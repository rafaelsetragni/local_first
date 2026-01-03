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
  /// Returns the repository with the given name, or null if not found.
  LocalFirstRepository? getRepositoryByName(String name) {
    for (final repo in _repositories) {
      if (repo.name == name) return repo;
    }
    return null;
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

  Future<void> _pullRemoteChanges(JsonMap map) {
    return Future.wait([
      for (final repositoryName in map.keys)
        _pullRemoteRepositoryChanges(
          repositoryName: repositoryName,
          changes: map[repositoryName] as JsonMap,
        ),
    ]);
  }

  Future<void> _pullRemoteRepositoryChanges({
    required String repositoryName,
    required JsonMap changes,
  }) {
    final repository = getRepositoryByName(repositoryName);
    if (repository == null) {
      throw Exception('Repository $repositoryName not registered');
    }

    final repositoryChangeJson = changes[repositoryName] as JsonMap;
    final repoServerSequence = repositoryChangeJson['sequence'];
    if (repoServerSequence is! int) {
      throw FormatException('Missing serverSequence for $repositoryName');
    }

    return Future.wait([
      setKeyValue(
        _getServerSequenceKey(repositoryName: repositoryName),
        repoServerSequence,
      ),
      repository._pullRemoteChanges(changes: repositoryChangeJson),
    ]);
  }

  Future<int?> getLastServerSequence({required String repositoryName}) =>
      getKeyValue<int>(_getServerSequenceKey(repositoryName: repositoryName));

  Future<List<LocalFirstEvent>> getAllPendingObjects() async {
    final results = await Future.wait([
      for (var repository in _repositories) repository.getPendingObjects(),
    ]);
    final pending = results.expand((events) => events);
    return pending.toList();
  }

  Future<T?> getKeyValue<T>(String key) => _metaStorage.get(key);

  Future<void> setKeyValue<T>(String key, T value) =>
      _metaStorage.set<T>(key, value);

  Future<void> deleteKeyValue<T>(String key) => _metaStorage.delete(key);

  String _getServerSequenceKey({required String repositoryName}) =>
      '_last_sync_seq_$repositoryName';
}
