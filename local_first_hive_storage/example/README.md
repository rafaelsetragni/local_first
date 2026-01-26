# LocalFirst Hive + HTTP Example

This example demonstrates using the LocalFirst framework with:
- **Hive** for local storage
- **Dart WebSocket Server** for remote persistence (via REST API)
- **PeriodicSyncStrategy** plugin for periodic synchronization

## Architecture

This example showcases the **separation of concerns** principle:

### Technical Implementation (Plugin)
The `local_first_periodic_strategy` plugin provides:
- Periodic timer management
- Sync orchestration (push → pull pattern)
- Connection state reporting
- Event batching

### Business Logic (Application)
The application provides:
- REST API client ([rest_api_client.dart](lib/rest_api_client.dart))
- Sync state manager (inside [main.dart](lib/main.dart))
- Repository-specific logic
- Event transformation

## Setup

### 1. Start the WebSocket Server

From the monorepo root, run:

```bash
melos websocket:server
```

This command automatically:
- Starts MongoDB with Docker Compose
- Starts the Dart WebSocket server on port 8080
- Configures networking between services
- Shows real-time logs

**Or manually:**

```bash
# Start MongoDB
docker run -d --name local_first_mongodb -p 27017:27017 \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=admin mongo:7

# Start the server
cd server && dart run websocket_server.dart
```

### 2. Run the Application

```bash
flutter run
```

## How It Works

### Sync Flow

1. **Periodic Timer**: Every 5 seconds, the PeriodicSyncStrategy triggers a sync cycle
2. **Push Phase**: Local pending events are pushed to server via REST API
3. **Pull Phase**: Remote events are fetched from server and applied locally
4. **State Tracking**: `SyncStateManager` tracks last server sequence for incremental sync

### Key Components

#### RestApiClient ([rest_api_client.dart](lib/rest_api_client.dart))
- HTTP client for communicating with the Dart server
- Implements `fetchEvents(repositoryName, afterSequence)` for pulling events
- Implements `pushEvents(repositoryName, events)` for pushing events
- Health check via `/api/health` endpoint

#### SyncStateManager (in [main.dart](lib/main.dart))
- Tracks last synced server sequence per repository
- Enables incremental sync (only fetch new events)
- Stores state in LocalFirst config storage

#### RepositoryService ([main.dart](lib/main.dart))
- Wires together all components
- Provides callbacks to PeriodicSyncStrategy:
  - `onFetchEvents`: Fetches from server via RestApiClient
  - `onPushEvents`: Pushes to server via RestApiClient
  - `onBuildSyncFilter`: Returns sequence filters
  - `onSaveSyncState`: Saves latest sequence
  - `onPing`: Checks server health

## REST API Endpoints

The server exposes these endpoints:

- `GET /api/events/{repository}?seq={n}` - Fetch events after sequence
- `POST /api/events/{repository}/batch` - Push events batch
- `GET /api/health` - Health check

## Comparison with WebSocket Example

| Aspect | This Example (HTTP + Periodic) | WebSocket Example |
|--------|-------------------------------|-------------------|
| Sync Strategy | PeriodicSyncStrategy | WebSocketSyncStrategy |
| Transport | HTTP REST API | WebSocket |
| Sync Timing | Every 5 seconds (batch) | Real-time on event |
| Connection | Stateless HTTP requests | Stateful WebSocket |
| Best For | Simple setups, REST APIs | Real-time collaboration |
| State Tracking | Server sequences | Server sequences |
| Server | Dart WebSocket Server | Dart WebSocket Server |

## Benefits of This Architecture

### Reusability
The `PeriodicSyncStrategy` plugin can be used with:
- Any REST API
- Any backend (Node.js, Python, Go, etc.)
- Any database (PostgreSQL, MySQL, etc.)
- Cloud services (Firebase, Supabase, custom)

### Testability
Business logic is decoupled from sync orchestration:
- Test `RestApiClient` independently
- Mock callbacks in unit tests
- Easy to swap implementations

### Maintainability
Clear separation of concerns:
- Plugin handles "how" to sync
- Application handles "what" to sync
- Changes to business logic don't affect sync orchestration

## Customization

### Change Sync Interval

In [main.dart](lib/main.dart), modify the PeriodicSyncStrategy configuration:

```dart
syncStrategy = PeriodicSyncStrategy(
  syncInterval: Duration(seconds: 10), // Changed from 5 to 10 seconds
  // ... rest of config
);
```

### Use Different Backend

Replace `RestApiClient` with your own API client:

```dart
class MyRestApi {
  Future<List<JsonMap>> fetchEvents(String repo, {int? afterSequence}) async {
    final response = await http.get(/* your API */);
    return /* parse response */;
  }

  Future<bool> pushEvents(String repo, LocalFirstEvents events) async {
    final response = await http.post(/* your API */);
    return response.statusCode == 200;
  }
}
```

Then update the callbacks in `RepositoryService`:

```dart
onFetchEvents: _myApi.fetchEvents,
onPushEvents: _myApi.pushEvents,
```

## Troubleshooting

### Server Connection Error

If you see connection errors, ensure:
1. The WebSocket server is running on port 8080
2. MongoDB container is started
3. Port 8080 is not in use by another service

Check server logs:
```bash
# If using melos
melos websocket:server

# Check if server is responding
curl http://localhost:8080/api/health
```

### Sync Not Working

Check the console for log messages from:
- `PeriodicSyncStrategy`: Sync orchestration
- `RestApiClient`: HTTP operations
- `SyncStateManager`: State tracking

Enable verbose logging:
```bash
flutter run -v
```

### Port Already in Use

If port 8080 is in use:
```bash
# Find process using port 8080
lsof -i :8080

# Kill the process
kill -9 <PID>
```
