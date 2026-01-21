part of '../../local_first.dart';

/// Contract for a config-style key-value storage with SharedPreferences-compatible types.
///
/// Implementations should accept only the types supported by
/// `shared_preferences` (`bool`, `int`, `double`, `String`, `List<String>`),
/// but expose a single generic API for reads and writes.
abstract class ConfigKeyValueStorage {
  /// Initializes the storage backend.
  Future<void> initialize();

  /// Closes the storage backend and releases resources.
  Future<void> close();

  /// Switches the active namespace/database when supported.
  Future<void> useNamespace(String namespace);

  /// Returns whether a given key exists.
  Future<bool> containsConfigKey(String key);

  /// Persists a value using a single, generic entry point.
  ///
  /// Implementations should validate `value` to ensure it matches one of the
  /// supported types (`bool`, `int`, `double`, `String`, `List<String>`).
  Future<bool> setConfigValue<T>(String key, T value);

  /// Reads a value using a single, generic entry point.
  ///
  /// Implementations should attempt to cast to the requested `T` and return
  /// `null` when the key is missing or the value is incompatible.
  Future<T?> getConfigValue<T>(String key);

  /// Removes a single entry.
  Future<bool> removeConfig(String key);

  /// Removes all entries.
  Future<bool> clearConfig();

  /// Returns all stored keys.
  Future<Set<String>> getConfigKeys();
}
