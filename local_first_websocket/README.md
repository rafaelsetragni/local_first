# local_first_websocket

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](#)
[![Discord](https://img.shields.io/discord/888523488376279050.svg?style=for-the-badge&colorA=7289da&label=Chat%20on%20Discord)](https://discord.awesome-notifications.carda.me)

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=103)](#)
[![pub package](https://img.shields.io/pub/v/local_first_websocket.svg)](https://pub.dev/packages/local_first_websocket)
![Full tests workflow](https://github.com/rafaelsetragni/local_first/actions/workflows/dart.yml/badge.svg?branch=main)
[![codecov](https://codecov.io/github/rafaelsetragni/local_first/graph/badge.svg?token=7BRG8JcWTQ)](https://codecov.io/github/rafaelsetragni/local_first)

<br>

A real-time bidirectional synchronization strategy plugin for the [LocalFirst](https://pub.dev/packages/local_first) framework. This plugin provides instant, WebSocket-based synchronization for building collaborative and real-time applications.

> **Note:** This is a companion package to `local_first`. You need to install the core package first.

## Why local_first_websocket?

- **Real-time synchronization**: Changes propagate instantly to all connected clients
- **Bidirectional sync**: Both push (local → remote) and pull (remote → local) operations
- **Production-ready**: Automatic reconnection, heartbeat monitoring, and event queuing
- **Flexible authentication**: Support for tokens and custom headers with dynamic updates
- **Connection resilience**: Handles network issues gracefully with configurable retry logic
- **Developer-friendly**: Clear protocol, comprehensive logging, and easy integration

## Features

- ✅ **Instant Sync**: Changes are pushed immediately via persistent WebSocket connection
- ✅ **Automatic Reconnection**: Handles connection loss with configurable retry delay
- ✅ **Event Queue**: Queues pending events during disconnection for later sync
- ✅ **Heartbeat Monitoring**: Keeps connection alive with periodic ping/pong messages
- ✅ **Connection State Tracking**: Reports connection status to the UI in real-time
- ✅ **Dynamic Authentication**: Update tokens and headers without reconnecting
- ✅ **Conflict Resolution**: Integrates with LocalFirst's conflict resolution strategies
- ✅ **Event Acknowledgment**: Server confirms successful event processing

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  local_first: ^0.6.0
  local_first_websocket: ^1.0.0
  # Choose your storage adapter
  local_first_hive_storage: ^0.2.0  # or
  local_first_sqlite_storage: ^0.2.0
```

Then install it with:

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:local_first/local_first.dart';
import 'package:local_first_websocket/local_first_websocket.dart';

// 1) Create WebSocket sync strategy
final wsStrategy = WebSocketSyncStrategy(
  websocketUrl: 'ws://your-server.com/sync',
  reconnectDelay: Duration(seconds: 3),
  heartbeatInterval: Duration(seconds: 30),
  authToken: 'your-auth-token', // Optional
);

// 2) Initialize client with WebSocket strategy
final client = LocalFirstClient(
  repositories: [userRepository, todoRepository],
  localStorage: HiveLocalFirstStorage(),
  syncStrategies: [wsStrategy],
);

await client.initialize();
await wsStrategy.start();

// 3) Listen to connection state changes
wsStrategy.connectionChanges.listen((isConnected) {
  print('WebSocket ${isConnected ? "connected" : "disconnected"}');
});

// 4) Use repositories normally - sync happens automatically
await todoRepository.upsert(
  Todo(id: '1', title: 'Buy milk'),
  needSync: true, // Event pushed immediately to server
);
```

## How It Works

### Architecture

```
┌─────────────────────────────────────────┐
│         Flutter Application             │
│  ┌───────────────────────────────────┐  │
│  │  LocalFirst Repositories          │  │
│  │  - Create/Update/Delete           │  │
│  └───────────────┬───────────────────┘  │
│                  │                       │
│  ┌───────────────▼───────────────────┐  │
│  │  WebSocketSyncStrategy            │  │
│  │  - Instant event push             │  │
│  │  - Real-time event pull           │  │
│  │  - Reconnection logic             │  │
│  │  - Event queue management         │  │
│  └───────────────┬───────────────────┘  │
└──────────────────┼───────────────────────┘
                   │ WebSocket (persistent)
┌──────────────────▼───────────────────────┐
│         WebSocket Server                 │
│  ┌───────────────────────────────────┐   │
│  │  Protocol Handler                 │   │
│  │  - auth, ping/pong                │   │
│  │  - push_event, push_events_batch  │   │
│  │  - request_events, events         │   │
│  │  - ack, sync_complete             │   │
│  └───────────────┬───────────────────┘   │
└──────────────────┼───────────────────────┘
                   │
┌──────────────────▼───────────────────────┐
│            Database (MongoDB)            │
│  - Event storage                         │
│  - Event deduplication                   │
│  - Query filtering                       │
└──────────────────────────────────────────┘
```

### Push Flow

When data changes locally:

1. **User Action**: Create/update/delete data via repository
2. **Event Creation**: LocalFirst creates event with `SyncStatus.pending`
3. **Immediate Push**: `WebSocketSyncStrategy.onPushToRemote()` is called
4. **Send or Queue**:
   - If connected: sends event via WebSocket immediately
   - If disconnected: adds event to pending queue
5. **Server Acknowledgment**: Server responds with ACK message
6. **Mark Synced**: Strategy marks event as `SyncStatus.ok`

### Pull Flow

When server has new data:

1. **Server Push**: Server sends `events` message with new/updated data
2. **Apply Locally**: Strategy calls `pullChangesToLocal()` to apply changes
3. **Conflict Resolution**: LocalFirst merges remote changes, handling conflicts
4. **Confirm Receipt**: Strategy sends confirmation to server
5. **UI Update**: Repository streams automatically notify UI

### Reconnection Flow

When connection is lost:

1. **Connection Lost**: Network issue, server restart, etc.
2. **Report State**: Strategy reports `connectionState: false`
3. **Queue Events**: Pending events are queued locally
4. **Retry Logic**: After `reconnectDelay`, attempts to reconnect
5. **Catch Up**: On reconnect, requests missed events via `request_events`
6. **Flush Queue**: Sends all pending events to server
7. **Resume**: Reports `connectionState: true`, normal operation resumes

## Configuration Options

### Reconnection Delay

Control how long to wait before attempting to reconnect:

```dart
final wsStrategy = WebSocketSyncStrategy(
  websocketUrl: 'ws://your-server.com/sync',
  reconnectDelay: Duration(seconds: 5), // Wait 5s before reconnecting
);
```

**Recommendations:**
- 📱 Mobile apps: 3-5 seconds (balance between responsiveness and battery)
- 💻 Desktop apps: 2-3 seconds (faster reconnection expected)
- 🌐 Web apps: 3-5 seconds (similar to mobile)

### Heartbeat Interval

Configure how often to send ping messages to keep connection alive:

```dart
final wsStrategy = WebSocketSyncStrategy(
  websocketUrl: 'ws://your-server.com/sync',
  heartbeatInterval: Duration(seconds: 60), // Ping every 60s
);
```

**Recommendations:**
- Default: 30 seconds (good balance)
- Behind proxy/load balancer: 20-30 seconds (prevent timeout)
- Direct connection: 45-60 seconds (reduce overhead)

### Custom Headers

Add authentication or custom headers:

```dart
final wsStrategy = WebSocketSyncStrategy(
  websocketUrl: 'ws://your-server.com/sync',
  headers: {
    'Authorization': 'Bearer your-token',
    'X-Custom-Header': 'value',
  },
);
```

### Authentication Token

Simplified authentication with token:

```dart
final wsStrategy = WebSocketSyncStrategy(
  websocketUrl: 'ws://your-server.com/sync',
  authToken: 'your-auth-token',
);
```

## Dynamic Authentication Updates

Update authentication credentials without disconnecting:

### Update Only Token

```dart
wsStrategy.updateAuthToken('new-token-here');
```

### Update Only Headers

```dart
wsStrategy.updateHeaders({
  'Authorization': 'Bearer new-token',
  'X-Custom-Header': 'value',
});
```

### Update Both at Once

```dart
wsStrategy.updateCredentials(
  authToken: 'new-token',
  headers: {'X-Custom-Header': 'value'},
);
```

**Note**: If the WebSocket is currently connected, updating credentials will automatically re-authenticate with the server using the new credentials.

### Example: JWT Token Refresh

```dart
class AuthService {
  final WebSocketSyncStrategy wsStrategy;
  Timer? _refreshTimer;

  AuthService(this.wsStrategy);

  void startTokenRefresh() {
    // Refresh token every 50 minutes (assuming 60-minute expiry)
    _refreshTimer = Timer.periodic(Duration(minutes: 50), (_) async {
      final newToken = await refreshJWTToken();
      wsStrategy.updateAuthToken(newToken);
      print('Token refreshed and WebSocket re-authenticated');
    });
  }

  void stopTokenRefresh() {
    _refreshTimer?.cancel();
  }

  Future<String> refreshJWTToken() async {
    // Your token refresh logic here
    final response = await http.post(
      Uri.parse('https://api.example.com/auth/refresh'),
      headers: {'Authorization': 'Bearer $oldRefreshToken'},
    );
    return jsonDecode(response.body)['token'];
  }
}
```

## WebSocket Server Protocol

The server must implement the following message protocol:

### Client → Server Messages

#### Authentication
```json
{
  "type": "auth",
  "token": "your-auth-token"
}
```

#### Heartbeat
```json
{
  "type": "ping"
}
```

#### Push Single Event
```json
{
  "type": "push_event",
  "repository": "users",
  "event": {
    "eventId": "event-uuid",
    "operation": 0,
    "createdAt": "2025-01-23T10:00:00.000Z",
    "data": { ... }
  }
}
```

#### Push Multiple Events (Batch)
```json
{
  "type": "push_events_batch",
  "repository": "users",
  "events": [ ... ]
}
```

#### Request Events Since Timestamp
```json
{
  "type": "request_events",
  "repository": "users",
  "since": "2025-01-23T10:00:00.000Z"
}
```

#### Request All Events
```json
{
  "type": "request_all_events"
}
```

#### Confirm Events Received
```json
{
  "type": "events_received",
  "repository": "users",
  "count": 5
}
```

### Server → Client Messages

#### Authentication Success
```json
{
  "type": "auth_success"
}
```

#### Heartbeat Response
```json
{
  "type": "pong"
}
```

#### Send Events to Client
```json
{
  "type": "events",
  "repository": "users",
  "events": [
    {
      "eventId": "event-uuid",
      "operation": 0,
      "createdAt": "2025-01-23T10:00:00.000Z",
      "data": { ... }
    }
  ]
}
```

#### Acknowledge Received Events
```json
{
  "type": "ack",
  "eventIds": ["event-uuid-1", "event-uuid-2"],
  "repositories": {
    "users": ["event-uuid-1"],
    "todos": ["event-uuid-2"]
  }
}
```

#### Sync Complete
```json
{
  "type": "sync_complete",
  "repository": "users"
}
```

#### Error
```json
{
  "type": "error",
  "message": "Error description"
}
```

## Comparison with Other Strategies

| Feature | WebSocketSyncStrategy | PeriodicSyncStrategy |
|---------|----------------------|---------------------|
| **Sync Timing** | Real-time on event | Periodic intervals |
| **Push Pattern** | Immediate | Batched |
| **Pull Pattern** | Server-initiated | Client-initiated |
| **Connection** | Stateful WebSocket | Stateless HTTP/REST |
| **Best For** | Real-time collaboration, chat, live updates | REST APIs, batch sync, polling |
| **Complexity** | Moderate | Simple |
| **Battery Usage** | Higher (always connected) | Low (configurable interval) |
| **Latency** | Lowest (~10-50ms) | Medium (depends on interval) |
| **Scalability** | Requires WebSocket support | Works with any REST API |

## Running the Example

The example includes a complete WebSocket server implementation using the Dart server and MongoDB.

### Prerequisites

- Flutter SDK (>= 3.10.0)
- Docker (for MongoDB)
- Dart SDK (for server)

### 1. Start the Server

From the monorepo root, run:

```bash
melos server:start
```

This command automatically:
- ✅ Starts MongoDB with Docker Compose
- ✅ Starts the Dart WebSocket server on port 8080
- ✅ Configures networking between services
- ✅ Shows real-time logs

**Or manually:**

```bash
# Start MongoDB
docker run -d --name local_first_mongodb -p 27017:27017 \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=admin mongo:7

# Start the server
cd server && dart run websocket_server.dart
```

The server will start on `ws://localhost:8080/sync`

### 2. Run the Flutter App

```bash
cd local_first_websocket/example
flutter pub get
flutter run
```

## Best Practices

### 1. Handle Connection State in UI

Show connection status to users:

```dart
StreamBuilder<bool>(
  stream: wsStrategy.connectionChanges,
  builder: (context, snapshot) {
    final isConnected = snapshot.data ?? false;
    return Banner(
      message: isConnected ? 'Connected' : 'Offline',
      color: isConnected ? Colors.green : Colors.red,
    );
  },
)
```

### 2. Implement Token Refresh

For JWT or expiring tokens, refresh before expiry:

```dart
// Refresh every 50 minutes for 60-minute tokens
Timer.periodic(Duration(minutes: 50), (_) async {
  final newToken = await refreshToken();
  wsStrategy.updateAuthToken(newToken);
});
```

### 3. Use Appropriate Heartbeat Intervals

- Too frequent: Wastes battery and bandwidth
- Too infrequent: Connection may be closed by proxies
- Recommended: 30 seconds for most scenarios

### 4. Handle Offline Mode Gracefully

Let LocalFirst handle offline state:

```dart
// Events are automatically queued when offline
await todoRepository.upsert(todo, needSync: true);
// Will sync automatically when connection is restored
```

### 5. Monitor Performance

Log sync times to identify bottlenecks:

```dart
wsStrategy.connectionChanges.listen((isConnected) {
  if (isConnected) {
    final syncStart = DateTime.now();
    // Monitor how long catch-up sync takes
  }
});
```

## Troubleshooting

### WebSocket Connection Fails

**Symptoms:** App shows "disconnected", no syncing happens

**Solutions:**
1. Verify server is running and accessible:
   ```bash
   curl http://localhost:8080/api/health
   ```
2. Check WebSocket URL format:
   ```dart
   // Correct
   websocketUrl: 'ws://localhost:8080/sync'
   // NOT
   websocketUrl: 'http://localhost:8080/sync'
   ```
3. For mobile/emulator, use correct host:
   - Android emulator: `ws://10.0.2.2:8080/sync`
   - iOS simulator: `ws://localhost:8080/sync`
   - Physical device: `ws://192.168.x.x:8080/sync`

### Authentication Fails

**Symptoms:** Connection opens but immediately closes

**Solutions:**
1. Verify auth token is valid
2. Check server logs for authentication errors
3. Ensure server responds with `auth_success` message

### Events Not Syncing

**Symptoms:** Local changes don't appear on server

**Solutions:**
1. Ensure `needSync: true` when creating/updating data
2. Check connection state is `true`
3. Enable verbose logging:
   ```bash
   flutter run -v
   ```
4. Verify server ACK messages are being sent

### Frequent Reconnections

**Symptoms:** Connection constantly dropping and reconnecting

**Solutions:**
1. Increase heartbeat interval if behind proxy:
   ```dart
   heartbeatInterval: Duration(seconds: 20)
   ```
2. Check network stability
3. Verify server timeout settings match heartbeat interval

### High Battery Usage

**Symptoms:** App draining battery quickly

**Solutions:**
1. Increase heartbeat interval to reduce overhead
2. Consider using `PeriodicSyncStrategy` instead for less critical data
3. Pause sync when app is backgrounded:
   ```dart
   wsStrategy.stop(); // When app backgrounds
   wsStrategy.start(); // When app resumes
   ```

### Duplicate Events

**Symptoms:** Same event appears multiple times

**Solutions:**
1. Verify server implements event deduplication by `eventId`
2. Ensure server sends ACK for received events
3. Check LocalFirst marks events as synced after ACK

## Advanced Usage

### Multiple Strategies

Combine WebSocket for real-time data with periodic sync for background data:

```dart
final client = LocalFirstClient(
  repositories: [messageRepo, userRepo, settingsRepo],
  localStorage: HiveLocalFirstStorage(),
  syncStrategies: [
    // Real-time for messages
    WebSocketSyncStrategy(
      websocketUrl: 'ws://api.example.com/sync',
      // ... config
    ),
    // Periodic for settings
    PeriodicSyncStrategy(
      syncInterval: Duration(minutes: 5),
      repositoryNames: ['settings'],
      // ... config
    ),
  ],
);
```

### Custom Error Handling

Listen to connection changes and handle errors:

```dart
wsStrategy.connectionChanges.listen(
  (isConnected) {
    if (!isConnected) {
      // Show retry button, enable offline mode, etc.
      showOfflineBanner();
    } else {
      hideOfflineBanner();
    }
  },
  onError: (error) {
    logger.error('WebSocket error: $error');
    showErrorDialog('Connection error: $error');
  },
);
```

## Contributing

Contributions are welcome! Please open an issue to discuss ideas or bugs, and feel free to submit pull requests. See the main [local_first](https://pub.dev/packages/local_first) repository for guidelines.

## License

This project is available under the MIT License. See `LICENSE` for details.
