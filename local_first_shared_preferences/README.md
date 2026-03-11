# local_first_shared_preferences

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](#)
[![Discord](https://img.shields.io/discord/888523488376279050.svg?style=for-the-badge&colorA=7289da&label=Chat%20on%20Discord)](https://discord.awesome-notifications.carda.me)

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=103)](#)
[![pub package](https://img.shields.io/pub/v/local_first_shared_preferences.svg)](https://pub.dev/packages/local_first_shared_preferences)
![Full tests workflow](https://github.com/rafaelsetragni/local_first/actions/workflows/dart.yml/badge.svg?branch=main)
[![codecov](https://codecov.io/github/rafaelsetragni/local_first/graph/badge.svg?token=7BRG8JcWTQ)](https://codecov.io/github/rafaelsetragni/local_first)

<br>

A lightweight configuration storage adapter for the [local_first](https://pub.dev/packages/local_first) ecosystem. Built on Flutter's SharedPreferences for storing app settings, feature flags, and metadata with namespace support.

> **Note:** This package provides **config storage only** (implements `ConfigKeyValueStorage`). For event/data storage, use [local_first_hive_storage](https://pub.dev/packages/local_first_hive_storage) or [local_first_sqlite_storage](https://pub.dev/packages/local_first_sqlite_storage).

## Why local_first_shared_preferences?

- **Platform Native**: Uses platform-specific preferences stores (NSUserDefaults on iOS, SharedPreferences on Android)
- **Lightweight**: Perfect for storing small configuration values and app settings
- **Simple API**: Key-value storage with type safety
- **Namespace Support**: Isolate settings per user or tenant
- **Zero Dependencies**: Only requires Flutter's built-in `shared_preferences` plugin
- **Instant Access**: No async initialization required for reads after first load

## Features

- ✅ **Config Storage**: Store app settings, feature flags, and metadata
- ✅ **Type Safe**: Generic get/set methods with type checking
- ✅ **Namespace Support**: Prefix keys per user/tenant automatically
- ✅ **Platform Native**: Uses native preference stores on each platform
- ✅ **Simple API**: Easy to use key-value interface
- ✅ **Null Safety**: Full null safety support

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  local_first: ^0.6.0
  local_first_shared_preferences: ^0.2.0
```

Then install it with:

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:local_first_shared_preferences/local_first_shared_preferences.dart';

// 1) Create storage instance
final storage = SharedPreferencesConfigStorage(
  namespace: 'user_alice', // Optional: isolate data per user
);

// 2) Initialize
await storage.initialize();

// 3) Store values
await storage.setConfigValue('theme', 'dark');
await storage.setConfigValue('notifications_enabled', true);
await storage.setConfigValue('sync_interval', 30);

// 4) Retrieve values
final theme = await storage.getConfigValue<String>('theme');
final notificationsEnabled = await storage.getConfigValue<bool>('notifications_enabled');
final syncInterval = await storage.getConfigValue<int>('sync_interval');

print('Theme: $theme'); // dark
print('Notifications: $notificationsEnabled'); // true
print('Sync interval: $syncInterval seconds'); // 30
```

## Integration with LocalFirst

Use SharedPreferences for config storage alongside event storage:

```dart
import 'package:local_first/local_first.dart';
import 'package:local_first_hive_storage/local_first_hive_storage.dart';
import 'package:local_first_shared_preferences/local_first_shared_preferences.dart';

Future<void> main() async {
  // SharedPreferences for config (settings, sync state)
  final configStorage = SharedPreferencesConfigStorage();
  await configStorage.initialize();

  // Hive for event storage (actual data)
  final client = LocalFirstClient(
    repositories: [todoRepository, userRepository],
    localStorage: HiveLocalFirstStorage(),
    configStorage: configStorage, // Use SharedPreferences for config
    syncStrategies: [
      // Strategies can use configStorage for sync state
    ],
  );

  await client.initialize();

  // Store sync state
  await client.setConfigValue('last_sync_seq', 42);

  // Store app preferences
  await client.setConfigValue('dark_mode', true);

  // Retrieve values
  final lastSeq = await client.getConfigValue<int>('last_sync_seq');
  final darkMode = await client.getConfigValue<bool>('dark_mode');
}
```

## Supported Types

SharedPreferences supports these types:

| Type | Example | Use Case |
|------|---------|----------|
| `bool` | `true` | Feature flags, toggle settings |
| `int` | `42` | Counters, sync sequences, numeric settings |
| `double` | `3.14` | Ratings, decimal settings |
| `String` | `'hello'` | User names, tokens, text settings |
| `List<String>` | `['a', 'b']` | Tags, categories, string lists |

### Example: Storing Different Types

```dart
final storage = SharedPreferencesConfigStorage();
await storage.initialize();

// Boolean
await storage.setConfigValue('dark_mode', true);
await storage.setConfigValue('notifications_enabled', false);

// Integer
await storage.setConfigValue('sync_interval_seconds', 30);
await storage.setConfigValue('max_retries', 3);

// Double
await storage.setConfigValue('font_scale', 1.2);
await storage.setConfigValue('volume_level', 0.75);

// String
await storage.setConfigValue('theme', 'dark');
await storage.setConfigValue('language', 'en_US');
await storage.setConfigValue('auth_token', 'eyJhbGciOi...');

// List<String>
await storage.setConfigValue('enabled_features', ['chat', 'notifications', 'analytics']);
await storage.setConfigValue('favorite_categories', ['work', 'personal']);

// Retrieve with type safety
final darkMode = await storage.getConfigValue<bool>('dark_mode');
final syncInterval = await storage.getConfigValue<int>('sync_interval_seconds');
final fontScale = await storage.getConfigValue<double>('font_scale');
final theme = await storage.getConfigValue<String>('theme');
final features = await storage.getConfigValue<List<String>>('enabled_features');
```

## Namespace Support

Isolate configuration per user or tenant:

```dart
final storage = SharedPreferencesConfigStorage();
await storage.initialize();

// Switch to Alice's namespace
await storage.useNamespace('user_alice');
await storage.setConfigValue('theme', 'dark');
await storage.setConfigValue('notifications', true);

// Switch to Bob's namespace
await storage.useNamespace('user_bob');
await storage.setConfigValue('theme', 'light');
await storage.setConfigValue('notifications', false);

// Back to Alice
await storage.useNamespace('user_alice');
final aliceTheme = await storage.getConfigValue<String>('theme'); // 'dark'

// Back to Bob
await storage.useNamespace('user_bob');
final bobTheme = await storage.getConfigValue<String>('theme'); // 'light'
```

### How Namespaces Work

Namespaces automatically prefix keys:

```dart
// Without namespace
await storage.setConfigValue('theme', 'dark');
// Stored as: "theme" = "dark"

// With namespace "user_alice"
await storage.useNamespace('user_alice');
await storage.setConfigValue('theme', 'dark');
// Stored as: "user_alice__theme" = "dark"

// With namespace "user_bob"
await storage.useNamespace('user_bob');
await storage.setConfigValue('theme', 'light');
// Stored as: "user_bob__theme" = "light"
```

**Use cases:**
- 👤 Multi-user apps (different settings per user)
- 🏢 Multi-tenant apps (isolate tenant config)
- 📱 Multiple account support
- 🔐 Testing (isolate test data from production)

## Common Use Cases

### 1. Feature Flags

```dart
// Store feature flags
await storage.setConfigValue('feature_chat_enabled', true);
await storage.setConfigValue('feature_analytics_enabled', false);
await storage.setConfigValue('feature_dark_mode_enabled', true);

// Check if feature is enabled
final chatEnabled = await storage.getConfigValue<bool>('feature_chat_enabled');
if (chatEnabled == true) {
  // Show chat UI
}
```

### 2. User Preferences

```dart
// Theme preference
await storage.setConfigValue('theme_mode', 'dark'); // 'light', 'dark', 'system'

// Notification settings
await storage.setConfigValue('notifications_enabled', true);
await storage.setConfigValue('notification_sound', 'chime');

// Accessibility
await storage.setConfigValue('font_size', 'large'); // 'small', 'medium', 'large'
await storage.setConfigValue('reduce_animations', false);

// Language
await storage.setConfigValue('locale', 'en_US');
```

### 3. Sync State Management

```dart
// Store last sync sequence per repository
await storage.setConfigValue('__last_seq__todos', 42);
await storage.setConfigValue('__last_seq__users', 15);

// Store last sync timestamp
await storage.setConfigValue('last_sync_time', DateTime.now().toIso8601String());

// Retrieve for next sync
final lastTodoSeq = await storage.getConfigValue<int>('__last_seq__todos');
if (lastTodoSeq != null) {
  // Sync only events after sequence 42
}
```

### 4. App State Persistence

```dart
// Remember user selections
await storage.setConfigValue('selected_workspace_id', 'workspace_123');
await storage.setConfigValue('last_viewed_project', 'project_456');

// Onboarding state
await storage.setConfigValue('onboarding_completed', true);
await storage.setConfigValue('tutorial_step', 3);

// Cache control
await storage.setConfigValue('cache_version', 2);
```

### 5. Authentication State

```dart
// Store auth tokens (consider secure storage for production)
await storage.setConfigValue('auth_token', 'eyJhbGc...');
await storage.setConfigValue('refresh_token', 'dGhlIHN...');
await storage.setConfigValue('token_expires_at', '2026-02-01T10:00:00Z');

// User info
await storage.setConfigValue('logged_in_user_id', 'user_123');
await storage.setConfigValue('user_email', 'alice@example.com');
```

## Best Practices

### 1. Use Type-Safe Retrieval

```dart
// Good: Specify type and handle null
final theme = await storage.getConfigValue<String>('theme') ?? 'light';

// Also good: Check for null explicitly
final syncInterval = await storage.getConfigValue<int>('sync_interval');
if (syncInterval != null) {
  // Use syncInterval
} else {
  // Use default
  const defaultInterval = 30;
}
```

### 2. Use Consistent Key Naming

```dart
// Good: Consistent naming convention
await storage.setConfigValue('feature_chat_enabled', true);
await storage.setConfigValue('feature_analytics_enabled', false);
await storage.setConfigValue('user_theme_preference', 'dark');
await storage.setConfigValue('user_language', 'en_US');

// Less clear: Inconsistent naming
await storage.setConfigValue('ChatFeature', true); // Mixed case
await storage.setConfigValue('enable-analytics', false); // Dashes vs underscores
await storage.setConfigValue('THEME', 'dark'); // All caps
```

### 3. Store Small Values Only

SharedPreferences is designed for small values:

```dart
// Good: Small config values
await storage.setConfigValue('theme', 'dark');
await storage.setConfigValue('user_id', 'user_123');
await storage.setConfigValue('sync_interval', 30);

// Bad: Large data (use Hive/SQLite instead)
await storage.setConfigValue('cached_todos', jsonEncode(allTodos)); // ❌
await storage.setConfigValue('large_image_data', base64Image); // ❌
```

**Rule of thumb:** Use SharedPreferences for config (<100 KB). Use Hive/SQLite for data.

### 4. Use Namespaces for Multi-User Apps

```dart
class AuthService {
  final SharedPreferencesConfigStorage storage;

  Future<void> login(String userId) async {
    await storage.useNamespace('user_$userId');
    // Now all config is isolated to this user
  }

  Future<void> logout() async {
    await storage.useNamespace(null); // Clear namespace
  }
}
```

### 5. Provide Defaults for Missing Values

```dart
Future<String> getTheme() async {
  return await storage.getConfigValue<String>('theme') ?? 'light';
}

Future<int> getSyncInterval() async {
  return await storage.getConfigValue<int>('sync_interval') ?? 30;
}

Future<bool> areNotificationsEnabled() async {
  return await storage.getConfigValue<bool>('notifications_enabled') ?? true;
}
```

## Comparison with Hive/SQLite

| Feature | SharedPreferences | Hive | SQLite |
|---------|------------------|------|--------|
| **Purpose** | Config/settings | Data storage | Data storage |
| **Data Size** | Small (<100 KB) | Medium-Large | Large |
| **Performance** | Very fast (cached) | Very fast | Fast |
| **Query Support** | Key-value only | Basic filtering | Rich SQL queries |
| **Storage Type** | Platform native | File-based | Database |
| **Best For** | Settings, flags | Events, documents | Structured data |
| **Namespace Support** | Yes (manual prefix) | Yes (built-in) | Yes (built-in) |

**Use SharedPreferences for:**
- ✅ User preferences (theme, language, font size)
- ✅ Feature flags (boolean toggles)
- ✅ Small config values (API endpoints, timeout values)
- ✅ Sync metadata (last sequence, last sync time)
- ✅ Authentication state (user ID, simple tokens)

**Use Hive/SQLite for:**
- ✅ Application data (todos, notes, messages)
- ✅ Event sourcing (LocalFirst events)
- ✅ Large datasets
- ✅ Data requiring queries/filtering

## Troubleshooting

### Values Not Persisting

**Symptoms:** Config values don't persist after app restart

**Solutions:**
1. Ensure you await `initialize()`:
   ```dart
   await storage.initialize(); // Don't forget await!
   ```
2. Ensure you await `setConfigValue()`:
   ```dart
   await storage.setConfigValue('theme', 'dark'); // Don't forget await!
   ```
3. Check platform permissions (iOS: `NSUserDefaults`, Android: `SharedPreferences`)

### Namespace Issues

**Symptoms:** Values from different namespaces mixing

**Solutions:**
1. Always call `useNamespace()` before operations:
   ```dart
   await storage.useNamespace('user_$userId');
   final theme = await storage.getConfigValue<String>('theme');
   ```
2. Verify namespace is set correctly:
   ```dart
   print('Current namespace: ${storage.currentNamespace}');
   ```

### Type Mismatch Errors

**Symptoms:** Getting null or wrong type

**Solutions:**
1. Ensure you use the correct type:
   ```dart
   // Stored as int
   await storage.setConfigValue('count', 42);

   // Retrieve as int, not String
   final count = await storage.getConfigValue<int>('count'); // ✅
   final wrongType = await storage.getConfigValue<String>('count'); // ❌ null
   ```

### Platform-Specific Issues

**iOS:**
- NSUserDefaults has a limit (~4 MB typically)
- Values are stored in `~/Library/Preferences/[bundle-id].plist`

**Android:**
- SharedPreferences stores XML files
- Located in `/data/data/[package]/shared_prefs/`

**Web:**
- Uses localStorage (limited to ~5-10 MB depending on browser)
- Cleared when user clears browser data

**Solution:** Keep values small and use Hive/SQLite for larger data.

## Testing

### Unit Tests

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_first_shared_preferences/local_first_shared_preferences.dart';

void main() {
  late SharedPreferencesConfigStorage storage;

  setUp(() async {
    storage = SharedPreferencesConfigStorage();
    await storage.initialize();
  });

  test('should store and retrieve string value', () async {
    await storage.setConfigValue('key', 'value');
    final result = await storage.getConfigValue<String>('key');
    expect(result, equals('value'));
  });

  test('should return null for non-existent key', () async {
    final result = await storage.getConfigValue<String>('non_existent');
    expect(result, isNull);
  });

  test('should isolate values by namespace', () async {
    await storage.useNamespace('ns1');
    await storage.setConfigValue('key', 'value1');

    await storage.useNamespace('ns2');
    await storage.setConfigValue('key', 'value2');

    await storage.useNamespace('ns1');
    final result1 = await storage.getConfigValue<String>('key');
    expect(result1, equals('value1'));

    await storage.useNamespace('ns2');
    final result2 = await storage.getConfigValue<String>('key');
    expect(result2, equals('value2'));
  });
}
```

## Example App

This package includes a complete example demonstrating:
- SharedPreferences for config storage
- Hive for event storage
- Namespace isolation
- Multi-user support

To run the example:

```bash
cd local_first_shared_preferences/example
flutter pub get
flutter run
```

## Platform Support

| Platform | Support | Storage Location |
|----------|---------|------------------|
| **Android** | ✅ | SharedPreferences XML |
| **iOS** | ✅ | NSUserDefaults plist |
| **macOS** | ✅ | NSUserDefaults plist |
| **Linux** | ✅ | JSON file in XDG directory |
| **Windows** | ✅ | Registry or JSON file |
| **Web** | ✅ | localStorage |

## Contributing

Contributions are welcome! Please open an issue to discuss ideas or bugs. See the main [local_first](https://pub.dev/packages/local_first) repository for contribution guidelines.

## License

This project is available under the MIT License. See `LICENSE` for details.
