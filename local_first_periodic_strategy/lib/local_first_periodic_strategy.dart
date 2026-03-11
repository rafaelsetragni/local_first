/// A reusable periodic synchronization strategy plugin for LocalFirst framework.
///
/// This plugin provides a technical framework for periodic synchronization,
/// separating the sync orchestration logic from business-specific API calls.
///
/// ## Features
///
/// - **Periodic Timer**: Automatically syncs at configurable intervals
/// - **Push-then-Pull Pattern**: Pushes local changes first, then pulls remote changes
/// - **Connection Health Checks**: Optional ping callback for monitoring connectivity
/// - **Separation of Concerns**: Technical sync logic separated from business logic
/// - **Flexible Callbacks**: Implement your own API calls, filtering, and state management
///
/// ## Usage
///
/// ```dart
/// import 'package:local_first_periodic_strategy/local_first_periodic_strategy.dart';
///
/// final strategy = PeriodicSyncStrategy(
///   syncInterval: Duration(seconds: 5),
///   repositoryNames: ['user', 'counter_log'],
///   onFetchEvents: (repositoryName) async {
///     // Fetch events from your API
///     final response = await myApi.fetchEvents(repositoryName);
///     return response.events;
///   },
///   onPushEvents: (repositoryName, events) async {
///     // Push events to your API
///     final success = await myApi.pushEvents(repositoryName, events);
///     return success;
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
///   onPing: () async {
///     // Optional: Check if API is reachable
///     return await myApi.ping();
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
///
/// ## Comparison with WebSocketSyncStrategy
///
/// | Feature | PeriodicSyncStrategy | WebSocketSyncStrategy |
/// |---------|---------------------|----------------------|
/// | Sync Timing | Periodic intervals | Real-time on event |
/// | Push Pattern | Batched | Immediate |
/// | Connection | Stateless HTTP/REST | Stateful WebSocket |
/// | Best For | REST APIs, polling | Real-time updates |
///
library;

export 'periodic_sync_strategy.dart';
