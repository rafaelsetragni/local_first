import 'dart:async';
import 'dart:developer' as dev;
import 'package:local_first/local_first.dart';

/// Callback for fetching remote events for a repository.
///
/// The implementation should use [BuildSyncFilterCallback] to get filter
/// parameters (e.g., last sync timestamp, last sequence number) and fetch
/// only new events from the remote server.
///
/// [repositoryName] The name of the repository to fetch events for
///
/// Returns a list of events as JSON maps that should be applied locally
typedef FetchEventsCallback = Future<List<JsonMap>> Function(
  String repositoryName,
);

/// Callback for pushing local events to remote server.
///
/// [repositoryName] The name of the repository to push events to
/// [events] List of events to push as LocalFirstEvent objects
///
/// Returns true if push was successful
typedef PushEventsCallback = Future<bool> Function(
  String repositoryName,
  LocalFirstEvents events,
);

/// Callback for building sync filter parameters for a repository.
///
/// This is called before fetching events to determine what filter parameters
/// to use (e.g., timestamp, sequence number, etc.). The implementation should
/// track sync state (last sync timestamp, last sequence, etc.) and return
/// the appropriate filter parameters for the business logic.
///
/// Return null or empty map to request all events.
typedef BuildSyncFilterCallback = Future<JsonMap<dynamic>?> Function(
  String repositoryName,
);

/// Callback for saving sync state after events are successfully applied.
///
/// This is called after remote events are applied locally. The implementation
/// should save the sync state (last sync timestamp, last sequence, etc.) so
/// that the next sync can fetch only new events.
typedef SaveSyncStateCallback = Future<void> Function(
  String repositoryName,
  List<JsonMap<dynamic>> events,
);

/// Callback for checking connection health.
///
/// Returns true if connection is healthy
typedef PingCallback = Future<bool> Function();

/// A reusable periodic synchronization strategy that separates technical
/// implementation from business logic.
///
/// This strategy implements a periodic timer that orchestrates the sync process:
/// 1. Push pending local events to remote
/// 2. Pull remote events and apply them locally
///
/// Business logic (API calls, repository-specific rules) is provided through
/// callbacks.
///
/// Example usage:
/// ```dart
/// final strategy = PeriodicSyncStrategy(
///   syncInterval: Duration(seconds: 5),
///   repositoryNames: ['user', 'counter_log'],
///   onFetchEvents: (repositoryName) async {
///     // Fetch events from your API
///     final response = await api.fetchEvents(repositoryName);
///     return response.events;
///   },
///   onPushEvents: (repositoryName, events) async {
///     // Push events to your API
///     return await api.pushEvents(repositoryName, events);
///   },
///   onBuildSyncFilter: (repositoryName) async {
///     // Return filter parameters based on last sync state
///     final lastSeq = await storage.getLastSequence(repositoryName);
///     return lastSeq != null ? {'afterSequence': lastSeq} : null;
///   },
///   onSaveSyncState: (repositoryName, events) async {
///     // Save sync state after applying events
///     if (events.isNotEmpty) {
///       final maxSeq = events.map((e) => e['sequence']).reduce(max);
///       await storage.saveLastSequence(repositoryName, maxSeq);
///     }
///   },
/// );
///
/// final client = LocalFirstClient(
///   repositories: [userRepository, counterLogRepository],
///   localStorage: SqliteLocalFirstStorage(),
///   syncStrategies: [strategy],
/// );
///
/// await client.initialize();
/// await strategy.start();
/// ```
class PeriodicSyncStrategy extends DataSyncStrategy {
  static const logTag = 'PeriodicSyncStrategy';

  /// Interval between sync cycles
  final Duration syncInterval;

  /// List of repository names to synchronize
  final List<String> repositoryNames;

  /// Callback to fetch remote events
  final FetchEventsCallback onFetchEvents;

  /// Callback to push local events
  final PushEventsCallback onPushEvents;

  /// Callback to build sync filter parameters
  final BuildSyncFilterCallback onBuildSyncFilter;

  /// Callback to save sync state after applying events
  final SaveSyncStateCallback onSaveSyncState;

  /// Optional callback to check connection health
  final PingCallback? onPing;

  Timer? _syncTimer;
  bool _isRunning = false;
  bool _isSyncing = false;

  PeriodicSyncStrategy({
    required this.syncInterval,
    required this.repositoryNames,
    required this.onFetchEvents,
    required this.onPushEvents,
    required this.onBuildSyncFilter,
    required this.onSaveSyncState,
    this.onPing,
  });

