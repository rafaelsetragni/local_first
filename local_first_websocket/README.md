# local_first_websocket

Real-time bidirectional synchronization strategy for [`local_first`](https://pub.dev/packages/local_first) using WebSockets.

## Features

- **Real-time synchronization**: Changes are propagated instantly via WebSocket connection
- **Bidirectional sync**: Both push (local → remote) and pull (remote → local) operations
- **Automatic reconnection**: Handles connection loss with configurable retry delay
- **Event queue**: Queues pending events during disconnection for later sync
- **Heartbeat monitoring**: Keeps connection alive with periodic ping/pong messages
- **Connection state tracking**: Reports connection status to the UI

## Getting Started

### Installation

Add this package to your `pubspec.yaml`:

```yaml
dependencies:
  local_first: ^0.6.0
  local_first_websocket: ^0.1.0
```

### Basic Usage

```dart
import 'package:local_first/local_first.dart';
import 'package:local_first_websocket/local_first_websocket.dart';

// Create WebSocket sync strategy
final wsStrategy = WebSocketSyncStrategy(
  websocketUrl: 'ws://your-server.com/sync',
  reconnectDelay: Duration(seconds: 3),
  heartbeatInterval: Duration(seconds: 30),
  authToken: 'your-auth-token', // Optional
);

// Create LocalFirstClient with WebSocket strategy
final client = LocalFirstClient(
  repositories: [userRepository, todoRepository],
  localStorage: InMemoryLocalFirstStorage(),
  syncStrategies: [wsStrategy],
);

// Initialize and start synchronization
await client.initialize();
await wsStrategy.start();

// Listen to connection state changes
wsStrategy.connectionChanges.listen((isConnected) {
  print('WebSocket ${isConnected ? "connected" : "disconnected"}');
});
```

### Updating Authentication Credentials

You can update the authentication token and headers dynamically after initialization:

```dart
// Update only the auth token
wsStrategy.updateAuthToken('new-token-here');

// Update only the headers
wsStrategy.updateHeaders({
  'Authorization': 'Bearer new-token',
  'X-Custom-Header': 'value',
});

// Update both at once
wsStrategy.updateCredentials(
  authToken: 'new-token',
  headers: {'X-Custom-Header': 'value'},
);
```

**Note**: If the WebSocket is currently connected, updating credentials will automatically re-authenticate with the server using the new credentials.

#### Example: Refreshing JWT Token

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
    return 'new-jwt-token';
  }
}
```

## WebSocket Server Protocol

The server must implement the following message types:

### Client → Server Messages

**Authentication:**
```json
{
  "type": "auth",
  "token": "your-auth-token"
}
```

**Heartbeat:**
```json
{
  "type": "ping"
}
```

**Push single event:**
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

**Push multiple events:**
```json
{
  "type": "push_events_batch",
  "repository": "users",
  "events": [ ... ]
}
```

**Request events since timestamp:**
```json
{
  "type": "request_events",
  "repository": "users",
  "since": "2025-01-23T10:00:00.000Z"
}
```

**Request all events:**
```json
{
  "type": "request_all_events"
}
```

**Confirm events received:**
```json
{
  "type": "events_received",
  "repository": "users",
  "count": 5
}
```

### Server → Client Messages

**Authentication success:**
```json
{
  "type": "auth_success"
}
```

**Heartbeat response:**
```json
{
  "type": "pong"
}
```

**Send events to client:**
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

**Acknowledge received events:**
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

**Sync complete:**
```json
{
  "type": "sync_complete",
  "repository": "users"
}
```

**Error:**
```json
{
  "type": "error",
  "message": "Error description"
}
```

## Running the Example

The example includes a complete WebSocket server implementation using MongoDB.

### 1. Start MongoDB

First, start a MongoDB instance using Docker:

```bash
docker run -d --name mongo_local -p 27017:27017 \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=admin mongo:7
```

### 2. Start the WebSocket Server

In the `example` directory, run:

```bash
dart run server/websocket_server.dart
```

The server will start on `ws://localhost:8080/sync`

### 3. Run the Flutter App

```bash
cd example
flutter run
```

## Advanced Configuration

### Custom Headers

```dart
final wsStrategy = WebSocketSyncStrategy(
  websocketUrl: 'ws://your-server.com/sync',
  headers: {
    'Authorization': 'Bearer your-token',
    'X-Custom-Header': 'value',
  },
);
```

### Reconnection Delay

```dart
final wsStrategy = WebSocketSyncStrategy(
  websocketUrl: 'ws://your-server.com/sync',
  reconnectDelay: Duration(seconds: 5), // Wait 5s before reconnecting
);
```

### Heartbeat Interval

```dart
final wsStrategy = WebSocketSyncStrategy(
  websocketUrl: 'ws://your-server.com/sync',
  heartbeatInterval: Duration(seconds: 60), // Ping every 60s
);
```

## How It Works

### Push Flow

1. User creates/updates/deletes data locally
2. `LocalFirstClient` creates an event with `SyncStatus.pending`
3. `WebSocketSyncStrategy.onPushToRemote()` is called
4. If connected: sends event via WebSocket immediately
5. If disconnected: adds event to pending queue
6. Server acknowledges with ACK message
7. Strategy marks event as `SyncStatus.ok`

### Pull Flow

1. Server sends `events` message with new/updated data
2. Strategy calls `pullChangesToLocal()` to apply changes
3. `LocalFirstClient` merges remote changes, handling conflicts
4. Strategy sends confirmation to server
5. UI automatically updates via repository streams

### Reconnection Flow

1. Connection lost (network issue, server restart, etc.)
2. Strategy reports `connectionState: false`
3. Pending events are queued locally
4. After `reconnectDelay`, attempts to reconnect
5. On reconnect, requests missed events via `request_events`
6. Flushes pending queue to server
7. Reports `connectionState: true`

## Comparison with Other Strategies

| Strategy | Push Timing | Pull Timing | Use Case |
|----------|------------|-------------|----------|
| `WebSocketSyncStrategy` | Immediate | Real-time | Low-latency apps, collaborative editing |
| `PeriodicSyncStrategy` | Every N seconds | Every N seconds | Background sync, batch updates |
| `ManualSyncStrategy` | On demand | On demand | User-controlled sync |
| `ConnectivitySyncStrategy` | On reconnect | On reconnect | Offline-first with sync on connectivity |

## Contributing

Contributions are welcome! Please read the [contributing guidelines](../CONTRIBUTING.md) first.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
