part of '../../local_first.dart';

/// Contract for key/value storage used for lightweight metadata.
abstract class LocalFirstKeyValueStorage {
  /// Opens the key/value storage.
  Future<void> open({String namespace = 'default'});

  /// Closes the key/value storage.
  Future<void> close();

  /// True when the storage connection is open.
  bool get isOpened;

  /// True when the storage connection is closed.
  bool get isClosed;

  /// The active namespace used by the storage.
  String get currentNamespace;

  /// Stores a value by key.
  Future<void> set<T>(String key, T value);

  /// Reads a value by key.
  Future<T?> get<T>(String key);

  /// Checks if a key exists.
  Future<bool> contains(String key);

  /// Removes a single key.
  Future<void> delete(String key);
}
