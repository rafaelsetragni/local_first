# Local First - Comprehensive Example App

A production-ready example demonstrating all Local First features with proper code organization.

## Features

This example showcases:

### Dual Sync Strategy Architecture
- **WebSocket Strategy**: Real-time push notifications
  - Receives live updates from server
  - Pending queue disabled (offline events handled by periodic strategy)
  - Bidirectional ping/pong for fast disconnect detection

- **Periodic Strategy**: Consistency and offline sync
  - Server sequence-based synchronization (~10s interval)
  - Handles offline events and missed updates
  - Saves sync state with server sequences

### Multi-User Support
- Per-user database namespaces using SQLite
- Session management with persistent state
- User authentication with server-first approach

### Real-Time Counter Demo
- Collaborative counter updated by all connected users
- Per-session counter tracking
- Activity log with animated list
- User avatars with real-time updates

### Storage
- **Local Data**: SQLite with namespace isolation
- **Configuration**: SharedPreferences for key-value storage
- **Sync State**: Server sequence tracking per repository

## Project Structure

```
lib/
├── config/
│   └── app_config.dart              # Server URLs and constants
├── models/
│   ├── counter_log_model.dart       # Counter activity log
│   ├── field_names.dart             # Field name constants
│   ├── session_counter_model.dart   # Per-session counters
│   └── user_model.dart              # User profile
├── pages/
│   ├── home_page.dart               # Main counter screen
│   └── sign_in_page.dart            # Authentication
├── repositories/
│   └── repositories.dart            # Repository builders
├── services/
│   ├── navigator_service.dart       # Navigation helper
│   ├── repository_service.dart      # Main data service
│   └── sync_state_manager.dart      # Sync state management
└── widgets/
    ├── avatar_preview.dart          # User avatar display
    └── counter_log_tile.dart        # Activity log entry
```

## Running the Example

### 1. Start the Server

From the monorepo root:

```bash
melos server:start
```

The server will start on port 8080 with MongoDB backend.

### 2. Start MongoDB (if not using Docker Compose)

```bash
docker run -d --name local_first_mongodb -p 27017:27017 \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=admin mongo:7
```

### 3. Run the App

```bash
cd example_app
flutter run
```

## Architecture Highlights

### Dual-Strategy Sync

The app uses both WebSocket and Periodic sync strategies together:

```dart
// WebSocket: Real-time push only
webSocketStrategy = WebSocketSyncStrategy(
  websocketUrl: websocketUrl,
  enablePendingQueue: false,  // Let periodic handle offline
  onBuildSyncFilter: (_) async => null,  // Don't pull
);

// Periodic: Consistency & offline handling
periodicStrategy = PeriodicSyncStrategy(
  syncInterval: Duration(seconds: 10),
  onFetchEvents: _fetchEvents,  // REST API polling
  onPushEvents: _pushEvents,    // REST API push
);
```

### Server-First Authentication

```dart
// 1. Create local user model
final localUser = UserModel(username: username);

// 2. Check if user exists on server
final remoteUser = await _fetchRemoteUser(localUser.id);

// 3. Use remote data if exists, otherwise sync local
authenticatedUser = remoteUser ?? localUser;
```

### Namespace Isolation

Each user gets their own SQLite namespace:

```dart
// Switch to user's namespace
await _switchUserDatabase(userId);

// All queries now isolated to this user's data
final results = await userRepository.query().getAll();
```

## Key Concepts Demonstrated

1. **Conflict Resolution**: Last-write-wins with timestamp comparison
2. **Event Synchronization**: Server sequence numbers for consistency
3. **Offline Support**: Pending queue + periodic sync fallback
4. **Real-Time Updates**: WebSocket push for instant notifications
5. **Session Management**: Persistent user sessions across app restarts
6. **Namespace Isolation**: Multi-user support with separate databases

## Related Examples

- **`local_first/example`**: Simple InMemory storage example
- **`local_first_websocket/example`**: WebSocket-only strategy (original monolithic version)
- **`local_first_periodic_strategy/example`**: Periodic-only strategy

This comprehensive example combines all strategies and demonstrates production-ready patterns.
