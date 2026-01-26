# local_first_periodic_strategy

[![pub package](https://img.shields.io/pub/v/local_first_periodic_strategy.svg)](https://pub.dev/packages/local_first_periodic_strategy)

<br>

A reusable periodic synchronization strategy plugin for the [LocalFirst](https://pub.dev/packages/local_first) framework. This plugin extracts the technical periodic sync mechanism into a reusable component, separating sync orchestration from business logic.

> **Note:** This is a companion package to `local_first`. You need to install the core package first.

## Why local_first_periodic_strategy?

- **Separation of concerns**: Technical sync logic separated from business-specific API calls
- **Reusable**: Works with any REST API, backend, or database
- **Callback-based**: Inject your own business logic through simple callbacks
- **Efficient**: Uses server sequences for incremental sync (only fetch new events)
- **Testable**: Easy to mock callbacks and test independently
- **Production-ready**: Includes error handling, connection health checks, and retry logic

## Features

- ✅ **Periodic Timer Management**: Configurable sync intervals
- ✅ **Push-then-Pull Pattern**: Orchestrates bidirectional sync automatically
- ✅ **Connection State Reporting**: Tracks and reports sync status to UI
- ✅ **Event Batching**: Efficiently batches multiple events in a single request
- ✅ **Health Checks**: Optional ping callback for connection monitoring
- ✅ **Error Recovery**: Continues syncing other repositories even if one fails

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  local_first: ^0.6.0
  local_first_periodic_strategy: ^1.0.0
  # Choose your storage adapter
  local_first_hive_storage: ^0.2.0  # or
  local_first_sqlite_storage: ^0.2.0
```

Then install it with:

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:local_first/local_first.dart';
import 'package:local_first_periodic_strategy/local_first_periodic_strategy.dart';

// 1) Implement your API client
class MyApiClient {
  Future<List<JsonMap>> fetchEvents(String repo, {int? afterSeq}) async {
    final response = await http.get(
      Uri.parse('https://api.example.com/events/$repo?seq=$afterSeq'),
    );
    return (jsonDecode(response.body)['events'] as List).cast<JsonMap>();
  }

  Future<bool> pushEvents(String repo, LocalFirstEvents events) async {
    final response = await http.post(
      Uri.parse('https://api.example.com/events/$repo/batch'),
      body: jsonEncode({'events': events.toJson()}),
    );
    return response.statusCode == 200;
  }
}

// 2) Create sync state manager (tracks last sequence)
class SyncStateManager {
  final LocalFirstClient client;

  SyncStateManager(this.client);

  Future<int?> getLastSequence(String repo) async {
    final value = await client.getConfigValue('__last_seq__$repo');
    return value != null ? int.tryParse(value) : null;
  }

  Future<void> saveLastSequence(String repo, int sequence) async {
    await client.setConfigValue('__last_seq__$repo', sequence.toString());
  }

  int? extractMaxSequence(List<JsonMap<dynamic>> events) {
    if (events.isEmpty) return null;
    return events.map((e) => e['serverSequence'] as int?).whereType<int>().reduce((a, b) => a > b ? a : b);
  }
}

// 3) Wire up the periodic sync strategy
final apiClient = MyApiClient();
final syncManager = SyncStateManager(client);

final strategy = PeriodicSyncStrategy(
  syncInterval: Duration(seconds: 5),
  repositoryNames: ['user', 'todo'],

  // Fetch events from your API
  onFetchEvents: (repositoryName) async {
    final lastSeq = await syncManager.getLastSequence(repositoryName);
    return await apiClient.fetchEvents(repositoryName, afterSeq: lastSeq);
  },

  // Push events to your API
  onPushEvents: (repositoryName, events) async {
    return await apiClient.pushEvents(repositoryName, events);
  },

  // Build sync filter (for your own tracking)
  onBuildSyncFilter: (repositoryName) async {
    final lastSeq = await syncManager.getLastSequence(repositoryName);
    return lastSeq != null ? {'seq': lastSeq} : null;
  },

  // Save sync state after successful sync
  onSaveSyncState: (repositoryName, events) async {
    final maxSeq = syncManager.extractMaxSequence(events);
    if (maxSeq != null) {
      await syncManager.saveLastSequence(repositoryName, maxSeq);
    }
  },

  // Optional: health check
  onPing: () async {
    final response = await http.get(Uri.parse('https://api.example.com/health'));
    return response.statusCode == 200;
  },
);

// 4) Initialize client with strategy
final client = LocalFirstClient(
  repositories: [userRepository, todoRepository],
  localStorage: HiveLocalFirstStorage(),
  syncStrategies: [strategy],
);

await client.initialize();
await strategy.start(); // Start syncing!
```

## How It Works

### Sync Flow

Every `syncInterval` seconds, the strategy automatically:

1. **Push Phase**: Gets pending local events and pushes them via `onPushEvents`
2. **Pull Phase**: Fetches remote events via `onFetchEvents` and applies them locally
3. **State Update**: Saves sync state via `onSaveSyncState` for incremental sync

```
┌─────────────────────────────────────────┐
│     PeriodicSyncStrategy (Plugin)       │
│   ┌─────────────────────────────────┐   │
│   │  Timer (every 5 seconds)        │   │
│   └─────────────┬───────────────────┘   │
│                 │                        │
│   ┌─────────────▼───────────────────┐   │
│   │  Push pending events             │   │
│   │  (calls onPushEvents callback)   │   │
│   └─────────────┬───────────────────┘   │
│                 │                        │
│   ┌─────────────▼───────────────────┐   │
│   │  Pull remote events              │   │
│   │  (calls onFetchEvents callback)  │   │
│   └─────────────┬───────────────────┘   │
│                 │                        │
│   ┌─────────────▼───────────────────┐   │
│   │  Save sync state                 │   │
│   │  (calls onSaveSyncState)         │   │
│   └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
           │                  │
           ▼                  ▼
    Your API Client    Your State Manager
```

## Architecture

### Technical Implementation (Plugin)
The plugin provides:
- Periodic timer management
- Sync orchestration (push → pull)
- Connection state reporting
- Event batching coordination
- Error handling and logging

### Business Logic (Your App)
You provide through callbacks:
- API endpoint calls
- Authentication headers
- Repository-specific filtering
- Sync state management
- Event transformation

This separation makes the plugin **reusable across any backend**.

## Comparison with WebSocketSyncStrategy

| Feature | PeriodicSyncStrategy | WebSocketSyncStrategy |
|---------|---------------------|----------------------|
| Sync Timing | Periodic intervals | Real-time on event |
| Push Pattern | Batched | Immediate |
| Connection | Stateless HTTP/REST | Stateful WebSocket |
| Best For | REST APIs, polling | Real-time collaboration |
| Complexity | Simple | Moderate |
| Battery Usage | Low (configurable) | Higher (always on) |

## Configuration Options

### Sync Interval
Adjust the sync frequency based on your needs:

```dart
PeriodicSyncStrategy(
  syncInterval: Duration(seconds: 10), // Every 10 seconds
  // ... other params
)
```

**Recommendations:**
- 📱 Mobile apps: 5-10 seconds (balance between freshness and battery)
- 💻 Desktop apps: 2-5 seconds (users expect faster updates)
- 🌐 Web apps: 3-5 seconds (moderate polling)

### Repository Names
Specify which repositories to sync:

```dart
repositoryNames: ['user', 'todo', 'settings'],
```

The strategy will sync all listed repositories in each cycle.

## Advanced Usage

### Custom Error Handling

The plugin logs errors but continues with other repositories. You can wrap callbacks for custom error handling:

```dart
onFetchEvents: (repositoryName) async {
  try {
    return await apiClient.fetchEvents(repositoryName);
  } catch (e) {
    // Custom error handling
    errorTracker.log('Fetch failed for $repositoryName: $e');
    return []; // Return empty list to continue
  }
},
```

### Conditional Syncing

Skip syncing for certain repositories based on conditions:

```dart
onFetchEvents: (repositoryName) async {
  // Skip syncing if user is in offline mode
  if (offlineMode && repositoryName != 'essential') {
    return [];
  }
  return await apiClient.fetchEvents(repositoryName);
},
```

### Multiple Strategies

Run multiple strategies simultaneously:

```dart
final client = LocalFirstClient(
  repositories: [userRepo, todoRepo, messageRepo],
  localStorage: HiveLocalFirstStorage(),
  syncStrategies: [
    // Critical data: frequent sync
    PeriodicSyncStrategy(
      syncInterval: Duration(seconds: 5),
      repositoryNames: ['user', 'message'],
      // ... callbacks
    ),
    // Non-critical: less frequent
    PeriodicSyncStrategy(
      syncInterval: Duration(minutes: 1),
      repositoryNames: ['settings', 'cache'],
      // ... callbacks
    ),
  ],
);
```

## Examples

Full working examples available in the monorepo:

- **Hive + HTTP**: `local_first_hive_storage/example` - Uses REST API with periodic sync
- **SQLite + HTTP**: Coming soon

## Best Practices

1. **Use Server Sequences**: Track `serverSequence` instead of timestamps for reliable incremental sync
2. **Batch Events**: The plugin already batches - don't send events one by one in your API
3. **Handle Errors Gracefully**: Return empty arrays or false in callbacks to continue syncing
4. **Test Offline**: Verify your app works when `onPushEvents` and `onFetchEvents` fail
5. **Monitor Performance**: Log sync times to identify slow repositories

## Troubleshooting

### Sync Not Working
- Verify the server is responding: check `onPing` callback
- Enable verbose logging to see sync activity
- Check that `onSaveSyncState` is actually saving the sequence

### Duplicate Events
- Ensure your API returns events based on `serverSequence` filtering
- Verify `onSaveSyncState` is called after events are applied

### High Battery Usage
- Increase `syncInterval` to reduce frequency
- Use connection state monitoring to pause syncing when app is backgrounded

## Contributing

Contributions are welcome! Please open an issue to discuss ideas or bugs, and feel free to submit pull requests. See the main [local_first](https://pub.dev/packages/local_first) repository for guidelines.

## License

This project is available under the MIT License. See `LICENSE` for details.
