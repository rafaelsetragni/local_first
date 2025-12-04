# local_first

Local-first data layer for Flutter apps that keeps your data available offline and synchronizes when the network returns. The goal is to provide a lightweight, pluggable engine that works with common local stores (Hive, SQLite, etc.) and can sync to any backend through custom adapters.

> Status: early preview. The package is in active development and the public API may change before the first stable release. Use the examples below as guidance for the intended design.

## Why local_first?

- Fast, responsive apps that read/write locally first and sync in the background.
- Works without a network connection; queues changes and resolves conflicts when back online.
- Pluggable storage: start with Hive, SQLite, or your preferred database.
- Backend-agnostic sync adapters so you can integrate with REST, gRPC, WebSockets, or custom APIs.
- Minimal boilerplate: declare your model, register adapters, and start syncing.

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
  local_first: ^0.0.1
```

Then install it with:

```bash
flutter pub get
```

## Quick start

The API is evolving, but the intended flow looks like this:

```dart
import 'package:local_first/local_first.dart';

// 1) Describe your model.
class Todo {
  Todo({required this.id, required this.title, this.completed = false});

  final String id;
  final String title;
  final bool completed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'completed': completed,
      };

  static Todo fromJson(Map<String, dynamic> json) => Todo(
        id: json['id'] as String,
        title: json['title'] as String,
        completed: json['completed'] as bool? ?? false,
      );
}

Future<void> main() async {
  // 2) Wire up local + remote adapters (implementation details coming soon).
  final client = LocalFirstClient(
    local: HiveStore(boxName: 'todos'), // or SQLiteStore/your own store
    remote: RestSyncAdapter(
      baseUrl: 'https://api.example.com',
      endpoint: '/todos',
    ),
    serializer: JsonSerializer<Todo>(
      fromJson: Todo.fromJson,
      toJson: (todo) => todo.toJson(),
    ),
  );

  await client.init();

  // 3) Use the repository as if you were online the whole time.
  final repo = client.repository<Todo>();

  await repo.save(Todo(id: '1', title: 'Buy milk'));
  final todos = await repo.getAll(); // served instantly from local cache

  // 4) Trigger sync when it makes sense (app start, pull-to-refresh, background).
  await client.sync();
}
```

> The classes above illustrate the design goals; exact names and signatures may shift as the package matures.

## Example app

A starter Flutter app lives in `example/` and will showcase the offline-first flow as features land:

```bash
cd example
flutter run
```

## Roadmap

- [ ] Implement Hive and SQLite storage adapters.
- [ ] Provide REST and WebSocket sync adapters.
- [ ] Add conflict resolution policies and hooks.
- [ ] Background sync helpers for Android/iOS.
- [ ] End-to-end sample app with authentication.
- [ ] Comprehensive docs and testing utilities.

## Contributing

Contributions are welcome! Please open an issue to discuss ideas or bugs, and feel free to submit pull requests once we agree on the approach. Running the test suite before sending changes helps keep the package stable:

```bash
flutter test
```

## License

This project is available under the MIT License. See `LICENSE` for details.
