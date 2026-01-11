part of '../../local_first.dart';

/// Defines the contract for different data synchronization strategies.
///
/// Implement this class to create custom sync strategies, such as:
/// - [PeriodicSyncStrategy]: Synchronizes data at a fixed time interval.
/// - [ManualSyncStrategy]: Triggers synchronization on demand.
/// - [ConnectivitySyncStrategy]: Synchronizes when network connectivity is restored.
/// - [WorkManagerSyncStrategy]: Uses a background service for robust synchronization.
/// - [WebSocketSyncStrategy]: Listens to a WebSocket for real-time updates.
abstract class DataSyncStrategy<T> {
  DataSyncStrategy() : modelType = T;

  /// Model type this strategy handles.
  final Type modelType;
  late LocalFirstClient _client;
  final List<LocalFirstRepository<T>> _repositories = [];

  void _attach(LocalFirstClient client) {
    _client = client;
  }

  /// Starts any background work needed by the strategy.
  Future<void> start() async {}

  /// Stops any background work started by [start].
  Future<void> stop() async {}

  /// Internal hook to bind the strategy to a repository (used by the client).
  void _bindRepository(LocalFirstRepository<T> repository) {
    if (!_repositories.contains(repository)) {
      _repositories.add(repository);
    }
  }

  /// Returns all repositories compatible with this strategy.
  @protected
  List<LocalFirstRepository<T>> get repositories {
    if (_repositories.isEmpty) {
      throw StateError('No repositories found for model type $modelType.');
    }
    return _repositories;
  }

  Future<SyncStatus> onPushToRemote(LocalFirstEvent<T> localData);

  /// Notifies listeners about connection state changes (e.g. connectivity loss).
  @protected
  void reportConnectionState(bool connected) {
    _client.reportConnectionState(connected);
  }

  /// Exposes the connection state stream maintained by the client.
  Stream<bool> get connectionChanges => _client.connectionChanges;

  /// Latest known connection state.
  bool? get latestConnectionState => _client.latestConnectionState;

  Future<List<LocalFirstEvent<T>>> getPendingEvents() {
    final repos = repositories;
    return Future.wait(
      repos.map((r) => r.getPendingEvents()),
    ).then((lists) => lists.expand((e) => e).toList());
  }
}
