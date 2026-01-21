part of '../../local_first.dart';

/// The central class that manages all repositories and coordinates synchronization.
///
/// This class is responsible for:
/// - Managing multiple [LocalFirstRepository] instances
/// - Coordinating bidirectional synchronization (push/pull)
/// - Maintaining sync state across nodes
/// - Providing access to the local database delegate
class LocalFirstClient {
  late final List<LocalFirstRepository> _repositories;
  final LocalFirstStorage _localStorage;
  final ConfigKeyValueStorage _configStorage;

  final List<DataSyncStrategy> syncStrategies;
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
  /// - [keyValueStorage]: Optional delegate for config key/value operations.
  ///   Defaults to [localStorage] when not provided.
  ///
  /// Throws [ArgumentError] if there are duplicate node names.
  LocalFirstClient({
    required List<LocalFirstRepository> repositories,
    required LocalFirstStorage localStorage,
    ConfigKeyValueStorage? keyValueStorage,
    required this.syncStrategies,
  }) : assert(
         syncStrategies.isNotEmpty,
         'You need to provide at least one sync strategy.',
       ),
       _localStorage = localStorage,
       _configStorage = keyValueStorage ?? localStorage {
    final names = repositories.map((n) => n.name).toSet();
    if (names.length != repositories.length) {
      throw ArgumentError('Duplicate node names');
    }
    for (var repository in repositories) {
      repository._client = this;
      repository._syncStrategies = syncStrategies;
    }
    for (final strategy in syncStrategies) {
      strategy.attach(this);
    }

    _repositories = List.unmodifiable(repositories);
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
    await _localStorage.initialize();
    if (!identical(_configStorage, _localStorage)) {
      await _configStorage.initialize();
    }

    for (var repository in _repositories) {
      await repository.initialize();
    }
    _onInitialize.complete();
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

  /// Switches the active namespace/database for both the main storage and the
  /// optional config storage delegate.
  Future<void> useNamespace(String namespace) async {
    await _localStorage.useNamespace(namespace);
    if (!identical(_configStorage, _localStorage)) {
      await _configStorage.useNamespace(namespace);
    }
  }

  /// Disposes the LocalFirstClient instance and closes the local database.
  ///
  /// Call this when you're done using the LocalFirstClient instance.
  Future<void> dispose() async {
    await _connectionController.close();
    if (!identical(_configStorage, _localStorage)) {
      await _configStorage.close();
    }
    await _localStorage.close();
  }

  Future<void> pullChanges({
    required String repositoryName,
    required List<JsonMap> changes,
  }) async {
    final repository = getRepositoryByName(repositoryName);
    for (final rawEvent in changes) {
      try {
        final event = repository.createEventFromRemote(rawEvent);
        await repository.mergeRemoteEvent(remoteEvent: event);
      } catch (e) {
        throw FormatException(
          'Malformed remote event for $repositoryName: $e | payload=$rawEvent',
        );
      }
    }
  }

  Future<LocalFirstEvents> getAllPendingEvents({
    required String repositoryName,
  }) async {
    final targets = _repositories.where((r) => r.name == repositoryName);
    final results = await Future.wait([
      for (var repository in targets) repository.getPendingEvents(),
    ]);
    return results.expand((e) => e).toList();
  }

  Future<String?> getConfigValue(String key) async {
    return await _configStorage.getConfigValue<String>(key);
  }

  Future<bool> setConfigValue(String key, String value) async {
    return await _configStorage.setConfigValue<String>(key, value);
  }

}

/// Test helper exposing internal state of [LocalFirstClient] for unit tests.
class TestHelperLocalFirstClient {
  final LocalFirstClient client;

  TestHelperLocalFirstClient(this.client);

  List<LocalFirstRepository> get repositories => client._repositories;
  Completer get onInitializeCompleter => client._onInitialize;
  StreamController<bool> get connectionController =>
      client._connectionController;
  bool? get latestConnection => client._latestConnection;
}
