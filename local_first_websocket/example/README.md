# WebSocket Real-Time Counter Example

This example demonstrates real-time synchronization using `local_first_websocket` with a WebSocket server backed by MongoDB.

## Features Demonstrated

- Real-time bidirectional synchronization via WebSocket
- Multiple users collaborating on a shared counter
- Automatic reconnection when connection is lost
- Event queue for offline changes
- User profiles with avatar updates
- Activity log showing recent changes
- Connection status indicator

## Prerequisites

1. **Docker Desktop** - To run MongoDB and optionally the WebSocket server
2. **Dart SDK** - To run the WebSocket server locally (optional if using Docker)
3. **Flutter** - To run the mobile/desktop app
4. **Melos** - To use the melos commands (optional, install with `dart pub global activate melos`)

## Setup Instructions

### Quick Start with Melos (Easiest)

The simplest way to run the WebSocket server in Docker:

```bash
# From the monorepo root
melos websocket:server
```

This command will:
- Start MongoDB automatically if not running
- Build and run the WebSocket server in a Docker container
- Mount your local code for easy updates
- Show server logs in real-time

To stop the server:
```bash
docker stop local_first_websocket_server
```

### Quick Start with VS Code (Recommended for Development)

The monorepo includes VS Code launch configurations for easy development.

1. **Install VS Code Extensions** (recommended when you open the project):
   - Dart
   - Flutter

2. **Start MongoDB**:
   ```bash
   docker run -d --name mongo_local -p 27017:27017 \
     -e MONGO_INITDB_ROOT_USERNAME=admin \
     -e MONGO_INITDB_ROOT_PASSWORD=admin mongo:7
   ```

3. **Run the Full Stack**:
   - Go to Run and Debug (`Cmd+Shift+D` / `Ctrl+Shift+D`)
   - Select `local_first_websocket: Full Stack`
   - Press F5 to start both server and client together

   Or run individually:
   - `local_first_websocket: Server` - Runs only the WebSocket server
   - `local_first_websocket: Example App` - Runs only the Flutter app (IDE will prompt for device selection)

### Manual Setup (Alternative)

#### 1. Start MongoDB

Run MongoDB in a Docker container:

```bash
docker run -d --name mongo_local -p 27017:27017 \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=admin mongo:7
```

Verify MongoDB is running:

```bash
docker stats mongo_local
```

#### 2. Start the WebSocket Server

**Option A: Using Docker (Recommended for Production-like Environment)**

From the monorepo root:

```bash
./local_first_websocket/example/server/run_server.sh
```

Or using melos:

```bash
melos websocket:server
```

The server will run in a Docker container with your code mounted as a volume.

**Option B: Direct Dart Execution (Faster for Quick Testing)**

From the `local_first_websocket` directory:

```bash
dart run example/server/websocket_server.dart
```

You should see:

```
WebSocket server listening on ws://0.0.0.0:8080
Connected to MongoDB at mongodb://admin:admin@127.0.0.1:27017/remote_counter_db?authSource=admin
```

#### 3. Run the Flutter App

From the `example` directory:

```bash
flutter run
```

Or run multiple instances to test real-time sync between users:

```bash
# Terminal 1
flutter run -d chrome

# Terminal 2
flutter run -d macos

# Terminal 3
flutter run -d linux
```

## How to Test

### Single User

1. Sign in with a username (e.g., "Alice")
2. Tap the + button to increment the counter
3. Tap the - button to decrement the counter
4. Update your avatar by tapping on it
5. Watch the activity log update in real-time

### Multiple Users

1. Run multiple instances of the app
2. Sign in with different usernames in each instance
3. Increment/decrement the counter in any instance
4. Watch all instances update in real-time
5. See all users appear in the "Users" section
6. Test offline mode by stopping the server:
   - The app shows "Disconnected"
   - Make changes locally
   - Restart the server
   - Watch changes sync automatically

## Synchronization Strategy

This example uses **server sequence numbers** instead of timestamps for synchronization. This solves the "time drift" problem where devices with unsynchronized clocks might miss events.

### Why Server Sequence?

- **No time drift issues**: Devices don't need synchronized clocks
- **Guaranteed ordering**: Server assigns monotonically increasing sequence numbers
- **Efficient querying**: Simple integer comparison (> lastSequence)
- **Idempotent**: Same event can be pushed multiple times safely

### How It Works

1. **Server assigns sequences**: Each event gets a unique sequence number per repository
2. **Client tracks last sequence**: `SyncStateManager` stores the highest sequence seen
3. **Incremental sync**: On reconnection, client requests `afterSequence: N`
4. **Application control**: Callbacks allow custom sync strategies

### Sync Callbacks

The `WebSocketSyncStrategy` uses two required callbacks:

```dart
// Build filter for requesting events from server
onBuildSyncFilter: (repositoryName) async {
  final lastSeq = await getLastSequence(repositoryName);
  return lastSeq != null ? {'afterSequence': lastSeq} : null;
}

// Update sync state after receiving events
onSyncCompleted: (repositoryName, events) async {
  final maxSeq = extractMaxSequence(events);
  if (maxSeq != null) {
    await saveLastSequence(repositoryName, maxSeq);
  }
}
```

**Benefits**:
- Infrastructure layer (WebSocket) doesn't make business decisions
- Application can use timestamps, sequences, version vectors, or custom strategies
- Easy to test and reason about

## WebSocket Server Implementation

The server ([websocket_server.dart](server/websocket_server.dart)) demonstrates:

- WebSocket connection handling with multiple clients
- MongoDB integration for persistence
- Server sequence assignment per repository
- Broadcasting events to all connected clients
- Acknowledgment protocol for reliable delivery
- Heartbeat/ping-pong for connection health
- Sequence-based synchronization

