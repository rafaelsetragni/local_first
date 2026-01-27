/// Real-time bidirectional synchronization strategy for LocalFirst framework using WebSockets.
///
/// This plugin enables instant synchronization between local and remote data stores
/// through persistent WebSocket connections, providing real-time updates and
/// automatic reconnection handling.
///
/// ## Features
///
/// - **Real-time Sync**: Immediate push and pull of data changes
/// - **Bidirectional**: Both client and server can initiate updates
/// - **Auto-Reconnection**: Handles network failures with configurable retry delays
/// - **Event Queue**: Optional queuing of events during disconnection
/// - **Heartbeat Monitoring**: Keeps connection alive with periodic ping/pong
/// - **Dynamic Authentication**: Update credentials without reconnecting
/// - **Connection State Tracking**: Reports connection status to UI
///
/// ## Usage
///
/// ```dart
/// import 'package:local_first_websocket/local_first_websocket.dart';
///
/// final wsStrategy = WebSocketSyncStrategy(
///   websocketUrl: 'ws://localhost:8080/sync',
///   authToken: 'your-auth-token',
///   headers: {'Authorization': 'Bearer your-token'},
///   reconnectDelay: Duration(seconds: 3),
///   heartbeatInterval: Duration(seconds: 30),
///   enablePendingQueue: true,
///   onBuildSyncFilter: (repositoryName) async {
///     // Return filter parameters for fetching events
///     final lastSync = await storage.getLastSync(repositoryName);
///     return lastSync != null ? {'since': lastSync} : null;
///   },
///   onSyncCompleted: (repositoryName, events) async {
///     // Save sync state after receiving events
///     if (events.isNotEmpty) {
///       await storage.saveLastSync(repositoryName, DateTime.now());
///     }
///   },
///   onAuthenticationFailed: () async {
///     // Optional: Handle auth failures by refreshing token
///     final newToken = await refreshToken();
///     return AuthCredentials(
///       authToken: newToken,
///       headers: {'Authorization': 'Bearer $newToken'},
///     );
///   },
/// );
///
/// final client = LocalFirstClient(
///   repositories: [userRepository, counterRepository],
///   localStorage: SqliteLocalFirstStorage(),
///   syncStrategies: [wsStrategy],
/// );
///
/// await client.initialize();
/// await wsStrategy.start();
/// ```
///
/// ## WebSocket Protocol
///
/// The strategy expects the server to implement this message protocol:
///
/// ### Client → Server Messages
///
/// - `auth`: Authentication with token/headers
/// - `push_event`: Push local event to server
/// - `request_events`: Request events for a repository
/// - `ping`: Heartbeat to keep connection alive
/// - `pong`: Response to server ping
///
/// ### Server → Client Messages
///
/// - `auth_success`: Authentication succeeded
/// - `events`: Remote events to apply locally
/// - `ack`: Acknowledgment of received event
/// - `sync_complete`: Initial synchronization complete
/// - `ping`: Heartbeat from server
/// - `pong`: Response to client ping
/// - `error`: Error message from server
///
/// ## Comparison with PeriodicSyncStrategy
///
/// | Feature | WebSocketSyncStrategy | PeriodicSyncStrategy |
/// |---------|---------------------|----------------------|
/// | Sync Timing | Real-time on event | Periodic intervals |
/// | Push Pattern | Immediate | Batched |
/// | Connection | Stateful WebSocket | Stateless HTTP/REST |
/// | Latency | Milliseconds | Seconds (sync interval) |
/// | Network Usage | Constant connection | Periodic requests |
/// | Best For | Real-time apps | REST APIs, polling |
///
library;

export 'src/websocket_sync_strategy.dart';
