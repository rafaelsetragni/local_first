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

  /// Waits for the client to finish initialization.
  Future get awaitInitialization => _onInitialize.future;

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

  /// Looks up a repository by name so you can call repository-specific methods.
  ///
  /// Throws [StateError] if no node with the given name exists.
  ///
  /// - [name]: Repository name to retrieve.
  LocalFirstRepository getRepositoryByName(String name) {
    return _repositories.firstWhere((repo) => repo.name == name);
  }

  /// Initializes the LocalFirstClient and all its repositories.
  ///
  /// Call this once before doing any reads/writes so the storages are ready and
  /// each repository can set up its schema/state.
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

  /// Starts all sync strategies.
  ///
  /// This is a convenience method that calls `start()` on all registered
  /// sync strategies. Strategies that implement `start()` will be initialized
  /// and begin their synchronization process.
  ///
  /// Note: Not all strategies may implement `start()`. This method uses
  /// dynamic invocation to check if the strategy has a `start()` method.
  /// If a strategy doesn't implement `start()`, it will be skipped silently.
  Future<void> startAllStrategies() async {
    for (final strategy in syncStrategies) {
      try {
        // Try to call start() method if it exists
        final dynamic dynamicStrategy = strategy;
        final result = dynamicStrategy.start();
        // If the result is a Future, await it
        if (result is Future) {
          await result;
        }
      } catch (e) {
        // Strategy doesn't implement start() or start() failed
        // Continue with other strategies
      }
    }
  }

  /// Stops all sync strategies.
  ///
  /// This is a convenience method that calls `stop()` on all registered
  /// sync strategies. Strategies that implement `stop()` will halt their
  /// synchronization process.
  ///
  /// Note: Not all strategies may implement `stop()`. This method uses
  /// dynamic invocation to check if the strategy has a `stop()` method.
  /// If a strategy doesn't implement `stop()`, it will be skipped silently.
  void stopAllStrategies() {
    for (final strategy in syncStrategies) {
      try {
        // Try to call stop() method if it exists
        final dynamic dynamicStrategy = strategy;
        dynamicStrategy.stop();
      } catch (e) {
        // Strategy doesn't implement stop() or stop() failed
        // Continue with other strategies
      }
    }
  }

  /// Clears all data from the local database.
  ///
  /// This wipes every table and reinitializes each repository. Use with
  /// caution—there is no undo.
  Future<void> clearAllData() async {
    await _localStorage.clearAllData();

    for (var repository in _repositories) {
      repository.reset();
      await repository.initialize();
    }
  }

  /// Switches the active namespace/database for both the main storage and the
  /// optional config storage delegate.
  ///
  /// - [namespace]: Target namespace name.
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

  /// Applies remote changes for a specific repository by parsing and merging
  /// each incoming event.
  ///
  /// Throws [FormatException] if any payload is malformed.
  ///
  /// - [repositoryName]: Name of the repository to apply changes to.
  /// - [changes]: Raw remote events to merge.
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

  /// Retrieves all pending events for the given repository name.
  ///
  /// - [repositoryName]: Target repository name.
  Future<LocalFirstEvents> getAllPendingEvents({
    required String repositoryName,
  }) async {
    final targets = _repositories.where((r) => r.name == repositoryName);
    final results = await Future.wait([
      for (var repository in targets) repository.getPendingEvents(),
    ]);
    return results.expand((e) => e).toList();
  }

  /// Reads a config value from the configured key/value storage.
  ///
  /// - [key]: Config key to read.
  Future<String?> getConfigValue(String key) async {
    return await _configStorage.getConfigValue<String>(key);
  }

  /// Writes a config value to the configured key/value storage.
  ///
  /// - [key]: Config key to write.
  /// - [value]: Config value to store.
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
