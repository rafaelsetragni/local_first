# WebSocket Server

This directory contains the WebSocket server implementation for the local_first_websocket example.

## Running the Server (Recommended - Docker Compose)

The easiest way to run the full stack (MongoDB + WebSocket Server):

### Using Melos

From the monorepo root:

```bash
melos websocket:server
```

### Using the Shell Script Directly

From the monorepo root:

```bash
./local_first_websocket/example/server/run_server.sh
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

From the `local_first_websocket` directory:

```bash
dart run example/server/websocket_server.dart
```

**Note:** This requires MongoDB to be running separately on `localhost:27017`.

## Server Configuration

The server connects to MongoDB at:
- **Host**: `127.0.0.1` (local) or `mongodb` (Docker Compose service)
- **Port**: `27017`
- **Database**: `remote_counter_db`
- **Credentials**: `admin:admin`

WebSocket server listens on:
- **Port**: `8080`
- **URL**: `ws://localhost:8080`

Environment variables (Docker Compose sets these automatically):
- `MONGO_HOST` - MongoDB hostname (default: `127.0.0.1`)
- `MONGO_PORT` - MongoDB port (default: `27017`)

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

- `websocket_server.dart` - Main server implementation with MongoDB integration
- `docker-compose.yml` - Full stack orchestration (MongoDB + WebSocket Server)
- `run_server.sh` - Convenience script to start the stack with docker-compose
