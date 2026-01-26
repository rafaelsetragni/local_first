# Hybrid WebSocket + REST API Server

This directory contains a hybrid server implementation that supports both WebSocket real-time synchronization and REST API endpoints for HTTP clients. Both protocols use server sequence numbers for synchronization.

## Running the Server (Recommended - Docker Compose)

The easiest way to run the full stack (MongoDB + WebSocket Server):

### Using Melos

From the monorepo root:

```bash
melos server:start
```

### Using the Shell Script Directly

From the monorepo root:

```bash
./server/run_server.sh
```

### Using Docker Compose Directly

From this directory:

```bash
docker compose up
```

**What this does:**
- ✅ Automatically starts MongoDB with persistent storage
- ✅ Waits for MongoDB to be healthy before starting the server
- ✅ Mounts your local code for live updates
- ✅ Configures networking between services
- ✅ Shows real-time logs
- ✅ Restarts server automatically if it crashes

## Alternative: Direct Dart Execution (No Docker)

From the `server` directory (at monorepo root):

```bash
dart run websocket_server.dart
```

**Note:** This requires MongoDB to be running separately on `localhost:27017`.

## Server Configuration

The server connects to MongoDB at:
- **Host**: `127.0.0.1` (local) or `mongodb` (Docker Compose service)
- **Port**: `27017`
- **Database**: `remote_counter_db`
- **Credentials**: `admin:admin`

Server listens on:
- **Port**: `8080`
- **WebSocket URL**: `ws://localhost:8080`
- **REST API Base URL**: `http://localhost:8080/api`

Environment variables (Docker Compose sets these automatically):
- `MONGO_HOST` - MongoDB hostname (default: `127.0.0.1`)
- `MONGO_PORT` - MongoDB port (default: `27017`)

## REST API Endpoints

The server provides REST API endpoints for HTTP clients. See [REST_API.md](REST_API.md) for complete documentation.

### Quick Reference

- `GET /api/health` - Health check
- `GET /api/repositories` - List available repositories with statistics
- `GET /api/events/{repository}?afterSequence={n}` - Get events after sequence number
- `GET /api/events/{repository}/{eventId}` - Get specific event by ID
- `POST /api/events/{repository}` - Create single event
- `POST /api/events/{repository}/batch` - Create multiple events

### Quick Test

```bash
# Check server health
curl http://localhost:8080/api/health

# List repositories
curl http://localhost:8080/api/repositories

# Get events from user repository
curl http://localhost:8080/api/events/user

# Get events after sequence 10
curl "http://localhost:8080/api/events/user?afterSequence=10"

# Create an event
curl -X POST http://localhost:8080/api/events/user \
  -H "Content-Type: application/json" \
  -d '{
    "eventId": "evt_test_123",
    "id": "test",
    "username": "Test User"
  }'
```

**Important**: REST API and WebSocket clients use the same server sequence numbers for synchronization, ensuring consistency across all client types.

## Docker Compose Management

All commands should be run from the `server/` directory:

### View Logs

```bash
# WebSocket server logs only
docker compose logs -f websocket_server

# All services (MongoDB + WebSocket)
docker compose logs -f

# Last 100 lines
docker compose logs --tail=100
```

### Control Services

```bash
# Stop services (keeps containers)
docker compose stop

# Start stopped services
docker compose start

# Restart services
docker compose restart

# Stop and remove containers (keeps volumes)
docker compose down

# Stop, remove containers AND volumes (clean slate)
docker compose down -v
```

### Service Status

```bash
# Check running services
docker compose ps

# View resource usage
docker stats local_first_websocket_server local_first_mongodb
```

### Rebuild After Code Changes

Code changes are reflected automatically because the code is mounted as a volume. However, if dependencies change:

```bash
# Restart the WebSocket server to reinstall dependencies
docker compose restart websocket_server
```

## Files

- `websocket_server.dart` - Main server implementation with MongoDB integration (WebSocket + REST API)
- `docker-compose.yml` - Full stack orchestration (MongoDB + WebSocket Server)
- `run_server.sh` - Convenience script to start the stack with docker-compose
- `REST_API.md` - Complete REST API documentation with examples