### Server Message Flow

```
Client A                Server              Client B              MongoDB
   |                      |                    |                     |
   |---[auth]------------>|                    |                     |
   |<--[auth_success]-----|                    |                     |
   |                      |<---[auth]----------|                     |
   |                      |---[auth_success]-->|                     |
   |                      |                    |                     |
   |--[request_events]--->|                    |                     |
   | afterSequence: 42    |---[query]------------------------------>|
   |                      |<--[events with seq 43-50]---------------|
   |<--[events]-----------|                    |                     |
   | serverSequence: 43-50|                    |                     |
   |                      |                    |                     |
   |---[push_event]------>|                    |                     |
   |                      |--[assign seq 51]------------------------->|
   |<--[ack]--------------|                    |                     |
   |                      |---[broadcast]----->|                     |
   |                      |  serverSequence: 51|                     |
   |                      |                    |                     |
```

**Key Points**:
- Server assigns `serverSequence` for each new event
- Clients request events using `afterSequence`
- No timestamp comparison or clock synchronization needed
- Sequences are per-repository, starting from 1

## Architecture

### Client-Side

```
UI Layer
   ↓
RepositoryService (manages auth, session, operations)
   ↓
LocalFirstClient (event sourcing, conflict resolution)
   ↓
WebSocketSyncStrategy (real-time sync, callbacks)
   ↓↑
SyncStateManager (tracks last sequence per repository)
   ↓
WebSocket Connection
```

**Separation of Concerns**:
- `WebSocketSyncStrategy`: Infrastructure layer (WebSocket communication)
- `SyncStateManager`: Business logic (sync strategy using sequences)
- `RepositoryService`: Application layer (domain operations)

### Server-Side

```
WebSocket Server (connection handling)
   ↓
Message Router (auth, push, pull, heartbeat)
   ↓
Sequence Assignment (atomic increment per repository)
   ↓
MongoDB Collections (user, counter_log, session_counter)
   ↓
Sequence Counters (_sequence_counters)
```

## Data Model

All events stored in MongoDB include a `serverSequence` field assigned by the server. This enables efficient, clock-independent synchronization.

### User

```dart
{
  "eventId": "evt_alice_1737629400000",
  "serverSequence": 15,  // Assigned by server
  "id": "alice",
  "username": "Alice",
  "avatarUrl": "https://...",
  "createdAt": "2025-01-23T10:00:00Z",
  "updatedAt": "2025-01-23T10:05:00Z"
}
```

### Counter Log

```dart
{
  "eventId": "evt_alice_1737629400123",
  "serverSequence": 89,  // Assigned by server
  "id": "alice_1737629400000",
  "username": "Alice",
  "sessionId": "sess_alice_...",
  "increment": 1,
  "createdAt": "2025-01-23T10:10:00Z",
  "updatedAt": "2025-01-23T10:10:00Z"
}
```

### Session Counter

```dart
{
  "eventId": "evt_sess_alice_1737629400456",
  "serverSequence": 42,  // Assigned by server
  "id": "sess_alice_...",
  "username": "Alice",
  "sessionId": "sess_alice_...",
  "count": 42,
  "createdAt": "2025-01-23T10:00:00Z",
  "updatedAt": "2025-01-23T10:10:00Z"
}
```

### Sequence Counter (Internal)

The server maintains a sequence counter per repository:

```dart
{
  "_id": "user",          // Repository name
  "sequence": 15          // Last assigned sequence
}
```

## Docker Server Management

When running the WebSocket server in Docker, use these commands:

### View Server Logs

```bash
docker logs -f local_first_websocket_server
```

### Stop the Server

```bash
docker stop local_first_websocket_server
```

### Restart the Server

```bash
docker restart local_first_websocket_server
```

### Remove the Server Container

```bash
docker stop local_first_websocket_server
docker rm local_first_websocket_server
```

### Rebuild After Code Changes

The Docker container mounts your local code as a volume. However, dependency changes or major updates may require rebuilding:

```bash
# Stop and remove the old container
docker stop local_first_websocket_server
docker rm local_first_websocket_server

# Run the server again (will rebuild automatically)
melos websocket:server
```

### Check Running Containers

```bash
docker ps
```

## Troubleshooting

### MongoDB Connection Failed

- Check if Docker container is running: `docker ps`
- Check MongoDB logs: `docker logs mongo_local`
- Restart container: `docker restart mongo_local`

### WebSocket Connection Failed

**If running server in Docker:**
- Check if container is running: `docker ps | grep local_first_websocket_server`
- Check server logs: `docker logs local_first_websocket_server`
- Verify MongoDB is accessible from container: `docker exec -it local_first_websocket_server ping mongo_local`

**If running server directly:**
- Check if server is running on port 8080
- Check firewall settings
- Try localhost instead of 0.0.0.0: Update `websocketUrl` to `ws://localhost:8080/sync`

### Changes Not Syncing

- Check server logs for errors
- Verify both client and server are connected
- Check MongoDB for stored events:
  ```bash
  docker exec -it mongo_local mongosh -u admin -p admin --authenticationDatabase admin
  use remote_counter_db
  db.user.find()
  db.counter_log.find()
  ```

## Next Steps

- Implement authentication with JWT tokens
- Add SSL/TLS for secure WebSocket (wss://)
- Deploy server to production (e.g., Heroku, Railway, Fly.io)
- Add more collaborative features (chat, drawing, etc.)
- Implement custom conflict resolution strategies

## Learn More

- [local_first documentation](https://pub.dev/packages/local_first)
- [WebSocket protocol](https://datatracker.ietf.org/doc/html/rfc6455)
- [MongoDB documentation](https://docs.mongodb.com/)
