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

  final List<DataSyncStrategy> syncStrategies;
  final Completer _onInitialize = Completer();

  Future get awaitInitialization => _onInitialize.future;

  /// Gets the local database delegate used for storage.
  LocalFirstStorage get localStorage => _localStorage;

  /// Creates an instance of LocalFirstClient.
  ///
  /// Parameters:
  /// - [nodes]: List of [LocalFirstRepository] instances to be managed
  /// - [localStorage]: The local database delegate for storage operations
  ///
  /// Throws [ArgumentError] if there are duplicate node names.
  LocalFirstClient({
    required List<LocalFirstRepository> repositories,
    required LocalFirstStorage localStorage,
    required this.syncStrategies,
  }) : assert(
         syncStrategies.isNotEmpty,
         'You need to provide at least one sync strategy.',
       ),
       _localStorage = localStorage {
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

  /// Disposes the LocalFirstClient instance and closes the local database.
  ///
  /// Call this when you're done using the LocalFirstClient instance.
  Future<void> dispose() async {
    await _localStorage.close();
  }

  Future<void> _pullRemoteChanges(Map<String, dynamic> map) async {
    final LocalFirstResponse response = await _buildOfflineResponse(map);

    for (final MapEntry<LocalFirstRepository, LocalFirstEvents> entry
        in response.changes.entries) {
      final LocalFirstRepository repository = entry.key;
      final LocalFirstEvents remoteEvents = entry.value;
      await repository._mergeRemoteEvents(remoteEvents);
    }

    for (final repository in _repositories) {
      await setKeyValue(
        '__last_sync__${repository.name}',
        response.timestamp.toIso8601String(),
      );
    }
  }

  Future<LocalFirstEvents> getAllPendingEvents() async {
    final results = await Future.wait([
      for (var repository in _repositories) repository.getPendingEvents(),
    ]);
    return results.expand((e) => e).toList();
  }

  Future<String?> getMeta(String key) async {
    return await localStorage.getMeta(key);
  }

  Future<void> setKeyValue(String key, String value) async {
    await localStorage.setMeta(key, value);
  }

  Future<LocalFirstResponse> _buildOfflineResponse(
    Map<String, dynamic> json,
  ) async {
    if (json['timestamp'] == null || json['changes'] == null) {
      throw FormatException('Invalid offline response format');
    }

    final timestamp = DateTime.parse(json['timestamp'] as String).toUtc();
    final changesJson = json['changes'] as Map;
    final repositoryEvents = <LocalFirstRepository, List<LocalFirstEvent>>{};

    for (var repositoryName in changesJson.keys) {
      final repository = getRepositoryByName(repositoryName as String);
      final events = <LocalFirstEvent>[];

      final repositoryChangeJson =
          changesJson[repositoryName] as Map<String, dynamic>;

      if (repositoryChangeJson.containsKey('insert')) {
        final inserts = (repositoryChangeJson['insert'] as List);
        for (var element in inserts) {
          final object = repository._buildRemoteObject(
            Map<String, dynamic>.from(element),
            operation: SyncOperation.insert,
          );
          events.add(object);
        }
      } else if (repositoryChangeJson.containsKey('update')) {
        final updates = (repositoryChangeJson['update'] as List);
        for (var element in updates) {
          final object = repository._buildRemoteObject(
            Map<String, dynamic>.from(element),
            operation: SyncOperation.update,
          );
          events.add(object);
        }
      } else if (repositoryChangeJson.containsKey('delete')) {
        final deleteIds = (repositoryChangeJson['delete'] as List<String>);
        for (var id in deleteIds) {
          final object = await repository._getById(id);
          if (object != null) {
            events.add(
              object.copyWith(
                syncStatus: SyncStatus.ok,
                syncOperation: SyncOperation.delete,
              ),
            );
          }
        }
      }

      repositoryEvents[repository] = events;
    }
    return LocalFirstResponse(changes: repositoryEvents, timestamp: timestamp);
  }
}
