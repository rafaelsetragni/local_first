part of '../../local_first.dart';

/// The central class that manages all repositories and coordinates synchronization.
///
/// This class is responsible for:
/// - Managing multiple [LocalFirstRepository] instances
/// - Coordinating bidirectional synchronization (push/pull)
/// - Maintaining sync state across nodes
/// - Providing access to the local database delegate
class LocalFirstClient {
  final List<LocalFirstRepository> _repositories = [];
  final LocalFirstStorage _localStorage;
  final LocalFirstKeyValueStorage _metaStorage;

  final List<DataSyncStrategy> syncStrategies = [];
  final Completer _onInitialize = Completer();
  Future<void>? _initializeFuture;
  bool get _initialized => _onInitialize.isCompleted;

  Future get awaitInitialization => _onInitialize.future;

  /// Gets the local database delegate used for storage.
  LocalFirstStorage get localStorage => _localStorage;

  /// Creates an instance of LocalFirstClient.
  ///
  /// Parameters:
  /// - [repositories]: Optional list of [LocalFirstRepository] instances
  ///   to be managed. You can also call [registerRepositories] later.
  /// - [localStorage]: The local database delegate for storage operations
  /// - [syncStrategies]: Optional list of [DataSyncStrategy] instances.
  ///   You can also call [registerSyncStrategies] later.
  /// - [metaStorage]: Optional key/value storage for metadata.
  ///
  /// Throws [ArgumentError] if there are duplicate node names.
  LocalFirstClient({
    List<LocalFirstRepository> repositories = const [],
    required LocalFirstStorage localStorage,
    LocalFirstKeyValueStorage? metaStorage,
    List<DataSyncStrategy> syncStrategies = const [],
  }) : _localStorage = localStorage,
       _metaStorage = metaStorage ?? SharedPreferencesKeyValueStorage() {
    if (repositories.isNotEmpty) {
      registerRepositories(repositories);
    }
    if (syncStrategies.isNotEmpty) {
      registerSyncStrategies(syncStrategies);
    }
  }

  /// Registers repositories with the client.
  ///
  /// Call this before [initialize] when not providing repositories
  /// in the constructor.
  void registerRepositories(List<LocalFirstRepository> repositories) {
    if (repositories.isEmpty) return;
    if (_initialized) {
      throw StateError('Cannot register repositories after initialize');
    }
    final existingNames = _repositories.map((n) => n.name).toSet();
    final incomingNames = repositories.map((n) => n.name).toSet();
    if (incomingNames.length != repositories.length) {
      throw ArgumentError('Duplicate node names');
    }
    final overlap = existingNames.intersection(incomingNames);
    if (overlap.isNotEmpty) {
      throw ArgumentError('Duplicate node names');
    }
    for (var repository in repositories) {
      repository._client = this;
      repository._syncStrategies = List.unmodifiable(syncStrategies);
    }
    _repositories.addAll(repositories);
  }

  /// Registers sync strategies with the client.
  ///
  /// Call this before [initialize] when not providing strategies
  /// in the constructor.
  void registerSyncStrategies(List<DataSyncStrategy> strategies) {
    if (strategies.isEmpty) return;
    if (_initialized) {
      throw StateError('Cannot register sync strategies after initialize');
    }
    for (final strategy in strategies) {
      strategy.attach(this);
    }
    syncStrategies.addAll(strategies);
    for (final repository in _repositories) {
      repository._syncStrategies = List.unmodifiable(syncStrategies);
    }
  }

  /// Gets a repository by its name.
  ///
  /// Throws [StateError] if no node with the given name exists.
  LocalFirstRepository getRepositoryByName(String name) {
    return _repositories.firstWhere((repo) => repo.name == name);
  }

  /// Initializes the LocalFirstClient and all its repositories.
  ///
  /// This must be called before using any LocalFirstClient functionality.
  /// It initializes the local database and all registered repositories.
  Future<void> initialize() async => _initializeFuture ??= _runInitialize();

