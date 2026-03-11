# Periodic Sync Strategy Example

This example demonstrates periodic synchronization using `local_first_periodic_strategy` with a simulated REST API backend.

## Features Demonstrated

- Periodic polling synchronization at configurable intervals
- Offline-first data persistence with Hive storage
- Automatic sync retry on failure
- Connection status indicator
- Simple counter app with sync state visualization
- Mock REST API for demonstration (no external server required)

## What is Periodic Sync?

Unlike real-time strategies (WebSocket), periodic sync polls the server at regular intervals to:
1. **Push** local changes to the server
2. **Pull** remote changes from the server

This approach is ideal for:
- ✅ Simpler backend infrastructure (REST API only)
- ✅ Lower server resource usage
- ✅ Mobile apps with intermittent connectivity
- ✅ When real-time updates aren't critical

Trade-offs:
- ⏰ Updates have latency (sync interval)
- 📊 More mobile data usage if interval is too short
- 🔋 Battery impact from periodic polling

## Setup Instructions

### Running the Example

1. **Get dependencies**:
   ```bash
   flutter pub get
   ```

2. **Run the app**:
   ```bash
   flutter run
   ```

The app uses a mock API that simulates server responses, so no external server setup is required!

## How It Works

### Architecture

```
┌─────────────┐         Periodic Sync          ┌─────────────┐
│             │ ←────────────────────────────→ │             │
│  Local DB   │  (Every N seconds)              │  REST API   │
│   (Hive)    │  1. Push pending events         │   (Mock)    │
│             │  2. Pull remote events          │             │
└─────────────┘                                 └─────────────┘
```

### Sync Flow

1. **On Start**: Performs initial sync immediately
2. **Periodic**: Syncs every 5 seconds (configurable)
3. **Push Phase**: Sends all pending local changes to API
4. **Pull Phase**: Fetches new remote changes from API
5. **State Tracking**: Saves last sync timestamp to avoid duplicate fetches

### Code Structure

- `lib/main.dart` - Main app with UI
- `lib/mock_api.dart` - Simulated REST API backend
- `lib/sync_state_provider.dart` - Sync state management

### Key Configuration

```dart
final strategy = PeriodicSyncStrategy(
  syncInterval: const Duration(seconds: 5), // How often to sync
  repositoryNames: ['counter'],             // Which repos to sync
  onFetchEvents: mockApi.fetchEvents,       // Pull from server
  onPushEvents: mockApi.pushEvents,         // Push to server
  onBuildSyncFilter: (repo) async {         // What to fetch
    final lastSync = await getLastSyncTime(repo);
    return {'afterTimestamp': lastSync};
  },
  onSaveSyncState: (repo, events) async {  // Track sync progress
    if (events.isNotEmpty) {
      await saveLastSyncTime(repo, DateTime.now());
    }
  },
);
```

## Customization

### Change Sync Interval

Edit the `syncInterval` parameter in `main.dart`:

```dart
syncInterval: const Duration(seconds: 10), // Sync every 10 seconds
```

Recommended intervals:
- **High frequency**: 5-15 seconds (more battery/data usage)
- **Medium frequency**: 30-60 seconds (balanced)
- **Low frequency**: 2-5 minutes (battery efficient)

### Add More Repositories

Add repository names to sync multiple data types:

```dart
repositoryNames: ['counter', 'users', 'messages'],
```

## Comparing with WebSocket Strategy

| Feature | Periodic Sync | WebSocket |
|---------|--------------|-----------|
| Real-time updates | ❌ Delayed by interval | ✅ Instant |
| Backend complexity | ✅ Simple REST API | ⚠️ WebSocket server required |
| Mobile data usage | ⚠️ Periodic polling | ✅ Event-driven |
| Offline support | ✅ Full support | ✅ Full support |
| Battery impact | ⚠️ Periodic wake-ups | ✅ Efficient |
| Best for | Mobile apps, simpler backends | Collaborative apps, chat |

## Learn More

- [LocalFirst Framework Documentation](../../README.md)
- [Sync Strategy Guide](../../docs/sync-strategies.md)
- [WebSocket Example](../../local_first_websocket/example/README.md)
