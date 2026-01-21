import 'package:flutter/widgets.dart';
import 'package:local_first/local_first.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Config storage backed by `shared_preferences`, namespaced via key prefixing.
class SharedPreferencesConfigStorage implements ConfigKeyValueStorage {
  SharedPreferencesConfigStorage({String namespace = 'default'})
      : _namespace = namespace.isEmpty ? 'default' : namespace;

  SharedPreferences? _prefs;
  bool _initialized = false;
  String _namespace;

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

  String _key(String key) => '${_namespace}::$key';

  @override
  Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  @override
  Future<void> close() async {
    _prefs = null;
    _initialized = false;
  }

  @override
  Future<void> useNamespace(String namespace) async {
    if (_namespace == namespace) return;
    _namespace = namespace.isEmpty ? 'default' : namespace;
  }

  @override
  Future<bool> containsConfigKey(String key) async {
    final prefs = _prefsOrThrow();
    return prefs.containsKey(_key(key));
  }

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

  @override
  Future<bool> removeConfig(String key) async {
    final prefs = _prefsOrThrow();
    return prefs.remove(_key(key));
  }

  @override
  Future<bool> clearConfig() async {
    final prefs = _prefsOrThrow();
    final keys = prefs.getKeys().where((k) => k.startsWith('$_namespace::'));
    for (final key in keys) {
      await prefs.remove(key);
    }
    return true;
  }

  @override
  Future<Set<String>> getConfigKeys() async {
    final prefs = _prefsOrThrow();
    final prefix = '$_namespace::';
    return prefs.getKeys().where((k) => k.startsWith(prefix)).map(
          (k) => k.substring(prefix.length),
        ).toSet();
  }
}
