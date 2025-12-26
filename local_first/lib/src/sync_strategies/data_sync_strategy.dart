part of '../../local_first.dart';

/// Defines the contract for different data synchronization strategies.
///
/// Implement this class to create custom sync strategies, such as:
/// - [PeriodicSyncStrategy]: Synchronizes data at a fixed time interval.
/// - [ManualSyncStrategy]: Triggers synchronization on demand.
/// - [ConnectivitySyncStrategy]: Synchronizes when network connectivity is restored.
/// - [WorkManagerSyncStrategy]: Uses a background service for robust synchronization.
/// - [WebSocketSyncStrategy]: Listens to a WebSocket for real-time updates.
abstract mixin class DataSyncStrategy<T> {
  late LocalFirstClient _client;

  void attach(LocalFirstClient client) {
    _client = client;
  }

  @visibleForTesting
  @protected
  LocalFirstClient get client => _client;

  /// Returns true when this strategy should handle the given event.
  bool supportsEvent(LocalFirstEvent event) => event.data is T;

  Future<SyncStatus> onPushToRemote(LocalFirstEvent<T> event);

  Future<List<LocalFirstEvent<T>>> getPendingObjects() async {
    final pending = await _client.getAllPendingObjects();
    return pending
        .where((event) => event.data is T)
        .map(
          (event) => LocalFirstEvent<T>(
            data: event.data as T,
            syncStatus: event.syncStatus,
            syncOperation: event.syncOperation,
            syncCreatedAt: event.syncCreatedAt,
            repositoryName: event.repositoryName,
          ),
        )
        .toList();
  }

  Future<void> pullChangesToLocal(Map<String, dynamic> remoteChanges) {
    return _client._pullRemoteChanges(remoteChanges);
  }
}
