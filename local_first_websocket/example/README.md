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

1. **Docker Desktop** - Required for running MongoDB and WebSocket server
2. **Flutter** - To run the mobile/desktop app
3. **Melos** - Optional, for convenience commands (`dart pub global activate melos`)

## Setup Instructions

### Quick Start with Melos (Recommended)

The simplest way to run the full stack (MongoDB + WebSocket Server):

```bash
# From the monorepo root
melos websocket:server
```

This single command will:
- ✅ Start MongoDB with persistent storage
- ✅ Start WebSocket server with automatic dependency installation
- ✅ Configure networking between services
- ✅ Mount your local code for instant updates (no rebuild needed)
- ✅ Show real-time server logs
- ✅ Auto-restart on crashes

To stop all services:
```bash
cd local_first_websocket/example/server
docker compose down
```

To stop and remove all data (clean slate):
```bash
cd local_first_websocket/example/server
docker compose down -v
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

### Alternative: Using Docker Compose Directly

If you prefer not to use melos:

```bash
cd local_first_websocket/example/server
docker compose up
```

This starts both MongoDB and the WebSocket server with live logs.

### Alternative: Direct Dart Execution (Development Only)

For quick iteration without Docker, you can run the server directly:

1. **Start MongoDB** (must be running on localhost:27017):
   ```bash
   docker run -d --name mongo_local -p 27017:27017 \
     -e MONGO_INITDB_ROOT_USERNAME=admin \
     -e MONGO_INITDB_ROOT_PASSWORD=admin mongo:7
   ```

2. **Run the server**:
   ```bash
   cd local_first_websocket
   dart run example/server/websocket_server.dart
   ```

3. You should see:
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

## Docker Compose Management

All commands should be run from `local_first_websocket/example/server/`:

### View Logs

```bash
# WebSocket server logs only
docker compose logs -f websocket_server

# All services (MongoDB + WebSocket)
docker compose logs -f

# Last 100 lines
docker compose logs --tail=100 websocket_server
```

### Control Services

```bash
# Stop services (keeps containers and data)
docker compose stop

# Start stopped services
docker compose start

# Restart services (useful after code changes to dependencies)
docker compose restart websocket_server

# Stop and remove containers (keeps data volumes)
docker compose down

# Stop, remove containers AND delete all data
docker compose down -v
```

### Check Status

```bash
# See running services
docker compose ps

# Monitor resource usage
docker compose stats
```

### Code Changes

Your code is mounted as a volume, so most changes are reflected immediately:
- **Server code changes**: Just save the file and restart: `docker compose restart websocket_server`
- **Dependency changes** (pubspec.yaml): Restart the service: `docker compose restart websocket_server`
- **Major updates**: Full restart: `docker compose down && docker compose up -d`

## Troubleshooting

### Services Won't Start

```bash
# Check service status
cd local_first_websocket/example/server
docker compose ps

# View logs for errors
docker compose logs

# Clean start
docker compose down -v
docker compose up
```

### MongoDB Connection Failed

```bash
# Check MongoDB health
docker compose ps mongodb

# View MongoDB logs
docker compose logs mongodb

# Restart MongoDB
docker compose restart mongodb
```

### WebSocket Server Issues

```bash
# Check if server is running
docker compose ps websocket_server

# View server logs
docker compose logs -f websocket_server

# Restart server
docker compose restart websocket_server

# Check if server can reach MongoDB
docker compose exec websocket_server ping mongodb
```

### Port Already in Use

If ports 8080 or 27017 are already in use:

```bash
# Find what's using the ports
lsof -i :8080
lsof -i :27017

# Stop conflicting services or change ports in docker-compose.yml
```

### Inspect Database Contents

```bash
# Access MongoDB shell
docker compose exec mongodb mongosh -u admin -p admin --authenticationDatabase admin

# Then in mongosh:
use remote_counter_db
db.user.find()
db.counter_log.find()
db.session_counter.find()
exit
```

### Clean Slate (Reset Everything)

```bash
cd local_first_websocket/example/server

# Stop and remove everything including data
docker compose down -v

# Start fresh
docker compose up
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