  /// Starts the periodic synchronization.
  ///
  /// This should be called after the LocalFirstClient is initialized.
  Future<void> start() async {
    if (_isRunning) return;

    dev.log('Starting periodic sync strategy', name: logTag);
    await client.awaitInitialization;

    _isRunning = true;

    // Report connected state
    reportConnectionState(true);

    // Start periodic sync timer
    _syncTimer = Timer.periodic(syncInterval, (_) => _performSync());

    // Perform initial sync
    await _performSync();
  }

  /// Stops the periodic synchronization.
  void stop() {
    dev.log('Stopping periodic sync strategy', name: logTag);

    _isRunning = false;
    _syncTimer?.cancel();
    _syncTimer = null;

    reportConnectionState(false);
  }

  /// Disposes of all resources.
  void dispose() {
    stop();
  }

  /// Performs a full sync cycle: push pending events, then pull remote events
  Future<void> _performSync() async {
    if (_isSyncing || !_isRunning) return;

    _isSyncing = true;

    try {
      // Optional: Check connection health
      if (onPing != null) {
        try {
          final isHealthy = await onPing!();
          if (!isHealthy) {
            reportConnectionState(false);
            dev.log('Connection health check failed', name: logTag);
            return;
          }
        } catch (e, s) {
          dev.log(
            'Error in onPing callback: $e',
            name: logTag,
            error: e,
            stackTrace: s,
          );
          reportConnectionState(false);
          return;
        }
      }

      reportConnectionState(true);

      // Phase 1: Push pending local events to remote
      await _pushPendingEvents();

      // Phase 2: Pull remote events and apply them locally
      await _pullRemoteEvents();

      dev.log('Sync cycle completed', name: logTag);
    } catch (e, s) {
      dev.log(
        'Sync error: $e',
        name: logTag,
        error: e,
        stackTrace: s,
      );
      reportConnectionState(false);
    } finally {
      _isSyncing = false;
    }
  }

  /// Push all pending local events to the remote server
  Future<void> _pushPendingEvents() async {
    for (final repositoryName in repositoryNames) {
      try {
        // Get pending events from local storage
        final pendingEvents = await getPendingEvents(
          repositoryName: repositoryName,
        );

        if (pendingEvents.isEmpty) continue;

        dev.log(
          'Pushing ${pendingEvents.length} events for $repositoryName',
          name: logTag,
        );

        // Push events using business logic callback
        final success = await onPushEvents(repositoryName, pendingEvents);

        if (success) {
          // Mark events as synced
          await markEventsAsSynced(pendingEvents);
          dev.log(
            'Successfully pushed ${pendingEvents.length} events for $repositoryName',
            name: logTag,
          );
        } else {
          dev.log(
            'Failed to push events for $repositoryName',
            name: logTag,
          );
        }
      } catch (e, s) {
        // Log error but continue with other repositories
        dev.log(
          'Error pushing events for $repositoryName: $e',
          name: logTag,
          error: e,
          stackTrace: s,
        );
      }
    }
  }

  /// Pull remote events from the server and apply them locally
  Future<void> _pullRemoteEvents() async {
    for (final repositoryName in repositoryNames) {
      try {
        // Fetch remote events using business logic callback
        // The callback should use onBuildSyncFilter to get filter parameters
        final remoteEvents = await onFetchEvents(repositoryName);

        if (remoteEvents.isEmpty) continue;

        dev.log(
          'Applying ${remoteEvents.length} remote events for $repositoryName',
          name: logTag,
        );

        // Apply remote events to local storage using base class method
        await pullChangesToLocal(
          repositoryName: repositoryName,
          remoteChanges: remoteEvents,
        );

        // Save sync state via callback
        try {
          await onSaveSyncState(repositoryName, remoteEvents);
        } catch (e, s) {
          dev.log(
            'Error in onSaveSyncState callback for $repositoryName: $e',
            name: logTag,
            error: e,
            stackTrace: s,
          );
        }

        dev.log(
          'Successfully applied ${remoteEvents.length} events for $repositoryName',
          name: logTag,
        );
      } catch (e, s) {
        // Log error but continue with other repositories
        dev.log(
          'Error pulling events for $repositoryName: $e',
          name: logTag,
          error: e,
          stackTrace: s,
        );
      }
    }
  }

  /// Implementation of push: queues event for next sync cycle
  ///
  /// Unlike WebSocketSyncStrategy which sends events immediately,
  /// PeriodicSyncStrategy batches events and sends them during the next
  /// sync cycle.
  @override
  Future<SyncStatus> onPushToRemote(LocalFirstEvent localData) async {
    // Events are automatically pushed during the next sync cycle
    // Return pending status to indicate they need to be synced
    dev.log(
      'Event queued for next sync: ${localData.eventId}',
      name: logTag,
    );
    return SyncStatus.pending;
  }
}
