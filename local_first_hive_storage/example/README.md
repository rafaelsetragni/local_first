# LocalFirst Hive + HTTP Example

A complete example demonstrating the LocalFirst framework with:
- **Hive** for local storage
- **Dart WebSocket Server** for remote persistence via REST API
- **PeriodicSyncStrategy** plugin for periodic synchronization

This example showcases the **separation of concerns** principle: the plugin handles sync orchestration while the app provides business-specific API calls.

## Features

- ✅ Offline-first counter that works without network
- ✅ Per-user data isolation using namespaces
- ✅ Server sequence-based incremental sync
- ✅ HTTP REST API communication
- ✅ Periodic sync every 5 seconds
- ✅ Connection state monitoring
- ✅ Multi-repository support (users, counter logs, sessions)

## Architecture

```
┌─────────────────────────────────────────┐
│    LocalFirst Hive Example (Client)    │
│  ┌───────────────────────────────────┐  │
│  │  Hive Storage (Local)             │  │
│  │  - user, counter_log, session     │  │
│  └───────────────┬───────────────────┘  │
│                  │                       │
│  ┌───────────────▼───────────────────┐  │
│  │  PeriodicSyncStrategy (Plugin)    │  │
│  │  - Timer: every 5 seconds         │  │
│  │  - Push → Pull orchestration      │  │
│  └───────────────┬───────────────────┘  │
│                  │                       │
│  ┌───────────────▼───────────────────┐  │
│  │  RestApiClient (Business Logic)   │  │
│  │  - GET /api/events/:repo?seq=n    │  │
│  │  - POST /api/events/:repo/batch   │  │
│  └───────────────┬───────────────────┘  │
└──────────────────┼───────────────────────┘
                   │ HTTP REST API
┌──────────────────▼───────────────────────┐
│    Dart WebSocket Server                 │
│  ┌───────────────────────────────────┐   │
│  │  REST API Endpoints               │   │
│  │  - Health check                   │   │
│  │  - Event fetch (seq filtering)    │   │
│  │  - Event push (batch)             │   │
│  └───────────────┬───────────────────┘   │
└──────────────────┼───────────────────────┘
                   │
┌──────────────────▼───────────────────────┐
│             MongoDB                      │
│  - serverSequence (auto-increment)       │
│  - Event storage with deduplication      │
└──────────────────────────────────────────┘
```

## Setup

### Prerequisites

- Flutter SDK (>= 3.10.0)
- Docker (for MongoDB and server)
- Dart SDK (for server)

### 1. Start the WebSocket Server

From the monorepo root, run:

```bash
melos websocket:server
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

### 2. Run the Application

```bash
cd local_first_hive_storage/example
flutter pub get
flutter run
```

## How It Works

### Sync Flow

The application syncs data every 5 seconds following this pattern:

1. **Timer Trigger**: `PeriodicSyncStrategy` timer fires
2. **Push Phase**:
   - Gets pending local events from Hive
   - Sends to server via `POST /api/events/{repo}/batch`
   - Marks events as synced on success
3. **Pull Phase**:
   - Fetches remote events via `GET /api/events/{repo}?seq={lastSeq}`
   - Applies events to local Hive storage
   - Updates `SyncStateManager` with latest sequence
4. **State Update**: Saves last synced sequence for next incremental sync

### Key Components

#### RestApiClient ([rest_api_client.dart](lib/rest_api_client.dart))
HTTP client for communicating with the Dart server:
- `fetchEvents(repo, afterSequence)` - GET events with filtering
- `pushEvents(repo, events)` - POST events in batch
- `ping()` - Health check endpoint

#### SyncStateManager (in [main.dart](lib/main.dart))
Tracks last synced server sequence per repository:
- `getLastSequence(repo)` - Load from config storage
- `saveLastSequence(repo, seq)` - Persist after sync
- `extractMaxSequence(events)` - Find highest sequence

#### RepositoryService ([main.dart](lib/main.dart))
Central orchestrator that wires everything together:
- Creates repositories (user, counter_log, session_counter)
- Initializes `PeriodicSyncStrategy` with callbacks
- Provides business logic through callbacks:
  - `onFetchEvents` → calls `RestApiClient.fetchEvents`
  - `onPushEvents` → calls `RestApiClient.pushEvents`
  - `onBuildSyncFilter` → returns sequence filter
  - `onSaveSyncState` → saves latest sequence
  - `onPing` → checks server health

## REST API Endpoints

The Dart server exposes these endpoints:

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/health` | Health check |
| GET | `/api/events/{repo}?seq={n}` | Fetch events after sequence |
| POST | `/api/events/{repo}/batch` | Push events batch |
| GET | `/api/events/{repo}/{eventId}` | Get specific event |

**Query Parameters:**
- `seq` (optional): Server sequence number to fetch events after
- `limit` (optional): Maximum events to return

**Example Request:**
```bash
curl "http://localhost:8080/api/events/user?seq=42&limit=10"
```

## Comparison with WebSocket Example

| Aspect | This Example (HTTP + Periodic) | WebSocket Example |
|--------|-------------------------------|-------------------|
| **Sync Strategy** | PeriodicSyncStrategy | WebSocketSyncStrategy |
| **Transport** | HTTP REST API | WebSocket |
| **Sync Timing** | Every 5 seconds (batched) | Real-time on event |
| **Connection** | Stateless HTTP requests | Stateful WebSocket |
| **Complexity** | Simple | Moderate |
| **Best For** | REST APIs, polling | Real-time collaboration |
| **Battery Usage** | Low (configurable interval) | Higher (always connected) |
| **State Tracking** | Server sequences | Server sequences |
| **Server** | Dart WebSocket Server | Dart WebSocket Server |

