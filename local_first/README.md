# Local First

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](#)
[![Discord](https://img.shields.io/discord/888523488376279050.svg?style=for-the-badge&colorA=7289da&label=Chat%20on%20Discord)](https://discord.awesome-notifications.carda.me)

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=103)](#)
[![pub package](https://img.shields.io/pub/v/local_first.svg)](https://pub.dev/packages/local_first)
![Full tests workflow](https://github.com/rafaelsetragni/local_first/actions/workflows/dart.yml/badge.svg?branch=main)
[![codecov](https://codecov.io/github/rafaelsetragni/local_first/graph/badge.svg?token=7BRG8JcWTQ)](https://codecov.io/github/rafaelsetragni/local_first)

<br>

Local-first data layer for Flutter apps that keeps your data available offline and synchronizes when the network returns. The goal is to provide a lightweight, pluggable engine that works with common local stores (Hive, SQLite, etc.) and can sync to any backend through custom strategies.

Data tables are hydrated from the event stream, and the plugins remain compatible with pre-existing data tables—you don’t need to drop or recreate existing records to adopt local_first.

> Status: early preview. The package is in active development (final stages) and the public API may change before the first stable release. Use the examples below as guidance for the intended design.

![Demo](https://live-update-demo.rafaelsetra.workers.dev/)

## Why local_first?

- Local-first by design: build apps that keep ownership/control of data without relying on third-party services.
- Fast, responsive apps that read/write locally first and sync in the background.
- Works without a network connection; queues changes and resolves conflicts when back online.
- Storage-agnostic: start with our Hive, SQLite, config-only SharedPreferences adapter, or your preferred custom database implementation. Data tables hydrate from events and stay compatible with existing tables—no rebuilds required.
- Backend-agnostic: create your sync strategies, so you can integrate with your existent REST, gRPC, WebSockets, etc.
- Minimal boilerplate: declare the storage, register your models with repositories, and start syncing.

## Local-first principle

Local-first apps give users instant feedback by reading and writing to the device first, even with no network. The sync layer runs in the background: when connectivity returns, queued changes are pushed and remote updates are pulled. Your UI never blocks on the server; the storage delegate is the primary interface your repositories talk to.

## Source of truth

During a session, the local database is the working source of truth. Remote systems are reconciled via pull/push cycles driven by your sync strategy. Namespacing (e.g., per user) lets you isolate data domains so a sign-in swap is just a `useNamespace` call on storage and config.

The event table is the single source of truth. Every change is captured as an event (`event_id` + `created_at`, both UUID v7-based) and pushed to the backend; child apps pull those events to converge on eventual consistency. Multiple sync strategies can run concurrently, and idempotency is guaranteed by event identifiers so duplicates are ignored rather than reprocessed. Storage plugins hydrate the data tables from events, but they remain compatible with pre-existing data tables: the event stream drives state forward without requiring you to drop or recreate existing records.

## Conflict resolution

Plan your data model to avoid hotspots: prefer append-only logs, split records so multiple writers don’t touch the same row, and keep timestamps in UTC. If concurrent edits still happen, plug in resolution rules per repository—last-write-wins, timestamp comparison, or custom merge callbacks—to decide which state should prevail when syncing.

### Conflict resolution modes

- **Last-write-wins (LWW):** pick the event with the latest `updated_at` (or another monotonic field).
- **Timestamp comparison:** prefer remote/local based on creation/update timestamps.
- **Custom resolver:** implement domain-specific merge logic (e.g., merge maps, sum counters, reconcile lists).

Example: registering LWW with `onConflict` when creating a repository:

```dart
final todoRepository = LocalFirstRepository<Todo>.create(
  name: 'todo',
  getId: (todo) => todo.id,
  toJson: (todo) => todo.toJson(),
  fromJson: Todo.fromJson,
  onConflictEvent: (local, remote) {
    final localUpdated = local.data.updatedAt;
    final remoteUpdated = remote.data.updatedAt;
    return remoteUpdated.isAfter(localUpdated) ? remote : local;
  },
);
```

## Server sync index

Keep a remote cursor per repository (commonly `server_sequence` or `server_created_at`) so pulls fetch only new/changed events. Store this cursor in config/meta storage and advance it after each successful pull; this keeps sync idempotent and efficient when talking to any backend API.

## Example app overview

The bundled demo is a multi-user, namespaced counter with user profiles and session counters. It shows repositories talking to storage, config/meta reads/writes, and a sync strategy exchanging events with a mock backend. Use it as a blueprint for wiring your own models and strategies.

## Running the examples

Each adapter ships the same demo. Choose the storage you want to explore and run:

- `local_first/example` (in-memory for dev)
- `local_first_hive_storage/example` (Hive storage)
- `local_first_sqlite_storage/example` (SQLite storage)
- `local_first_shared_preferences/example` (config-only storage)

From inside the chosen folder: `flutter run`.

## Features

- Offline-first caching with automatic retry when connectivity is restored.
- Typed repositories for common CRUD flows.
- Conflict handling strategies (last-write-wins, timestamps, and custom resolution hooks).
- Background sync hooks for push/pull cycles.
- Encryption-ready storage layer by leveraging your chosen database/provider.
- Dev-friendly: simple configuration, verbose logging, and test utilities.

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  local_first: ^0.6.0
  local_first_hive_storage: ^0.2.0  # optional
  local_first_sqlite_storage: ^0.2.0 # optional
  local_first_shared_preferences: ^0.1.0 # optional (config storage only)
```

Then install it with:

```bash
flutter pub get
```

## Quick start

The API is evolving, but the intended flow looks like this:

```dart
import 'package:local_first/local_first.dart';

// 1) Describe your model (no mixin needed). LocalFirstEvent will wrap it with
//    sync metadata. Keep your dates in UTC.
class Todo {
  const Todo({
    required this.id,
    required this.title,
    this.completed = false,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final bool completed;
  final DateTime updatedAt;

  JsonMaptoJson() => {
        'id': id,
        'title': title,
        'completed': completed,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Todo.fromJson(JsonMapjson) => Todo(
        id: json['id'] as String,
        title: json['title'] as String,
        completed: json['completed'] as bool? ?? false,
        updatedAt: DateTime.parse(json['updated_at']).toUtc(),
      );

  // Last write wins.
  static Todo resolveConflict(Todo local, Todo remote) =>
      local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
}

// 2) Create a repository for the model.
final todoRepository = LocalFirstRepository<Todo>.create(
  name: 'todo',
  getId: (todo) => todo.id,
  toJson: (todo) => todo.toJson(),
  fromJson: Todo.fromJson,
  onConflict: Todo.resolveConflict,
);

Future<void> main() async {
  // 3) Wire up local storage plus your sync strategy.
  final client = LocalFirstClient(
    repositories: [todoRepository],
    // Choose your adapter (add dependency and import it):
    // import 'package:local_first_hive_storage/local_first_hive_storage.dart';
    // import 'package:local_first_sqlite_storage/local_first_sqlite_storage.dart';
    localStorage: HiveLocalFirstStorage(), // or SqliteLocalFirstStorage()
    syncStrategies: [
      // Provide your own strategy that implements DataSyncStrategy.
      MyRestSyncStrategy(),
    ],
  );

  await client.initialize();

  // 4) Use the repository as if you were online the whole time.
  //    LocalFirstEvent is created internally and keeps sync metadata immutable.
  await todoRepository.upsert(
    Todo(id: '1', title: 'Buy milk', updatedAt: DateTime.now().toUtc()),
    needSync: true,
  );

  // served instantly from local cache
  final todoStream = todoRepository.query().orderBy('title').watch();

  // 5) Let your strategy push/pull, or trigger manually when it makes sense.
  // await client.sync();
}
```

### Choose your storage backend

- **Hive**: schema-less, fast key/value boxes. Add `local_first_hive_storage` and use `HiveLocalFirstStorage()` (default in the basic example).
- **SQLite**: structured tables with indexes for query filters/sorts. Add `local_first_sqlite_storage` and use `SqliteLocalFirstStorage()`, providing a schema when creating repositories:

```dart
final todoRepository = LocalFirstRepository<Todo>.create(
  name: 'todo',
  getId: (todo) => todo.id,
  toJson: (todo) => todo.toJson(),
  fromJson: Todo.fromJson,
  onConflict: Todo.resolveConflict,
  schema: const {
    'title': LocalFieldType.text,
    'completed': LocalFieldType.boolean,
    'updated_at': LocalFieldType.datetime,
  },
);
final client = LocalFirstClient(
  repositories: [todoRepository],
  localStorage: SqliteLocalFirstStorage(),
  syncStrategies: [MyRestSyncStrategy()],
);
```

## Example app

A starter Flutter app lives in `example/` and showcases the local-first flow to increment or decrement a global shared counter (per-user namespaces, repositories, and a Mongo sync mock).

```bash
# Clone and fetch deps
git clone https://github.com/rafaelsetragni/local_first.git
cd local_first
flutter pub get

# Run the sample
cd example
flutter pub get
flutter run

# (Optional) Start the Mongo mock used by the sync strategy.
# docker run -d --name mongo_local -p 27017:27017 \\
#   -e MONGO_INITDB_ROOT_USERNAME=admin \\
#   -e MONGO_INITDB_ROOT_PASSWORD=admin mongo:7
```

## Roadmap

- [X] Implement Hive and SQLite storage adapters via add-on packages.
- [ ] Provide REST and WebSocket sync strategies via add-on packages.
- [ ] Background sync helpers for Android/iOS via add-on packages.
- [X] End-to-end sample app with authentication.
- [X] Comprehensive docs and testing utilities (models now use `LocalFirstModel` mixin; full test coverage added).

## Contributing

Contributions are welcome! Please open an issue to discuss ideas or bugs, and feel free to submit pull requests once we agree on the approach. Running the test suite before sending changes helps keep the package stable:

```bash
flutter test
```

## License

This project is available under the MIT License. See `LICENSE` for details.
