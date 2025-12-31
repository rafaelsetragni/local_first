# Local First

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](#)
[![Discord](https://img.shields.io/discord/888523488376279050.svg?style=for-the-badge&colorA=7289da&label=Chat%20on%20Discord)](https://discord.awesome-notifications.carda.me)

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=103)](#)
[![pub package](https://img.shields.io/pub/v/local_first.svg)](https://pub.dev/packages/local_first)
![Full tests workflow](https://github.com/rafaelsetragni/local_first/actions/workflows/dart.yml/badge.svg?branch=main)
[![codecov](https://codecov.io/github/rafaelsetragni/local_first/graph/badge.svg?token=7BRG8JcWTQ)](https://codecov.io/github/rafaelsetragni/local_first)

<br>

Local-first data layer for Flutter apps that keeps your data available offline and synchronizes when the network returns. The goal is to provide a lightweight, pluggable engine that works with common local stores (Hive, SQLite, etc.) and can sync to any backend through custom strategies.

> Status: early preview. The package is in active development (final stages) and the public API may change before the first stable release. Use the examples below as guidance for the intended design.

![Demo](https://live-update-demo.rafaelsetra.workers.dev/)

## Why local_first?

- Fast, responsive apps that read/write locally first and sync in the background.
- Works without a network connection; queues changes and resolves conflicts when back online.
- Storage-agnostic: start with our Hive, SQLite, or your preferred custom database implementation.
- Backend-agnostic: create your sync strategies, so you can integrate with your existent REST, gRPC, WebSockets, etc.
- Minimal boilerplate: declare the storage, register your models with repositories, and start syncing.

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
  local_first_hive_storage: ^0.0.1  # optional
  local_first_sqlite_storage: ^0.0.1 # optional
```

Then install it with:

```bash
flutter pub get
```

## Quick start

The API is evolving, but the intended flow looks like this:

```dart
import 'package:local_first/local_first.dart';

// 1) Describe your model (no mixin required).
class Todo {
  Todo({
    required this.id,
    required this.title,
    this.completed = false,
  }) : updatedAt = DateTime.now();

  final String id;
  final String title;
  final bool completed;
  final DateTime updatedAt;
  JsonMap toJson() => {
        'id': id,
        'title': title,
        'completed': completed,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Todo.fromJson(JsonMap json) => Todo(
        id: json['id'] as String,
        title: json['title'] as String,
        completed: json['completed'] as bool? ?? false,
        updatedAt: DateTime.parse(json['updated_at']),
      );

  // Last write wins.
  static Todo resolveConflict(Todo local, Todo remote) =>
      local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
}

// Sync metadata is tracked separately via LocalFirstEvent during sync flows.

// 2) Create a repository for the model.
final todoRepository = LocalFirstRepository.create<Todo>(
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
  await todoRepository.upsert(Todo(id: '1', title: 'Buy milk'));

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
final todoRepository = LocalFirstRepository.create<Todo>(
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
- [X] Comprehensive docs and testing utilities (models use `LocalFirstEvent` wrapper; full test coverage added).

## Contributing

Contributions are welcome! Please open an issue to discuss ideas or bugs, and feel free to submit pull requests once we agree on the approach. Running the test suite before sending changes helps keep the package stable:

```bash
flutter test
```

## License

This project is available under the MIT License. See `LICENSE` for details.
