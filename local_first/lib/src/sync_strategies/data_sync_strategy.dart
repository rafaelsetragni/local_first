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

  Future<SyncStatus> onPushToRemote(LocalFirstEvent localData) =>
      Future.value(SyncStatus.pending);

  /// Notifies listeners about connection state changes (e.g. connectivity loss).
  @protected
  void reportConnectionState(bool connected) {
    _client.reportConnectionState(connected);
  }

  /// Exposes the connection state stream maintained by the client.
  Stream<bool> get connectionChanges => _client.connectionChanges;

  /// Latest known connection state.
  bool? get latestConnectionState => _client.latestConnectionState;

  Future<LocalFirstEvents> getPendingEvents({required String repositoryName}) =>
      _client.getAllPendingEvents(repositoryName: repositoryName);

  Future<void> pullChangesToLocal({
    required String repositoryName,
    required List<JsonMap> remoteChanges,
  }) => _client.pullChanges(
    repositoryName: repositoryName,
    changes: remoteChanges,
  );

  /// Marks the provided events as successfully synchronized.
  ///
  /// Use this after pushing events to the remote endpoint to persist the
  /// `ok` status locally (and cascade the update to earlier events of
  /// the same record).
  Future<void> markEventsAsSynced(LocalFirstEvents events) async {
    final latestByRepoAndId =
        <LocalFirstRepository, Map<String, LocalFirstEvent>>{};

    for (final event in events) {
      final repo = event.repository;
      final repoEvents = latestByRepoAndId.putIfAbsent(repo, () => {});
      final current = repoEvents[event.dataId];
      if (current == null ||
          event.syncCreatedAt.isAfter(current.syncCreatedAt)) {
        repoEvents[event.dataId] = event;
      }
    }

    for (final repoEvents in latestByRepoAndId.values) {
      for (final event in repoEvents.values) {
        final updated = event.updateEventState(syncStatus: SyncStatus.ok);
        await updated.repository._updateEventStatus(updated);
        await updated.repository._markAllPreviousEventAsOk(updated);
      }
    }
  }
}
