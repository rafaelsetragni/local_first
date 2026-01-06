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
  final LocalFirstKeyValueStorage _kvStorage;
  final List<DataSyncStrategy> syncStrategies = [];
  final Completer<void> _onInitialize = Completer<void>();
  Future<void>? _initializeFuture;

  static const _defaultNamespace = 'default';
  String _currentDocNamespace = _defaultNamespace;
  String _currentKvNamespace = _defaultNamespace;

  bool get _initialized => _onInitialize.isCompleted;

  Future get awaitInitialization => _onInitialize.future;

  /// Gets the local database delegate used for storage.
  LocalFirstStorage get localStorage => _localStorage;

  /// Creates an instance of LocalFirstClient.
  ///
  /// Repositories and estratégias de sync podem ser registradas depois via
  /// [registerRepositories] e [registerSyncStrategies], mas sempre antes de
  /// [initialize].
  LocalFirstClient({
    List<LocalFirstRepository> repositories = const [],
    required LocalFirstStorage localStorage,
    required LocalFirstKeyValueStorage keyValueStorage,
    List<DataSyncStrategy> syncStrategies = const [],
  }) : _localStorage = localStorage,
       _kvStorage = keyValueStorage {
    if (repositories.isNotEmpty) {
      registerRepositories(repositories);
    }
    if (syncStrategies.isNotEmpty) {
      registerSyncStrategies(syncStrategies);
    }
  }

  /// Registers repositories before initialization.
  void registerRepositories(List<LocalFirstRepository> repositories) {
    if (repositories.isEmpty) return;
    if (_initialized) {
      throw StateError('Cannot register repositories after initialize');
    }
    final existingNames = _repositories.map((n) => n.name).toSet();
    final incomingNames = repositories.map((n) => n.name).toSet();
    if (incomingNames.length != repositories.length) {
      throw ArgumentError('Duplicate repository names in input');
    }
    if (existingNames.intersection(incomingNames).isNotEmpty) {
      throw ArgumentError('Duplicate repository names across registrations');
    }
    for (final repository in repositories) {
      repository._client = this;
      repository._syncStrategies = List.unmodifiable(syncStrategies);
      _repositories.add(repository);
    }
  }

  /// Registers sync strategies before initialization.
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

      await _kvStorage.open();
      await _localStorage.initialize();
      for (var repository in _repositories) {
        repository.reset();
        await repository.initialize();
      }
      if (!_onInitialize.isCompleted) {
        _onInitialize.complete();
      }
    } catch (e) {
      _initializeFuture = null;
      rethrow;
    }
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
    await _kvStorage.close();
  }

  /// Opens storages for a namespace (defaults to client's default).
  ///
  /// This closes, re-applies namespace (when supported) and re-opens.
  Future<void> openDocumentDatabase({
    String namespace = _defaultNamespace,
  }) async {
    if (!_initialized) {
      throw StateError(
        'LocalFirstClient.initialize must be called before opening storage',
      );
    }
    if (_currentDocNamespace == namespace &&
        _localStorage is! LocalFirstMemoryStorage) {
      return;
    }
    _currentDocNamespace = namespace;

    await _localStorage.close();
    if (_localStorage is LocalFirstMemoryStorage) {
      (_localStorage as LocalFirstMemoryStorage).useNamespace(namespace);
    }
    await _localStorage.initialize();

    for (final repository in _repositories) {
      repository.reset();
      await repository.initialize();
    }
  }

  /// Opens the key/value database for a namespace.
  Future<void> openKeyValueDatabase({
    String namespace = _defaultNamespace,
  }) async {
    if (!_initialized) {
      throw StateError(
        'LocalFirstClient.initialize must be called before opening storage',
      );
    }
    if (_currentKvNamespace == namespace) return;
    _currentKvNamespace = namespace;
    await _kvStorage.close();
    await _kvStorage.open(namespace: namespace);
  }

  /// Closes both storages without disposing the client.
  Future<void> closeStorage() async {
    await _localStorage.close();
    await _kvStorage.close();
  }

  /// Applies remote changes grouped by repository name.
  ///
  /// Expected shape:
  /// {
  ///   "repoName": {
  ///     "server_sequence": 123,
  ///     "events": [ ... ]
  ///   },
  ///   ...
  /// }
  Future<void> _pullRemoteChanges(JsonMap<dynamic> map) {
    return Future.wait([
      for (final repoName in map.keys)
        _pullRemoteRepositoryChanges(
          repositoryName: repoName.toString(),
          payload: map[repoName] as JsonMap<dynamic>,
        ).catchError((e, s) {
          throw _PullRepositoryException(repoName.toString(), e, s);
        }),
    ]);
  }

  Future<void> _pullRemoteRepositoryChanges({
    required String repositoryName,
    required JsonMap<dynamic> payload,
  }) async {
    final repo = getRepositoryByName(repositoryName);
    if (repo == null) {
      throw StateError('Repository $repositoryName not registered');
    }

    final serverSeq = payload['server_sequence'];
    if (serverSeq is! int) {
      throw FormatException('Missing server_sequence for $repositoryName');
    }

    final eventsJson = payload['events'];
    if (eventsJson is! List) {
      throw FormatException('Missing events list for $repositoryName');
    }

    final rawEvents = eventsJson
        .map((e) => JsonMap<dynamic>.from(e as Map))
        .toList(growable: false);

    await repo._mergeRemoteEventMaps(rawEvents);
    await setKeyValue(
      _getServerSequenceKey(repositoryName: repositoryName),
      serverSeq.toString(),
    );
  }

  Future<LocalFirstEvents> getAllPendingObjects() async {
    final results = await Future.wait([
      for (var repository in _repositories) repository.getPendingObjects(),
    ]);
    return results.expand((e) => e).toList();
  }

  /// Marks events as synchronized (status ok) across repositories.
  Future<void> confirmLocalEvents(List<LocalFirstEvent> events) async {
    final grouped = events.groupByRepository();
    for (final repository in _repositories) {
      final repoEvents = grouped[repository.name];
      if (repoEvents == null || repoEvents.isEmpty) continue;
      await repository.markEventsAsSynced(
        repoEvents.cast<LocalFirstEvent<Object?>>(),
      );
    }
  }

  Future<T?> getKeyValue<T>(String key) async {
    return await _kvStorage.get<T>(key);
  }

  Future<void> setKeyValue<T>(String key, T value) async {
    await _kvStorage.set<T>(key, value);
  }

  String _getServerSequenceKey({required String repositoryName}) =>
      '_last_sync_seq_$repositoryName';

  /// Returns the last server sequence stored for a repository, if any.
  Future<int?> getLastServerSequence(String repositoryName) async {
    final raw = await _kvStorage.get<String>(
      _getServerSequenceKey(repositoryName: repositoryName),
    );
    return raw == null ? null : int.tryParse(raw);
  }
}

class _PullRepositoryException implements Exception {
  _PullRepositoryException(this.repository, this.error, this.stackTrace);
  final String repository;
  final Object error;
  final StackTrace stackTrace;

  @override
  String toString() => 'Pull failed for repository $repository: $error';
}
