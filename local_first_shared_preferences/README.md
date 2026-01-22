# local_first_shared_preferences

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](#)
[![Discord](https://img.shields.io/discord/888523488376279050.svg?style=for-the-badge&colorA=7289da&label=Chat%20on%20Discord)](https://discord.awesome-notifications.carda.me)

[![Open Source Love](https://badges.frapsoft.com/os/v1/open-source.svg?v=103)](#)
[![pub package](https://img.shields.io/pub/v/local_first_shared_preferences.svg)](https://pub.dev/packages/local_first_shared_preferences)
![Full tests workflow](https://github.com/rafaelsetragni/local_first/actions/workflows/dart.yml/badge.svg?branch=main)
[![codecov](https://codecov.io/github/rafaelsetragni/local_first/graph/badge.svg?token=7BRG8JcWTQ)](https://codecov.io/github/rafaelsetragni/local_first)

SharedPreferences-backed config storage for the `local_first` ecosystem. It implements `ConfigKeyValueStorage` using the platform `shared_preferences` plugin and respects namespaces by prefixing keys.

| Supported type      | Example                   |
| ------------------- | ------------------------- |
| `bool`              | `true`                    |
| `int`               | `42`                      |
| `double`            | `3.14`                    |
| `String`            | `'hello'`                 |
| `List<String>`      | `['a', 'b']`              |

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

## Example app

This package ships the same demo app as the other `local_first` storage adapters. To run it:

```bash
cd local_first_shared_preferences/example
flutter run
```

The app uses `SharedPreferencesConfigStorage` for config metadata, while the rest of the data stack mirrors the main examples.

## Contributing

Please read the contribution guidelines in the root project before opening issues or PRs: see `../CONTRIBUTING.md`.
