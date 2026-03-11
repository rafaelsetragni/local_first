part of '../../local_first.dart';

/// Simple in-memory implementation of [ConfigKeyValueStorage].
///
/// Accepts the same set of types supported by `shared_preferences` and is
/// intended for tests or lightweight scenarios where persistence is not needed.
class InMemoryConfigKeyValueStorage implements ConfigKeyValueStorage {
  bool _initialized = false;
  String _namespace = 'default';
  final Map<String, Map<String, Object>> _namespacedMetadata = {};

  Map<String, Object> get _metadata =>
      _namespacedMetadata.putIfAbsent(_namespace, () => {});

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

  /// Marks this storage as ready for use.
  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  /// Clears all namespaces and returns to the default state.
  @override
  Future<void> close() async {
    _namespacedMetadata.clear();
    _namespace = 'default';
    _initialized = false;
  }

  /// Switches the active namespace without clearing existing data.
  ///
  /// - [namespace]: Logical bucket name (for example, a user id). Data in other
  ///   namespaces is preserved until switched back.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<void> useNamespace(String namespace) async {
    if (_namespace == namespace) return;
    _namespace = namespace;
    if (!_initialized) return;
  }

  /// Checks if the provided key exists in the current namespace.
  ///
  /// - [key]: Raw key without namespace; this storage applies the namespace.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<bool> containsConfigKey(String key) async {
    _ensureInitialized();
    return _metadata.containsKey(key);
  }

  /// Persists a config value in memory for quick access in tests or demos.
  ///
  /// - [key]: Raw key without namespace; this storage applies the namespace.
  /// - [value]: Allowed types: bool, int, double, String or `List<String>`. Any
  ///   other type triggers an [ArgumentError].
  ///
  /// Throws [StateError] if called before [initialize].
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

  /// Reads a config value using the provided generic type.
  ///
  /// - [key]: Raw key without namespace; this storage applies the namespace.
  ///
  /// Throws [StateError] if called before [initialize].
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

  /// Removes a config entry from the current namespace.
  ///
  /// - [key]: Raw key without namespace; this storage applies the namespace.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<bool> removeConfig(String key) async {
    _ensureInitialized();
    _metadata.remove(key);
    return true;
  }

  /// Clears every config entry in the current namespace.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<bool> clearConfig() async {
    _ensureInitialized();
    _metadata.clear();
    return true;
  }

  /// Lists all config keys in the current namespace.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<Set<String>> getConfigKeys() async {
    _ensureInitialized();
    return _metadata.keys.toSet();
  }
}
