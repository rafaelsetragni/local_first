part of '../../local_first.dart';

/// Simple in-memory implementation of [ConfigKeyValueStorage].
///
/// Accepts the same set of types supported by `shared_preferences` and is
/// intended for tests or lightweight scenarios where persistence is not needed.
class InMemoryConfigKeyValueStorage implements ConfigKeyValueStorage {
  bool _initialized = false;
  final Map<String, Object> _metadata = {};

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'InMemoryConfigKeyValueStorage not initialized. Call initialize() first.',
      );
    }
  }

  bool _isSupportedConfigValue(Object value) {
    if (value is bool || value is int || value is double || value is String) {
      return true;
    }
    if (value is List<String>) return true;
    if (value is List && value.every((e) => e is String)) return true;
    return false;
  }

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<void> close() async {
    _metadata.clear();
    _initialized = false;
  }

  @override
  Future<bool> containsConfigKey(String key) async {
    _ensureInitialized();
    return _metadata.containsKey(key);
  }

  @override
  Future<bool> setConfigValue<T>(String key, T value) async {
    _ensureInitialized();
    if (value is! Object || !_isSupportedConfigValue(value)) {
      throw ArgumentError(
        'Unsupported config value type ${value.runtimeType}. '
        'Allowed: bool, int, double, String, List<String>.',
      );
    }
    _metadata[key] = value is List ? List<String>.from(value) : value;
    return true;
  }

  @override
  Future<T?> getConfigValue<T>(String key) async {
    _ensureInitialized();
    final value = _metadata[key];
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
    _ensureInitialized();
    _metadata.remove(key);
    return true;
  }

  @override
  Future<bool> clearConfig() async {
    _ensureInitialized();
    _metadata.clear();
    return true;
  }

  @override
  Future<Set<String>> getConfigKeys() async {
    _ensureInitialized();
    return _metadata.keys.toSet();
  }
}
