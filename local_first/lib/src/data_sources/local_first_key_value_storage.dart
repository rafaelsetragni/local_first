part of '../../local_first.dart';

/// Basic key/value storage used for lightweight metadata (e.g., server sequence).
///
/// Implementations can back this with SharedPreferences, in-memory maps,
/// or any other simple KV store. Values must be limited to primitive types
/// (`String`, `int`, `double`, `bool`) or JSON-friendly collections
/// (`Map<String, dynamic>` / `List<dynamic>` containing the same primitives).
abstract class LocalFirstKeyValueStorage {
  /// Opens the underlying storage if needed.
  ///
  /// Implementations may use [namespace] to isolate keys across contexts.
  Future<void> open({String namespace = 'default'});

  /// Whether the storage is currently open.
  bool get isOpen;

  /// Persists a value by key.
  ///
  /// Implementations should reject unsupported types.
  Future<void> set<T>(String key, T value);

  /// Reads a value by key, or null if not set.
  ///
  /// Returns the stored value cast to [T] when possible.
  Future<T?> get<T>(String key);

  /// Deletes a value by key.
  Future<void> delete(String key);

  /// Closes/disposes the storage.
  Future<void> close();
}
