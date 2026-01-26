# local_first_periodic_strategy

A reusable periodic synchronization strategy plugin for the LocalFirst framework. This plugin extracts the technical periodic sync mechanism into a reusable component, separating sync orchestration from business logic.

## Features

- **Periodic Timer**: Automatically syncs at configurable intervals
- **Push-then-Pull Pattern**: Pushes local changes first, then pulls remote changes
- **Connection Health Checks**: Optional ping callback for monitoring connectivity
- **Separation of Concerns**: Technical sync logic separated from business logic
- **Flexible Callbacks**: Implement your own API calls, filtering, and state management

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
  local_first_periodic_strategy:
    path: ../local_first_periodic_strategy
```

## Usage

```dart
import 'package:local_first_periodic_strategy/local_first_periodic_strategy.dart';

final strategy = PeriodicSyncStrategy(
  syncInterval: Duration(seconds: 5),
  repositoryNames: ['user', 'counter_log'],
  onFetchEvents: (repositoryName) async {
    // Fetch events from your API
    final response = await myApi.fetchEvents(repositoryName);
    return response.events;
  },
  onPushEvents: (repositoryName, events) async {
    // Push events to your API
    final success = await myApi.pushEvents(repositoryName, events);
    return success;
  },
  onBuildSyncFilter: (repositoryName) async {
    // Return filter parameters based on last sync state
    final lastSeq = await storage.getLastSequence(repositoryName);
    return lastSeq != null ? {'afterSequence': lastSeq} : null;
  },
  onSaveSyncState: (repositoryName, events) async {
    // Save sync state after applying events
    if (events.isNotEmpty) {
      final maxSeq = events.map((e) => e['sequence']).reduce(max);
      await storage.saveLastSequence(repositoryName, maxSeq);
    }
  },
  onPing: () async {
    // Optional: Check if API is reachable
    return await myApi.ping();
  },
);

final client = LocalFirstClient(
  repositories: [userRepository, counterLogRepository],
  localStorage: SqliteLocalFirstStorage(),
  syncStrategies: [strategy],
);

await client.initialize();
await strategy.start();
```

## Architecture

The plugin follows a clear separation of concerns:

### Technical Implementation (in plugin)
- Periodic timer management
- Sync orchestration (push → pull)
- Connection state reporting
- Event batching coordination

### Business Logic (in your app)
- API endpoint calls
- Authentication
- Repository-specific filtering
- Sync state management (timestamps, sequences)
- Event transformation

## Comparison with WebSocketSyncStrategy

| Feature | PeriodicSyncStrategy | WebSocketSyncStrategy |
|---------|---------------------|----------------------|
| Sync Timing | Periodic intervals | Real-time on event |
| Push Pattern | Batched | Immediate |
| Connection | Stateless HTTP/REST | Stateful WebSocket |
| Best For | REST APIs, polling | Real-time updates |

## Example

See the example applications in the monorepo for complete implementations using MongoDB.
