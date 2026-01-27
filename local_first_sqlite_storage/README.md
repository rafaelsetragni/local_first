# local_first_sqlite_storage

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](#)
[![Discord](https://img.shields.io/discord/888523488376279050.svg?style=for-the-badge&colorA=7289da&label=Chat%20on%20Discord)](https://discord.awesome-notifications.carda.me)

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=103)](#)
[![pub package](https://img.shields.io/pub/v/local_first_sqlite_storage.svg)](https://pub.dev/packages/local_first_sqlite_storage)
![Full tests workflow](https://github.com/rafaelsetragni/local_first/actions/workflows/dart.yml/badge.svg?branch=main)
[![codecov](https://codecov.io/github/rafaelsetragni/local_first/graph/badge.svg?token=7BRG8JcWTQ)](https://codecov.io/github/rafaelsetragni/local_first)

<br>

A powerful, schema-based storage adapter for the [local_first](https://pub.dev/packages/local_first) ecosystem. Built on SQLite with support for typed schemas, column indexes, rich queries, and reactive updates.

> **Note:** This is a companion package to `local_first`. You need to install the core package first.

## Why local_first_sqlite_storage?

- **Schema-based**: Define typed columns with automatic table creation
- **Rich Queries**: SQL-powered filtering, sorting, limit/offset, and null checks
- **Column Indexes**: Fast lookups on indexed fields
- **Battle-tested**: Built on SQLite, the world's most deployed database
- **Reactive**: Real-time UI updates with `watchQuery`
- **Namespace Support**: Multi-user isolation with `useNamespace`
- **JSON Fallback**: Schema columns for performance, JSON for flexibility

## Features

- ✅ **Typed Schemas**: Define columns with `LocalFieldType` (text, int, double, datetime, bool)
- ✅ **Automatic Indexes**: Create indexes on schema columns for fast queries
- ✅ **Rich Query Builder**: SQL-based filtering with comparisons, IN/NOT IN, null checks
- ✅ **Sorting**: Order by any column (ascending/descending)
- ✅ **Pagination**: Limit and offset support for large datasets
- ✅ **Reactive Queries**: `watchQuery` with real-time updates
- ✅ **Metadata Storage**: Store app configuration and sync state
- ✅ **Namespaces**: Isolate data per user or tenant
- ✅ **Full CRUD**: Complete create, read, update, delete operations
- ✅ **JSON Storage**: Full object stored in `data` column + schema columns

## Installation

Add the core package and SQLite adapter to your `pubspec.yaml`:

```yaml
dependencies:
  local_first: ^0.6.0
  local_first_sqlite_storage: ^0.2.0
```

Then install it with:

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:local_first/local_first.dart';
import 'package:local_first_sqlite_storage/local_first_sqlite_storage.dart';

// 1) Define your model (keep it immutable)
class Todo {
  const Todo({
    required this.id,
    required this.title,
    required this.completed,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final bool completed;
  final DateTime updatedAt;

  JsonMap toJson() => {
        'id': id,
        'title': title,
        'completed': completed,
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory Todo.fromJson(JsonMap json) => Todo(
        id: json['id'] as String,
        title: json['title'] as String,
        completed: json['completed'] as bool,
        updatedAt: DateTime.parse(json['updated_at']).toUtc(),
      );

  static Todo resolveConflict(Todo local, Todo remote) =>
      local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
}

// 2) Create repository with schema
final todoRepository = LocalFirstRepository<Todo>.create(
  name: 'todo',
  getId: (todo) => todo.id,
  toJson: (todo) => todo.toJson(),
  fromJson: Todo.fromJson,
  onConflict: Todo.resolveConflict,
  schema: const {
    'title': LocalFieldType.text,        // Indexed text column
    'completed': LocalFieldType.bool,    // Indexed boolean column
    'updated_at': LocalFieldType.datetime, // Indexed datetime column
  },
);

// 3) Initialize client with SQLite storage
Future<void> main() async {
  final client = LocalFirstClient(
    repositories: [todoRepository],
    localStorage: SqliteLocalFirstStorage(),
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
      completed: false,
      updatedAt: DateTime.now().toUtc(),
    ),
    needSync: true,
  );

  // 5) Query with filters (uses indexed columns!)
  final incompleteTodos = await todoRepository.query(
    where: (fields) => fields['completed'].equals(false),
    orderBy: [OrderBy('updated_at', OrderDirection.desc)],
    limit: 10,
  );
}
```

## Architecture

### Storage Structure

```
┌────────────────────────────────────────────┐
│      SqliteLocalFirstStorage               │
│  ┌──────────────────────────────────────┐  │
│  │  Metadata Table (__config__)         │  │
│  │  key (TEXT) | value (TEXT)           │  │
│  │  - Sync sequences                    │  │
│  │  - App configuration                 │  │
│  └──────────────────────────────────────┘  │
│                                            │
│  ┌──────────────────────────────────────┐  │
│  │  Repository Tables                   │  │
│  │  ┌────────────────────────────────┐  │  │
│  │  │  todo (table)                  │  │  │
│  │  │  eventId (TEXT) PRIMARY KEY    │  │  │
│  │  │  data (TEXT) -- Full JSON      │  │  │
│  │  │  title (TEXT) INDEXED          │  │  │
│  │  │  completed (INTEGER) INDEXED   │  │  │
│  │  │  updated_at (INTEGER) INDEXED  │  │  │
│  │  └────────────────────────────────┘  │  │
│  │  ┌────────────────────────────────┐  │  │
│  │  │  user (table)                  │  │  │
│  │  │  eventId (TEXT) PRIMARY KEY    │  │  │
│  │  │  data (TEXT)                   │  │  │
│  │  │  name (TEXT) INDEXED           │  │  │
│  │  │  email (TEXT) INDEXED          │  │  │
│  │  └────────────────────────────────┘  │  │
│  └──────────────────────────────────────┘  │
└────────────────────────────────────────────┘
```

### How Schema Works

1. **Full JSON Storage**: Complete object stored in `data` column
2. **Schema Columns**: Extracted fields stored in typed columns with indexes
3. **Query Optimization**: Filters use indexed columns, then reconstruct full object from `data`

```
┌─────────────────────────────────────────┐
│  Application Code                       │
│  todoRepository.query(                  │
│    where: (f) => f['completed'] == false│
│  )                                       │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│  LocalFirstRepository                   │
│  - Builds query from where clause       │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│  SqliteLocalFirstStorage                │
│  - Converts to SQL:                     │
│    SELECT * FROM todo                   │
│    WHERE completed = 0  -- Uses index!  │
│  - Executes query                       │
│  - Deserializes from data column        │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│  SQLite Database                        │
│  - Uses index for fast lookup           │
│  - Returns matching rows                │
└─────────────────────────────────────────┘
```

## Supported Field Types

Define schema with these types:

| LocalFieldType | SQL Type | Dart Type | Use Case |
|---------------|----------|-----------|----------|
| `text` | TEXT | String | Names, descriptions, IDs |
| `int` | INTEGER | int | Counters, quantities |
| `double` | REAL | double | Prices, ratings |
| `datetime` | INTEGER | DateTime | Timestamps (stored as milliseconds) |
| `bool` | INTEGER | bool | Flags, completion status |

### Example Schema

```dart
final schema = const {
  'title': LocalFieldType.text,        // String field
  'priority': LocalFieldType.int,      // Integer field
  'price': LocalFieldType.double,      // Double field
  'due_date': LocalFieldType.datetime, // DateTime field
  'completed': LocalFieldType.bool,    // Boolean field
};
```

## Supported Config Types

Metadata storage supports these types via `setConfigValue`/`getConfigValue`:

| Type | Example | Use Case |
|------|---------|----------|
| `bool` | `true` | Feature flags, preferences |
| `int` | `42` | Counters, sync sequences |
| `double` | `3.14` | Ratings, calculations |
| `String` | `'hello'` | User names, tokens |
| `List<String>` | `['a', 'b']` | Tags, categories |

## Rich Query Builder

### Comparisons

```dart
// Equals
await todoRepository.query(
  where: (fields) => fields['completed'].equals(true),
);

// Greater than
await todoRepository.query(
  where: (fields) => fields['priority'].greaterThan(5),
);

// Less than
await todoRepository.query(
  where: (fields) => fields['due_date'].lessThan(DateTime.now()),
);

// Greater than or equal
await todoRepository.query(
  where: (fields) => fields['price'].greaterThanOrEqual(10.0),
);

// Less than or equal
await todoRepository.query(
  where: (fields) => fields['rating'].lessThanOrEqual(3.5),
);

// Not equals
await todoRepository.query(
  where: (fields) => fields['status'].notEquals('deleted'),
);
```

### IN and NOT IN

```dart
// IN - matches any value in list
await todoRepository.query(
  where: (fields) => fields['category'].whereIn(['work', 'personal', 'urgent']),
);

// NOT IN - excludes values in list
await todoRepository.query(
  where: (fields) => fields['status'].notIn(['deleted', 'archived']),
);
```

### Null Checks

```dart
// Is null
await todoRepository.query(
  where: (fields) => fields['deleted_at'].isNull(),
);

// Is not null
await todoRepository.query(
  where: (fields) => fields['assigned_to'].isNotNull(),
);
```

### Sorting

```dart
// Single column ascending
await todoRepository.query(
  orderBy: [OrderBy('title', OrderDirection.asc)],
);

// Single column descending
await todoRepository.query(
  orderBy: [OrderBy('updated_at', OrderDirection.desc)],
);

// Multiple columns
await todoRepository.query(
  orderBy: [
    OrderBy('priority', OrderDirection.desc),  // First by priority
    OrderBy('due_date', OrderDirection.asc),   // Then by due date
  ],
);
```

### Pagination

```dart
// First 20 items
await todoRepository.query(limit: 20);

// Skip first 20, get next 20
await todoRepository.query(limit: 20, offset: 20);

// Page 3 (items 40-59)
final page = 3;
final pageSize = 20;
await todoRepository.query(
  limit: pageSize,
  offset: (page - 1) * pageSize,
);
```

### Combined Queries

```dart
// Complex query combining multiple features
final urgentIncompleteTodos = await todoRepository.query(
  where: (fields) => fields['completed'].equals(false)
      .and(fields['priority'].greaterThan(7))
      .and(fields['category'].whereIn(['work', 'urgent'])),
  orderBy: [
    OrderBy('priority', OrderDirection.desc),
    OrderBy('due_date', OrderDirection.asc),
  ],
  limit: 10,
);
```

## Reactive Queries

Watch for real-time updates:

```dart
// Watch all todos
final stream = todoRepository.watchQuery();

stream.listen((todos) {
  print('Todos updated: ${todos.length}');
});

// Watch with filters
final incompleteStream = todoRepository.watchQuery(
  where: (fields) => fields['completed'].equals(false),
);

// In Flutter
StreamBuilder<List<LocalFirstEvent<Todo>>>(
  stream: todoRepository.watchQuery(
    where: (fields) => fields['completed'].equals(false),
    orderBy: [OrderBy('updated_at', OrderDirection.desc)],
  ),
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

## Comparison with Hive Storage

| Feature | SqliteLocalFirstStorage | HiveLocalFirstStorage |
|---------|------------------------|----------------------|
| **Performance** | Fast (native SQLite) | Faster (pure Dart) |
| **Schema** | Schema-based | Schema-less |
| **Query Capabilities** | Rich SQL queries | In-memory filtering |
| **Indexes** | Column indexes | No indexes |
| **Storage Size** | Larger (with indexes) | Smaller |
| **Setup Complexity** | Define schemas | Zero config |
| **Best For** | Complex queries, filtering | Simple models, speed |
| **Platform Support** | All platforms | All platforms |
| **Memory Usage** | Very low | Low (with lazy) |

**Choose SQLite when:**
- ✅ You need complex SQL queries
- ✅ You want indexed filtering and sorting
- ✅ Your data has many fields you'll filter by
- ✅ You need advanced query capabilities
- ✅ Performance with large datasets is critical

**Choose Hive when:**
- ✅ You want the fastest performance
- ✅ Your models are simple and don't need complex filtering
- ✅ You prefer zero configuration
- ✅ You're building for mobile/web and want pure Dart

## Namespace Support

Isolate data per user or tenant:

```dart
final storage = SqliteLocalFirstStorage();
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

## CRUD Operations

### Create/Update (Upsert)

```dart
await todoRepository.upsert(
  Todo(
    id: '1',
    title: 'Buy milk',
    completed: false,
    updatedAt: DateTime.now(),
  ),
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
// Uses indexes for fast filtering
final events = await todoRepository.query(
  where: (fields) => fields['completed'].equals(false),
  orderBy: [OrderBy('updated_at', OrderDirection.desc)],
  limit: 20,
);
```

## Best Practices

### 1. Define Schemas for Fields You'll Query

```dart
// Good: Schema includes fields you'll filter/sort by
final schema = const {
  'title': LocalFieldType.text,      // Will search by title
  'completed': LocalFieldType.bool,  // Will filter by status
  'priority': LocalFieldType.int,    // Will sort by priority
  'updated_at': LocalFieldType.datetime, // Will sort by date
};

// Less efficient: Missing fields you'll query
final schema = const {
  'title': LocalFieldType.text, // Only title indexed
  // completed, priority not in schema - will be slower to query
};
```

### 2. Use Proper Field Types

```dart
// Good: Use datetime for timestamps
final schema = const {
  'created_at': LocalFieldType.datetime, // Stored as int, can compare dates
};

// Bad: String timestamps are hard to compare
final schema = const {
  'created_at': LocalFieldType.text, // "2025-01-26" - string comparison issues
};
```

### 3. Keep Models Immutable

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

### 4. Handle Conflicts Properly

```dart
static Todo resolveConflict(Todo local, Todo remote) {
  // Last-write-wins based on timestamp
  return local.updatedAt.isAfter(remote.updatedAt) ? local : remote;

  // Or merge specific fields
  // return Todo(
  //   id: local.id,
  //   title: remote.title,          // Take remote title
  //   completed: local.completed,    // Keep local status
  //   updatedAt: remote.updatedAt,   // Use latest timestamp
  // );
}
```

### 5. Use Pagination for Large Lists

```dart
// Load first page
final page1 = await todoRepository.query(limit: 20, offset: 0);

// Load more on scroll
final page2 = await todoRepository.query(limit: 20, offset: 20);

// Or implement infinite scroll
Future<List<Todo>> loadMoreTodos(int currentCount) {
  return todoRepository.query(limit: 20, offset: currentCount);
}
```

### 6. Store Metadata for Sync State

```dart
// Save last sync sequence
await client.setConfigValue('__last_seq__$repositoryName', sequence);

// Load on next sync
final lastSeq = await client.getConfigValue<int>('__last_seq__$repositoryName');
```

## Troubleshooting

### Slow Queries

**Symptoms:** Queries taking a long time with large datasets

**Solutions:**
1. Ensure queried fields are in schema:
   ```dart
   // Add fields you filter/sort by to schema
   schema: const {
     'completed': LocalFieldType.bool, // Now indexed!
   }
   ```
2. Use pagination to limit results:
   ```dart
   query(limit: 20) // Don't load everything
   ```
3. Check that indexes were created (check SQLite logs)

### Schema Changes Not Applying

**Symptoms:** Added field to schema but queries fail

**Solutions:**
1. Schema changes require database migration or reset
2. For development, delete app data and reinstall
3. For production, implement proper migrations:
   ```dart
   // Future: Migration support will be added
   ```

### Data Not Persisting

**Symptoms:** Data disappears after app restart

**Solutions:**
1. Ensure you await `client.initialize()`:
   ```dart
   await client.initialize(); // Don't forget await!
   ```
2. Check SQLite file location is correct
3. Verify no errors during writes

### Type Mismatch Errors

**Symptoms:** `TypeError` when querying

**Solutions:**
1. Ensure JSON field types match schema types:
   ```dart
   // Schema says int
   'priority': LocalFieldType.int,

   // JSON must have int, not string
   toJson() => {'priority': 5, not: '5'}
   ```
2. Handle null values properly:
   ```dart
   toJson() => {
     'priority': priority ?? 0, // Provide default
   }
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
- SQLite storage with schemas
- Rich query capabilities
- Multi-repository support
- Namespace isolation
- Reactive UI updates

To run the example:

```bash
cd local_first_sqlite_storage/example
flutter pub get
flutter run
```

## Contributing

Contributions are welcome! Please open an issue to discuss ideas or bugs. See the main [local_first](https://pub.dev/packages/local_first) repository for contribution guidelines.

## License

This project is available under the MIT License. See `LICENSE` for details.
