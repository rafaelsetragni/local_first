part of '../../local_first.dart';

/// Defines the contract for different data synchronization strategies.
///
/// Implement this class to create custom sync strategies, such as:
/// - [PeriodicSyncStrategy]: Synchronizes data at a fixed time interval.
/// - [ManualSyncStrategy]: Triggers synchronization on demand.
/// - [ConnectivitySyncStrategy]: Synchronizes when network connectivity is restored.
/// - [WorkManagerSyncStrategy]: Uses a background service for robust synchronization.
/// - [WebSocketSyncStrategy]: Listens to a WebSocket for real-time updates.
abstract class DataSyncStrategy {
  late LocalFirstClient _client;

  void attach(LocalFirstClient client) {
    _client = client;
  }

  @visibleForTesting
  @protected
  LocalFirstClient get client => _client;

  Future<SyncStatus> onPushToRemote(LocalFirstEvent localData);

  Future<List<LocalFirstEvent>> getPendingObjects() {
    return _client.getAllPendingObjects();
  }

  Future<void> pullChangesToLocal(JsonMap<dynamic> remoteChanges) {
    return _client._pullRemoteChanges(remoteChanges);
  }

  /// Marks a set of local events as synchronized (status ok) after a
  /// successful push to the remote.
  Future<void> confirmLocalEvents(List<LocalFirstEvent> events) {
    return _client.confirmLocalEvents(events);
  }
}