## Benefits of This Architecture

### 🔌 Separation of Concerns
- **Plugin**: Handles "how" to sync (timer, orchestration, batching)
- **Application**: Handles "what" to sync (API calls, filtering, state)

### ♻️ Reusability
The `PeriodicSyncStrategy` plugin can be reused with:
- Any REST API (Node.js, Python, Go, Ruby, etc.)
- Any backend (Firebase, Supabase, AWS, Azure)
- Any database (PostgreSQL, MySQL, SQLite, etc.)
- Cloud services or custom servers

### ✅ Testability
- Mock `RestApiClient` to test without server
- Mock callbacks in `PeriodicSyncStrategy`
- Test offline behavior independently
- Easy to write integration tests

### 🛠️ Maintainability
- Clear interfaces between components
- Changes to API don't affect sync logic
- Changes to sync logic don't affect API
- Easy to swap implementations

## Configuration

### Change Sync Interval

In [main.dart](lib/main.dart), modify the `PeriodicSyncStrategy` configuration:

```dart
syncStrategy = PeriodicSyncStrategy(
  syncInterval: Duration(seconds: 10), // Changed from 5 to 10 seconds
  // ... rest of config
);
```

**Recommendations:**
- 📱 Mobile: 5-10 seconds (battery conscious)
- 💻 Desktop: 2-5 seconds (faster updates)
- 🌐 Web: 3-5 seconds (moderate polling)

### Use Different Backend

Replace `RestApiClient` with your own implementation:

```dart
class MyApiClient {
  Future<List<JsonMap>> fetchEvents(String repo, {int? afterSeq}) async {
    final response = await http.get(
      Uri.parse('https://myapi.com/sync/$repo?after=$afterSeq'),
    );
    return (jsonDecode(response.body)['events'] as List).cast<JsonMap>();
  }

  Future<bool> pushEvents(String repo, LocalFirstEvents events) async {
    final response = await http.post(
      Uri.parse('https://myapi.com/sync/$repo'),
      body: jsonEncode({'events': events.toJson()}),
    );
    return response.statusCode == 200;
  }
}
```

Update callbacks in `RepositoryService`:

```dart
_apiClient = MyApiClient();

syncStrategy = PeriodicSyncStrategy(
  // ... same config
  onFetchEvents: (repo) => _apiClient.fetchEvents(repo, afterSeq: lastSeq),
  onPushEvents: (repo, events) => _apiClient.pushEvents(repo, events),
  // ... rest of callbacks
);
```

### Add Authentication

Add auth headers to API client:

```dart
class RestApiClient {
  final String baseUrl;
  final String? authToken;

  Future<List<JsonMap>> fetchEvents(String repo, {int? afterSeq}) async {
    final response = await http.get(
      uri,
      headers: authToken != null
          ? {'Authorization': 'Bearer $authToken'}
          : null,
    );
    // ... rest of implementation
  }
}
```

## Troubleshooting

### Server Connection Error

**Symptoms:** App shows "disconnected", no syncing happens

**Solutions:**
1. Verify server is running on port 8080
   ```bash
   curl http://localhost:8080/api/health
   ```
2. Check MongoDB is running
   ```bash
   docker ps | grep local_first_mongodb
   ```
3. Check server logs
   ```bash
   melos websocket:server
   ```

### Sync Not Working

**Symptoms:** Data not appearing across devices

**Solutions:**
1. Enable verbose logging:
   ```bash
   flutter run -v
   ```
2. Check console for log messages:
   - `PeriodicSyncStrategy`: Sync orchestration
   - `RestApiClient`: HTTP operations
   - `SyncStateManager`: State tracking
3. Verify sequence is being saved:
   ```dart
   final seq = await syncManager.getLastSequence('user');
   print('Last sequence: $seq');
   ```

### Duplicate Events

**Symptoms:** Same data appearing multiple times

**Solutions:**
1. Verify server returns events based on `seq` filter
2. Check `onSaveSyncState` is called after events applied
3. Ensure `serverSequence` is being properly assigned by server

### High Battery Usage

**Symptoms:** App draining battery quickly

**Solutions:**
1. Increase sync interval:
   ```dart
   syncInterval: Duration(seconds: 30), // Less frequent
   ```
2. Pause syncing when app is backgrounded
3. Reduce number of repositories being synced

### Port Already in Use

**Symptoms:** Server fails to start with "address already in use"

**Solutions:**
```bash
# Find process using port 8080
lsof -i :8080

# Kill the process
kill -9 <PID>

# Or use a different port
dart run websocket_server.dart --port 8081
```

## Running Tests

```bash
# Unit tests
flutter test

# Integration tests
flutter test integration_test/

# Run server tests
cd server && dart test
```

## See Also

- [local_first](https://pub.dev/packages/local_first) - Core framework
- [local_first_periodic_strategy](../../../local_first_periodic_strategy) - Periodic sync plugin
- [local_first_websocket](../../../local_first_websocket) - WebSocket sync plugin
- [Server Implementation](../../../server) - Dart WebSocket server

## Contributing

Contributions are welcome! Please open an issue to discuss ideas or bugs. See the main [local_first](https://pub.dev/packages/local_first) repository for guidelines.

## License

This project is available under the MIT License. See `LICENSE` for details.
