# local_first_shared_preferences

SharedPreferences-backed config storage for the `local_first` ecosystem. It implements `ConfigKeyValueStorage` using the platform `shared_preferences` plugin and respects namespaces by prefixing keys.

## Usage

```dart
final storage = SharedPreferencesConfigStorage(namespace: 'user_alice');
await storage.initialize();

await storage.setConfigValue('theme', 'dark');
final theme = await storage.getConfigValue<String>('theme');
```

Switching namespaces simply changes the key prefix:

```dart
await storage.useNamespace('user_bob');
```
