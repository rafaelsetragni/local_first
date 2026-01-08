# local_first_hive_storage
[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](#)
[![Discord](https://img.shields.io/discord/888523488376279050.svg?style=for-the-badge&colorA=7289da&label=Chat%20on%20Discord)](https://discord.awesome-notifications.carda.me)

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=103)](#)
[![pub package](https://img.shields.io/pub/v/local_first_hive_storage.svg)](https://pub.dev/packages/local_first_hive_storage)
![Full tests workflow](https://github.com/rafaelsetragni/local_first/actions/workflows/dart.yml/badge.svg?branch=main)
[![codecov](https://codecov.io/github/rafaelsetragni/local_first/graph/badge.svg?token=7BRG8JcWTQ)](https://codecov.io/github/rafaelsetragni/local_first)

Child package of the [local_first](https://pub.dev/packages/local_first) ecosystem. This Hive adapter provides schema-less, offline-first storage using Hive boxes, plus metadata support and reactive queries.

## Why use this adapter?

- Fast key/value storage with Hive.
- Schema-less: store your model maps directly, no column definitions needed.
- Namespaces for multi-user isolation (`useNamespace`).
- Reactive queries via `watchQuery`.
- Metadata storage via `setMeta` / `getMeta`.

## Installation

Add the core and the Hive adapter to your `pubspec.yaml`:

```yaml
dependencies:
  local_first: ^0.5.0
  local_first_hive_storage: ^0.1.0
```

## Quick start

```dart
import 'package:local_first/local_first.dart';
import 'package:local_first_hive_storage/local_first_hive_storage.dart';

// Keep your model immutable; LocalFirstEvent wraps it with sync metadata.
class Todo {
  const Todo({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Todo.fromJson(Map<String, dynamic> json) => Todo(
        id: json['id'] as String,
        title: json['title'] as String,
        updatedAt: DateTime.parse(json['updated_at']).toUtc(),
      );

  static Todo resolveConflict(Todo local, Todo remote) =>
      local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
}

final todoRepository = LocalFirstRepository<Todo>.create(
  name: 'todo',
  getId: (todo) => todo.id,
  toJson: (todo) => todo.toJson(),
  fromJson: Todo.fromJson,
  onConflict: Todo.resolveConflict,
);

Future<void> main() async {
  final client = LocalFirstClient(
    repositories: [todoRepository],
    localStorage: HiveLocalFirstStorage(),
    syncStrategies: [
      // Provide your own strategy implementing DataSyncStrategy.
    ],
  );

  await client.initialize();
  await todoRepository.upsert(
    Todo(
      id: '1',
      title: 'Buy milk',
      updatedAt: DateTime.now().toUtc(),
    ),
  );
}
```

## Features

- Schema-less Hive boxes (lazy boxes supported via `lazyCollections`).
- Namespaced storage with `useNamespace`.
- Reactive queries (`watchQuery`) and standard CRUD operations.
- Metadata table for app/client state (`setMeta` / `getMeta`).

## Testing

Run tests from this package root:

```
flutter test
```

## License

MIT (see LICENSE).