  Future<void> _runInitialize() async {
    try {
      assert(
        !_initialized,
        'Initialize should only be called once in the entire application.',
      );
      assert(
        _repositories.isNotEmpty,
        'You need to register at least one repository.',
      );
      assert(
        syncStrategies.isNotEmpty,
        'You need to provide at least one sync strategy.',
      );
      await _metaStorage.open();
      await _localStorage.initialize();
      if (!_onInitialize.isCompleted) {
        _onInitialize.complete();
      }
    } catch (e) {
      _initializeFuture = null;
      rethrow;
    }
  }

  /// Opens the local storage connection.
  Future<void> openStorage({String namespace = 'default'}) async {
    if (!_initialized) {
      await initialize();
    }
    await _localStorage.open(namespace: namespace);
    for (var repository in _repositories) {
      repository.reset();
      await repository.initialize();
    }
  }

  /// Closes the local storage connection.
  Future<void> closeStorage() async {
    await _localStorage.close();
  }

  /// Clears all data from the local database.
  ///
  /// This will delete all stored data and reset all repositories.
  /// Use with caution as this operation cannot be undone.
  Future<void> clearAllData() async {
    await _localStorage.clearAllData();

    for (var repository in _repositories) {
      repository.reset();
      await repository.initialize();
    }
  }

  /// Disposes the LocalFirstClient instance and closes the local database.
  ///
  /// Call this when you're done using the LocalFirstClient instance.
  Future<void> dispose() async {
    await _localStorage.close();
    await _metaStorage.close();
  }

  Future<void> _pullRemoteChanges(Map<String, dynamic> map) async {
    final LocalFirstResponse response = await _buildOfflineResponse(map);

    for (final MapEntry<LocalFirstRepository, List<LocalFirstEvent>> entry
        in response.changes.entries) {
      final LocalFirstRepository repository = entry.key;
      final List<LocalFirstEvent> remoteEvents = entry.value;
      await repository._mergeRemoteItems(remoteEvents);
    }

    for (final repository in _repositories) {
      await setKeyValue(
        '__last_sync__${repository.name}',
        response.timestamp.toIso8601String(),
      );
    }
  }

  Future<List<LocalFirstEvent>> getAllPendingObjects() async {
    final results = await Future.wait([
      for (var repository in _repositories) repository.getPendingObjects(),
    ]);
    final pending = results.expand((events) => events);
    return pending.toList();
  }

  Future<String?> getMeta(String key) async {
    return await _metaStorage.get(key);
  }

  Future<void> setKeyValue(String key, String value) async {
    await _metaStorage.set(key, value);
  }

  Future<LocalFirstResponse> _buildOfflineResponse(
    Map<String, dynamic> json,
  ) async {
    if (json['timestamp'] == null || json['changes'] == null) {
      throw FormatException('Invalid offline response format');
    }

    final timestamp = DateTime.parse(json['timestamp'] as String);
    final changesJson = json['changes'] as Map;
    final repositoryObjects = <LocalFirstRepository, List<LocalFirstEvent>>{};

    for (var repositoryName in changesJson.keys) {
      final repository = getRepositoryByName(repositoryName as String);
      final objects = <LocalFirstEvent>[];

      final repositoryChangeJson =
          changesJson[repositoryName] as Map<String, dynamic>;

      if (repositoryChangeJson.containsKey('insert')) {
        final inserts = (repositoryChangeJson['insert'] as List);
        for (var element in inserts) {
          final object = repository._buildRemoteEvent(
            Map<String, dynamic>.from(element),
            operation: SyncOperation.insert,
          );
          objects.add(object);
        }
      }
      if (repositoryChangeJson.containsKey('update')) {
        final updates = (repositoryChangeJson['update'] as List);
        for (var element in updates) {
          final object = repository._buildRemoteEvent(
            Map<String, dynamic>.from(element),
            operation: SyncOperation.update,
          );
          objects.add(object);
        }
      }
      if (repositoryChangeJson.containsKey('delete')) {
        final deleteIds = (repositoryChangeJson['delete'] as List<String>);
        for (var id in deleteIds) {
          final object = await repository._getById(id);
          if (object != null) {
            object._setSyncStatus(SyncStatus.ok);
            object._setSyncOperation(SyncOperation.delete);
            objects.add(object);
          }
        }
      }

      repositoryObjects[repository] = objects;
    }
    return LocalFirstResponse(changes: repositoryObjects, timestamp: timestamp);
  }
}
