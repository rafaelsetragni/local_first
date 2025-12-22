# local_first_sqlite_storage
[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](#)
[![Discord](https://img.shields.io/discord/888523488376279050.svg?style=for-the-badge&colorA=7289da&label=Chat%20on%20Discord)](https://discord.awesome-notifications.carda.me)

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=103)](#)
[![pub package](https://img.shields.io/pub/v/local_first_sqlite_storage.svg)](https://pub.dev/packages/local_first_sqlite_storage)
![Full tests workflow](https://github.com/rafaelsetragni/local_first/actions/workflows/dart.yml/badge.svg?branch=main)
[![codecov](https://codecov.io/github/rafaelsetragni/local_first/graph/badge.svg?token=7BRG8JcWTQ)](https://codecov.io/github/rafaelsetragni/local_first)

Child package of the [local_first](https://pub.dev/packages/local_first) ecosystem. This SQLite adapter provides structured tables with typed schemas, indexes, and server-like filtering/sorting for offline-first apps.

## Why use this adapter?

- Structured schema with per-column indexes.
- Rich query filters (`whereIn`, comparisons, null checks), sorting, limit/offset.
- JSON fallback for non-schema fields.
- Namespaces and metadata storage.
- Reactive `watchQuery` updates on data changes.

## Installation

Add the core and the SQLite adapter to your `pubspec.yaml`:

```yaml
dependencies:
  local_first: ^0.5.0
  local_first_sqlite_storage: ^0.1.0
```

## Quick start

```dart
import 'package:local_first/local_first.dart';
import 'package:local_first_sqlite_storage/local_first_sqlite_storage.dart';

class Todo with LocalFirstModel {
  Todo({required this.id, required this.title})
      : updatedAt = DateTime.now();

  final String id;
  final String title;
  final DateTime updatedAt;

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Todo.fromJson(Map<String, dynamic> json) => Todo(
        id: json['id'] as String,
        title: json['title'] as String,
      );

  static Todo resolveConflict(Todo local, Todo remote) =>
      local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
}

final todoRepository = LocalFirstRepository.create<Todo>(
  name: 'todo',
  getId: (todo) => todo.id,
  toJson: (todo) => todo.toJson(),
  fromJson: Todo.fromJson,
  onConflict: Todo.resolveConflict,
  schema: const {
    'title': LocalFieldType.text,
    'updated_at': LocalFieldType.datetime,
  },
);

Future<void> main() async {
  final client = LocalFirstClient(
    repositories: [todoRepository],
    localStorage: SqliteLocalFirstStorage(),
    syncStrategies: [
      // Provide your own strategy implementing DataSyncStrategy.
    ],
  );

  await client.initialize();
  await todoRepository.upsert(Todo(id: '1', title: 'Buy milk'));
}
```

## Features

- Creates tables and indexes based on provided schema.
- Query builder with comparisons, IN/NOT IN, null checks, sorting, limit/offset.
- Stores full JSON in a `data` column and leverages schema columns for performance.
- Namespaces and metadata (`setMeta` / `getMeta`).
- Reactive `watchQuery`.

## Testing

Run tests from this package root:

```
flutter test
```

## License

MIT (see LICENSE).
