import 'package:flutter/widgets.dart';
import 'package:local_first/local_first.dart';
import 'package:shared_preferences/shared_preferences.dart';

  /// Simple config storage backed by `shared_preferences`, with all keys
  /// automatically prefixed by a namespace so different users/sessions stay
  /// isolated.
class SharedPreferencesConfigStorage implements ConfigKeyValueStorage {
  SharedPreferencesConfigStorage({String namespace = 'default'})
    : _namespace = namespace.isEmpty ? 'default' : namespace;

  SharedPreferences? _prefs;
  bool _initialized = false;
  String _namespace;

  /// Current namespace prefix applied to all keys.
  String get namespace => _namespace;

  SharedPreferences _prefsOrThrow() {
    final prefs = _prefs;
    if (!_initialized || prefs == null) {
      throw StateError(
        'SharedPreferencesConfigStorage not initialized. Call initialize() first.',
      );
    }
    return prefs;
  }

  String _key(String key) => '$_namespace::$key';

  /// Prepares the `SharedPreferences` instance so reads and writes can happen.
  @override
  Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  /// Resets the adapter and drops the cached prefs instance.
  @override
  Future<void> close() async {
    _prefs = null;
    _initialized = false;
  }

  /// Switches the namespace prefix used for every key/value pair.
  ///
  /// - [namespace]: Logical bucket name (for example, a user id). Empty strings
  ///   fall back to `default` so callers never create a blank prefix.
  ///
  /// Throws [StateError] if the storage has not been initialized.
  @override
  Future<void> useNamespace(String namespace) async {
    if (_namespace == namespace) return;
    _namespace = namespace.isEmpty ? 'default' : namespace;
  }

  /// Checks if a namespaced config key already exists.
  ///
  /// - [key]: Raw key without namespace; the method handles prefixing.
  ///
  /// Throws [StateError] if the storage has not been initialized.
  @override
  Future<bool> containsConfigKey(String key) async {
    final prefs = _prefsOrThrow();
    return prefs.containsKey(_key(key));
  }

  /// Saves a config value under the current namespace.
  ///
  /// - [key]: Raw key without namespace; the method handles prefixing.
  /// - [value]: Allowed types: bool, int, double, String or List<String>. Any
  ///   other type triggers an [ArgumentError].
  ///
  /// Throws [StateError] if the storage has not been initialized.
  @override
  Future<bool> setConfigValue<T>(String key, T value) async {
    final prefs = _prefsOrThrow();
    if (value is! Object) {
      throw ArgumentError('Config value cannot be null.');
    }
    final namespacedKey = _key(key);
    if (value is bool) return prefs.setBool(namespacedKey, value);
    if (value is int) return prefs.setInt(namespacedKey, value);
    if (value is double) return prefs.setDouble(namespacedKey, value);
    if (value is String) return prefs.setString(namespacedKey, value);
    if (value is List<String>) {
      return prefs.setStringList(namespacedKey, List<String>.from(value));
    }
    if (value is List && value.every((e) => e is String)) {
      return prefs.setStringList(
        namespacedKey,
        List<String>.from(value.map((e) => e as String)),
      );
    }
    throw ArgumentError(
      'Unsupported config value type ${value.runtimeType}. '
      'Allowed: bool, int, double, String, List<String>.',
    );
  }

  /// Reads a config value for the given key.
  ///
  /// - [key]: Raw key without namespace; the method handles prefixing.
  ///
  /// Throws [StateError] if the storage has not been initialized.
  @override
  Future<T?> getConfigValue<T>(String key) async {
    final prefs = _prefsOrThrow();
    final value = prefs.get(_key(key));
    if (value == null) return null;
    if (T == dynamic) return value as T;
    if (value is List<String>) {
      if (value is T) return value as T;
      return null;
    }
    if (value is T) return value as T;
    return null;
  }

  /// Deletes a single config entry from the current namespace.
  ///
  /// - [key]: Raw key without namespace; the method handles prefixing.
  ///
  /// Throws [StateError] if the storage has not been initialized.
  @override
  Future<bool> removeConfig(String key) async {
    final prefs = _prefsOrThrow();
    return prefs.remove(_key(key));
  }

  /// Wipes every config entry stored in the current namespace.
  ///
  /// Throws [StateError] if the storage has not been initialized.
  @override
  Future<bool> clearConfig() async {
    final prefs = _prefsOrThrow();
    final keys = prefs.getKeys().where((k) => k.startsWith('$_namespace::'));
    for (final key in keys) {
      await prefs.remove(key);
    }
    return true;
  }

  /// Lists all config keys for the active namespace.
  ///
  /// Throws [StateError] if the storage has not been initialized.
  @override
  Future<Set<String>> getConfigKeys() async {
    final prefs = _prefsOrThrow();
    final prefix = '$_namespace::';
    return prefs
        .getKeys()
        .where((k) => k.startsWith(prefix))
        .map((k) => k.substring(prefix.length))
        .toSet();
  }
}
