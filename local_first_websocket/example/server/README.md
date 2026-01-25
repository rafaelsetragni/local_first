# WebSocket Server

This directory contains the WebSocket server implementation for the local_first_websocket example.

## Running the Server

### Option 1: Using Melos (Recommended)

From the monorepo root:

```bash
melos websocket:server
```

This will automatically:
- Start MongoDB if not running
- Build and run the server in Docker
- Mount your local code for easy updates
- Show server logs

### Option 2: Using the Shell Script Directly

From the monorepo root:

```bash
./local_first_websocket/example/server/run_server.sh
```

### Option 3: Direct Dart Execution (No Docker)

From the `local_first_websocket` directory:

```bash
dart run example/server/websocket_server.dart
```

Note: This requires MongoDB to be running separately.

## Server Configuration

The server connects to MongoDB at:
- Host: `127.0.0.1` (or `mongo_local` when running in Docker with `--network host`)
- Port: `27017`
- Database: `remote_counter_db`
- Credentials: `admin:admin`

WebSocket server listens on:
- Port: `8080`
- URL: `ws://localhost:8080` or `ws://0.0.0.0:8080`

## Docker Management

View logs:
```bash
docker logs -f local_first_websocket_server
```

Stop server:
```bash
docker stop local_first_websocket_server
```

Restart server:
```bash
docker restart local_first_websocket_server
```

## Files

- `websocket_server.dart` - Main server implementation
- `Dockerfile` - Docker configuration for containerized deployment
- `run_server.sh` - Shell script to build and run in Docker
- `.dockerignore` - Files to exclude from Docker build context
