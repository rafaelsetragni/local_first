# local_first_hive_storage

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](#)
[![Discord](https://img.shields.io/discord/888523488376279050.svg?style=for-the-badge&colorA=7289da&label=Chat%20on%20Discord)](https://discord.awesome-notifications.carda.me)

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=103)](#)
[![pub package](https://img.shields.io/pub/v/local_first_hive_storage.svg)](https://pub.dev/packages/local_first_hive_storage)
![Full tests workflow](https://github.com/rafaelsetragni/local_first/actions/workflows/dart.yml/badge.svg?branch=main)
[![codecov](https://codecov.io/github/rafaelsetragni/local_first/graph/badge.svg?token=7BRG8JcWTQ)](https://codecov.io/github/rafaelsetragni/local_first)

<br>

A fast, schema-less storage adapter for the [local_first](https://pub.dev/packages/local_first) ecosystem. Built on Hive's lightning-fast key-value storage with support for namespaces, reactive queries, and metadata management.

> **Note:** This is a companion package to `local_first`. You need to install the core package first.

## Why local_first_hive_storage?

- **Blazing Fast**: Hive's pure Dart implementation is optimized for mobile performance
- **Schema-less**: No column definitions needed - store your model maps directly
- **Zero Configuration**: Works out of the box with sensible defaults
- **Reactive**: Built-in `watchQuery` for real-time UI updates
- **Namespace Support**: Multi-user isolation with `useNamespace`
- **Metadata Storage**: Persistent config values via `setConfigValue`/`getConfigValue`
- **Lazy Loading**: Optional lazy boxes for memory-efficient large datasets

## Features

- ✅ **Pure Dart**: No native dependencies, works on all Flutter platforms
- ✅ **Key-Value Storage**: Fast Hive boxes for each repository
- ✅ **Schema-less**: Store JSON maps without defining schemas
- ✅ **Namespaces**: Isolate data per user or tenant
- ✅ **Reactive Queries**: `watchQuery` with real-time updates
- ✅ **Metadata Table**: Store app configuration and sync state
- ✅ **Lazy Collections**: Reduce memory usage for large datasets
- ✅ **CRUD Operations**: Full support for create, read, update, delete
- ✅ **Query Filtering**: In-memory filtering after load

## Installation

Add the core package and Hive adapter to your `pubspec.yaml`:

```yaml
dependencies:
  local_first: ^0.6.0
  local_first_hive_storage: ^0.2.0
```

Then install it with:

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:local_first/local_first.dart';
import 'package:local_first_hive_storage/local_first_hive_storage.dart';

// 1) Define your model (keep it immutable)
class Todo {
  const Todo({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime updatedAt;

  JsonMap toJson() => {
        'id': id,
        'title': title,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Todo.fromJson(JsonMap json) => Todo(
        id: json['id'] as String,
        title: json['title'] as String,
        updatedAt: DateTime.parse(json['updated_at']).toUtc(),
      );

  static Todo resolveConflict(Todo local, Todo remote) =>
      local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
}

// 2) Create repository
final todoRepository = LocalFirstRepository<Todo>.create(
  name: 'todo',
  getId: (todo) => todo.id,
  toJson: (todo) => todo.toJson(),
  fromJson: Todo.fromJson,
  onConflict: Todo.resolveConflict,
);

// 3) Initialize client with Hive storage
Future<void> main() async {
  final client = LocalFirstClient(
    repositories: [todoRepository],
    localStorage: HiveLocalFirstStorage(),
    syncStrategies: [
      // Add your sync strategy here
    ],
  );

  await client.initialize();

  // 4) Use the repository
  await todoRepository.upsert(
    Todo(
      id: '1',
      title: 'Buy milk',
      updatedAt: DateTime.now().toUtc(),
    ),
    needSync: true,
  );

  // 5) Query data
  final todos = await todoRepository.getAll();
  print('Todos: ${todos.length}');
}
```

## Architecture

### Storage Structure

```
┌────────────────────────────────────────────┐
│      HiveLocalFirstStorage                 │
│  ┌──────────────────────────────────────┐  │
│  │  Metadata Box (__config__)           │  │
│  │  - Sync sequences                    │  │
│  │  - App configuration                 │  │
│  │  - Namespace state                   │  │
│  └──────────────────────────────────────┘  │
│                                            │
│  ┌──────────────────────────────────────┐  │
│  │  Repository Boxes                    │  │
│  │  ┌────────────────────────────────┐  │  │
│  │  │  todo_box                      │  │  │
│  │  │  key: eventId → JsonMap        │  │  │
│  │  └────────────────────────────────┘  │  │
│  │  ┌────────────────────────────────┐  │  │
│  │  │  user_box                      │  │  │
│  │  │  key: eventId → JsonMap        │  │  │
│  │  └────────────────────────────────┘  │  │
│  └──────────────────────────────────────┘  │
└────────────────────────────────────────────┘
```

### Data Flow

```
┌─────────────────────────────────────────┐
│  Application Code                       │
│  todoRepository.upsert(todo)            │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│  LocalFirstClient                       │
│  - Creates LocalFirstEvent              │
│  - Wraps data with metadata             │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│  HiveLocalFirstStorage                  │
│  - Serializes to JsonMap                │
│  - Stores in Hive box                   │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│  Hive Box (Disk)                        │
│  eventId: {id, operation, data, ...}    │
└─────────────────────────────────────────┘
```

## Configuration Options

### Lazy Collections

Enable lazy boxes to reduce memory usage for large datasets:

```dart
final storage = HiveLocalFirstStorage(
  lazyCollections: true, // Default: false
);
```

**When to use:**
- ✅ Large datasets (>10,000 records per repository)
- ✅ Memory-constrained devices
- ✅ Repositories with infrequent access

**When NOT to use:**
- ❌ Small datasets (<1,000 records)
- ❌ Frequently accessed repositories
- ❌ Real-time reactive queries (performance impact)

### Namespace Support

Isolate data per user or tenant:

```dart
final storage = HiveLocalFirstStorage();
await storage.initialize();

// Switch to user Alice's namespace
await storage.useNamespace('user_alice');

// All operations now affect Alice's data
await todoRepository.upsert(todo);

// Switch to user Bob's namespace
await storage.useNamespace('user_bob');

// Now operating on Bob's data
final bobTodos = await todoRepository.getAll();
```

**Use cases:**
- 👤 Multi-user applications
- 🏢 Multi-tenant apps
- 📱 Multiple accounts support
- 🔐 Data isolation requirements

## Supported Config Types

The metadata storage supports these types via `setConfigValue`/`getConfigValue`:

| Type | Example | Use Case |
|------|---------|----------|
| `bool` | `true` | Feature flags, preferences |
| `int` | `42` | Counters, sync sequences |
| `double` | `3.14` | Ratings, calculations |
| `String` | `'hello'` | User names, tokens |
| `List<String>` | `['a', 'b']` | Tags, categories |

### Example: Storing Metadata

```dart
final client = LocalFirstClient(
  repositories: [todoRepository],
  localStorage: HiveLocalFirstStorage(),
  syncStrategies: [],
);

await client.initialize();

// Store sync sequence
await client.setConfigValue('last_sync_seq', 42);

// Store user preference
await client.setConfigValue('dark_mode', true);

// Store feature flags
await client.setConfigValue('enabled_features', ['chat', 'notifications']);

// Retrieve values
final lastSeq = await client.getConfigValue<int>('last_sync_seq');
final darkMode = await client.getConfigValue<bool>('dark_mode');
final features = await client.getConfigValue<List<String>>('enabled_features');
```

## Reactive Queries

Watch for real-time updates:

```dart
// Watch all todos
final stream = todoRepository.watchQuery();

stream.listen((todos) {
  print('Todos updated: ${todos.length}');
});

// In Flutter
StreamBuilder<List<LocalFirstEvent<Todo>>>(
  stream: todoRepository.watchQuery(),
  builder: (context, snapshot) {
    if (!snapshot.hasData) return CircularProgressIndicator();

    final events = snapshot.data!;
    final todos = events.map((e) => e.data).toList();

    return ListView.builder(
      itemCount: todos.length,
      itemBuilder: (context, index) => TodoTile(todos[index]),
    );
  },
)
```

## Comparison with SQLite Storage

| Feature | HiveLocalFirstStorage | SqliteLocalFirstStorage |
|---------|----------------------|------------------------|
| **Performance** | Faster (pure Dart) | Fast (native SQLite) |
| **Schema** | Schema-less | Schema-based |
| **Query Capabilities** | In-memory filtering | Rich SQL queries |
| **Indexes** | No indexes | Column indexes |
| **Storage Size** | Smaller | Larger (with indexes) |
| **Setup Complexity** | Zero config | Define schemas |
| **Best For** | Simple models, speed | Complex queries, filtering |
| **Platform Support** | All platforms | All platforms |
| **Memory Usage** | Low (with lazy) | Very low |

**Choose Hive when:**
- ✅ You want the fastest performance
- ✅ Your models are simple and don't need complex filtering
- ✅ You prefer zero configuration
- ✅ You're building for mobile/web and want pure Dart

**Choose SQLite when:**
- ✅ You need complex SQL queries
- ✅ You want indexed filtering and sorting
- ✅ Your data has relational aspects
- ✅ You need advanced query capabilities

## CRUD Operations

### Create/Update (Upsert)

```dart
await todoRepository.upsert(
  Todo(id: '1', title: 'Buy milk', updatedAt: DateTime.now()),
  needSync: true, // Mark for synchronization
);
```

### Read Single Item

```dart
final event = await todoRepository.getById('1');
if (event != null) {
  print('Todo: ${event.data.title}');
}
```

### Read All Items

```dart
final events = await todoRepository.getAll();
final todos = events.map((e) => e.data).toList();
```

### Delete

```dart
await todoRepository.delete('1', needSync: true);
```

### Query with Filter

```dart
// Note: Hive loads all data then filters in memory
final events = await todoRepository.query();
final incompleteTodos = events
    .map((e) => e.data)
    .where((todo) => !todo.completed)
    .toList();
```

## Best Practices

### 1. Use Lazy Boxes for Large Datasets

```dart
// For repositories with >10k records
final storage = HiveLocalFirstStorage(lazyCollections: true);
```

### 2. Keep Models Immutable

```dart
class Todo {
  const Todo({required this.id, required this.title}); // Immutable

  final String id;
  final String title;

  // Use copyWith for updates
  Todo copyWith({String? title}) => Todo(
    id: id,
    title: title ?? this.title,
  );
}
```

### 3. Handle Conflicts Properly

```dart
static Todo resolveConflict(Todo local, Todo remote) {
  // Last-write-wins based on timestamp
  return local.updatedAt.isAfter(remote.updatedAt) ? local : remote;

  // Or merge fields
  // return Todo(
  //   id: local.id,
  //   title: remote.title, // Take remote title
  //   completed: local.completed, // Keep local completion status
  // );
}
```

### 4. Use Namespaces for Multi-User Apps

```dart
// On login
await storage.useNamespace('user_${userId}');

// On logout
await storage.useNamespace(null); // Clear namespace
```

### 5. Store Metadata for Sync State

```dart
// Save last sync sequence
await client.setConfigValue('__last_seq__$repositoryName', sequence);

// Load on next sync
final lastSeq = await client.getConfigValue<int>('__last_seq__$repositoryName');
```

## Troubleshooting

### Data Not Persisting

**Symptoms:** Data disappears after app restart

**Solutions:**
1. Ensure you await `client.initialize()`:
   ```dart
   await client.initialize(); // Don't forget await!
   ```
2. Check that Hive boxes are being opened:
   ```dart
   // Enable Hive logging
   Hive.init(path); // Ensure path is correct
   ```

### Performance Issues with Large Datasets

**Symptoms:** Slow queries or high memory usage

**Solutions:**
1. Enable lazy collections:
   ```dart
   HiveLocalFirstStorage(lazyCollections: true)
   ```
2. Implement pagination at application level:
   ```dart
   final page1 = todos.skip(0).take(20).toList();
   final page2 = todos.skip(20).take(20).toList();
   ```

### Namespace Data Isolation Issues

**Symptoms:** Data from different users mixing

**Solutions:**
1. Always call `useNamespace` before operations:
   ```dart
   await storage.useNamespace('user_$userId');
   await todoRepository.getAll(); // Now isolated
   ```
2. Verify namespace is set:
   ```dart
   print('Current namespace: ${storage.currentNamespace}');
   ```

### Box Already Open Errors

**Symptoms:** `HiveError: Box is already open`

**Solutions:**
1. Don't manually open Hive boxes - let the adapter handle it
2. Only create one `LocalFirstClient` instance:
   ```dart
   // Good: Singleton
   static final client = LocalFirstClient(...);

   // Bad: Multiple instances
   final client1 = LocalFirstClient(...);
   final client2 = LocalFirstClient(...); // ❌ Don't do this
   ```

### watchQuery Not Updating

**Symptoms:** UI not reflecting changes

**Solutions:**
1. Ensure you're using `needSync: true`:
   ```dart
   await todoRepository.upsert(todo, needSync: true);
   ```
2. Check that StreamBuilder is properly set up:
   ```dart
   StreamBuilder<List<LocalFirstEvent<Todo>>>(
     stream: todoRepository.watchQuery(), // Correct
     // NOT: stream: todoRepository.query(), // ❌ Wrong
   ```

## Testing

### Unit Tests

Run tests from this package root:

```bash
flutter test
```

### Integration Tests

```bash
flutter test integration_test/
```

### Mock Storage for Tests

```dart
// Use in-memory storage for tests
final testClient = LocalFirstClient(
  repositories: [todoRepository],
  localStorage: InMemoryLocalFirstStorage(), // No disk I/O
  syncStrategies: [],
);
```

## Example App

This package includes a complete example demonstrating:
- Hive storage setup
- REST API sync with PeriodicSyncStrategy
- Multi-repository support
- Namespace isolation
- Reactive UI updates

To run the example:

```bash
cd local_first_hive_storage/example
flutter pub get
flutter run
```

See the [example README](example/README.md) for detailed setup instructions including server configuration.

## Contributing

Contributions are welcome! Please open an issue to discuss ideas or bugs. See the main [local_first](https://pub.dev/packages/local_first) repository for contribution guidelines.

## License

This project is available under the MIT License. See `LICENSE` for details.
