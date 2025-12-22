part of '../../local_first.dart';

/// Defines the contract for different data synchronization strategies.
///
/// Implement this class to create custom sync strategies, such as:
/// - [PeriodicSyncStrategy]: Synchronizes data at a fixed time interval.
/// - [ManualSyncStrategy]: Triggers synchronization on demand.
/// - [ConnectivitySyncStrategy]: Synchronizes when network connectivity is restored.
/// - [WorkManagerSyncStrategy]: Uses a background service for robust synchronization.
/// - [WebSocketSyncStrategy]: Listens to a WebSocket for real-time updates.
abstract mixin class DataSyncStrategy {
  late LocalFirstClient _client;

  void attach(LocalFirstClient client) {
    _client = client;
  }

  @visibleForTesting
  @protected
  LocalFirstClient get client => _client;

  Future<SyncStatus> onPushToRemote(LocalFirstModel localData);

  Future<List<LocalFirstModel>> getPendingObjects() {
    return _client.getAllPendingObjects();
  }

  Future<void> pullChangesToLocal(Map<String, dynamic> remoteChanges) {
    return _client._pullRemoteChanges(remoteChanges);
  }
}
