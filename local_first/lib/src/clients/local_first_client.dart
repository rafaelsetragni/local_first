part of '../../local_first.dart';

/// The central class that manages all repositories and coordinates synchronization.
///
/// This class is responsible for:
/// - Managing multiple [LocalFirstRepository] instances
/// - Coordinating bidirectional synchronization (push/pull)
/// - Maintaining sync state across nodes
/// - Providing access to the local database delegate
class LocalFirstClient {
  final List<LocalFirstRepository> _repositories;
  final LocalFirstStorage _localStorage;
  final List<DataSyncStrategy> _globalSyncStrategies;
  final List<DataSyncStrategy> _allStrategies = [];
  bool _initialized = false;

  final Completer _onInitialize = Completer();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  bool? _latestConnection;

  Future get awaitInitialization => _onInitialize.future;

  /// Gets the local database delegate used for storage.
  LocalFirstStorage get localStorage => _localStorage;

  /// Emits connection state changes observed by sync strategies.
  void reportConnectionState(bool connected) {
    _latestConnection = connected;
    if (!_connectionController.isClosed) {
      _connectionController.add(connected);
    }
  }

  /// Stream of connection state changes pushed by sync strategies.
  Stream<bool> get connectionChanges => _connectionController.stream;

  /// Latest known connection state (if any).
  bool? get latestConnectionState => _latestConnection;

  /// Creates an instance of LocalFirstClient.
  ///
  /// Parameters:
  /// - [nodes]: List of [LocalFirstRepository] instances to be managed
  /// - [localStorage]: The local database delegate for storage operations
  ///
  /// Throws [ArgumentError] if there are duplicate node names.
  LocalFirstClient({
    required LocalFirstStorage localStorage,
    List<LocalFirstRepository>? repositories,
    List<DataSyncStrategy>? globalSyncStrategies,
  }) : _localStorage = localStorage,
       _repositories = List<LocalFirstRepository>.from(
         repositories ?? const [],
       ),
       _globalSyncStrategies = List<DataSyncStrategy>.from(
         globalSyncStrategies ?? const [],
       ) {
    assert(
      _repositories.map((r) => r.name).toSet().length == _repositories.length,
      'Duplicate repository names detected.',
    );
    assert(
      _repositories.map((r) => r.modelType).toSet().length ==
          _repositories.length,
      'Duplicate repository model types detected.',
    );
  }

  /// Strategies attached to this client (legacy + per-repository).
  List<DataSyncStrategy> get syncStrategies => _allStrategies;

  /// Registers a repository after client construction.
  void registerRepository(LocalFirstRepository repository) {
    assert(!_initialized, 'Cannot add repositories after initialization.');
    final exists = _repositories.any((r) => r.name == repository.name);
    assert(
      !exists,
      'Repository with name "${repository.name}" already exists.',
    );
    final sameType = _repositories.any(
      (r) => r.modelType == repository.modelType,
    );
    assert(
      !sameType,
      'Repository with model type "${repository.modelType}" already exists.',
    );
    _repositories.add(repository);
  }

  /// Registers a global strategy after client construction.
  void registerGlobalStrategy(DataSyncStrategy strategy) {
    assert(!_initialized, 'Cannot add strategies after initialization.');
    _globalSyncStrategies.add(strategy);
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
  Future<void> initialize() async {
    if (_initialized) return;

    await _localStorage.initialize();
    await Future.wait([_initializeRepositories(), _initializeStrategies()]);

    _onInitialize.complete();
    _initialized = true;
  }

  Future<void> _initializeRepositories() async {
    for (var repository in _repositories) {
      await repository.initialize(this);
      for (final strategy in repository._syncStrategies) {
        final compatible =
            strategy.modelType == dynamic ||
            strategy.modelType == repository.modelType;
        if (!compatible) continue;
        strategy._attach(this);
        strategy._bindRepository(repository);
      }
    }
  }

  Future<void> _initializeStrategies() async {
    final set = <DataSyncStrategy>{};

    // Attach global strategies (no repository binding) and collect.
    for (final strategy in _globalSyncStrategies) {
      strategy._attach(this);
      set.add(strategy);
    }

    // Collect per-repository strategies without duplication.
    for (final repo in _repositories) {
      set.addAll(repo._syncStrategies);
    }

    assert(
      set.every(
        (strategy) => _repositories.any(
          (repo) =>
              strategy.modelType == dynamic ||
              repo.modelType == strategy.modelType,
        ),
      ),
      'Orphan strategy has no compatible repository. Strategies must'
      ' have type dynamic or its respective repository registered.',
    );

    _allStrategies
      ..clear()
      ..addAll(set);
  }

  /// Clears all data from the local database.
  ///
  /// This will delete all stored data and reset all repositories.
  /// Use with caution as this operation cannot be undone.
  Future<void> clearAllData() async {
    await _localStorage.clearAllData();

    for (var repository in _repositories) {
      repository.reset();
    }
  }

  /// Opens a database/namespace in the configured local storage.
  Future<void> openDatabase(String namespace) =>
      _localStorage.openDatabase(namespace);

  /// Closes the currently opened database/namespace.
  Future<void> closeDatabase() => _localStorage.closeDatabase();

  /// Starts all attached sync strategies.
  Future<void> startSyncStrategies() =>
      Future.wait(_assertInitialized().map((s) => s.start()));

  /// Stops all attached sync strategies.
  Future<void> stopSyncStrategies() =>
      Future.wait(_assertInitialized().map((s) => s.stop()));

  /// Disposes the LocalFirstClient instance and closes the local database.
  ///
  /// Call this when you're done using the LocalFirstClient instance.
  Future<void> dispose() => Future.wait([
    _connectionController.close(),
    closeDatabase(),
    stopSyncStrategies(),
  ]);

  Future<LocalFirstEvents> getAllPendingEvents() async {
    final results = await Future.wait([
      for (var repository in _repositories) repository.getPendingEvents(),
    ]);
    return results.expand((e) => e).toList();
  }

  List<DataSyncStrategy> _assertInitialized() {
    assert(_initialized, 'LocalFirstClient not initialized.');
    return _allStrategies;
  }

  Future<String?> getKeyValue(String key) async {
    return await localStorage.getKey(key);
  }

  Future<void> setKeyValue(String key, String value) async {
    await localStorage.setKey(key, value);
  }

  Future<void> deleteKeyValue(String key) async {
    await localStorage.deleteKey(key);
  }
}
