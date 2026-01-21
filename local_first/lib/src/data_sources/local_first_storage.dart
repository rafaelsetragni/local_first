part of '../../local_first.dart';

/// Abstract interface for local database operations.
///
/// Implement this interface to support different local storage backends
/// (Hive, Isar, Drift, etc.). Storage adapters live in their own packages
/// (e.g., `local_first_hive_storage`, `local_first_sqlite_storage`).
///
/// Example:
/// ```dart
/// class IsarLocalFirstDelegate implements LocalFirstStorage {
///   @override
///   Future<void> initialize() async {
///     // Initialize Isar database
///   }
///
///   // Implement other methods...
/// }
/// ```
abstract class LocalFirstStorage implements ConfigKeyValueStorage {
  /// Initializes the local database.
  ///
  /// Called once during [LocalFirstClient.initialize].
  @override
  Future<void> initialize();

  /// Closes the database connection.
  ///
  /// Called when disposing the LocalFirstClient instance.
  @override
  Future<void> close();

  /// Clears all data from the database.
  ///
  /// Use with caution as this operation cannot be undone.
  Future<void> clearAllData();

  /// Gets all items from the state table/collection.
  Future<List<JsonMap>> getAll(String tableName);

  /// Gets all items from the event log table/collection.
  Future<List<JsonMap>> getAllEvents(String tableName);

  /// Gets a single item by its ID.
  ///
  /// Returns null if the item doesn't exist.
  Future<JsonMap?> getById(String tableName, String id);

  /// Checks if a single item exists by its ID.
  ///
  /// Returns null if the item doesn't exist.
  Future<bool> containsId(String tableName, String id);

  /// Gets a single event by its event id.
  Future<JsonMap?> getEventById(String tableName, String id);

  /// Inserts a new item into the state table/collection.
  Future<void> insert(String tableName, JsonMap item, String idField);

  /// Inserts a new event into the event log table/co'llection.
  Future<void> insertEvent(String tableName, JsonMap item, String idField);

  /// Updates an existing item in the state table/collection.
  Future<void> update(String tableName, String id, JsonMap item);

  /// Updates an existing event in the event log.
  Future<void> updateEvent(String tableName, String id, JsonMap item);

  /// Deletes an item by its ID in the state table.
  Future<void> delete(String repositoryName, String id);

  /// Deletes an event by its ID in the event table.
  Future<void> deleteEvent(String repositoryName, String id);

  /// Deletes all items from the state table/collection.
  Future<void> deleteAll(String tableName);

  /// Deletes all items from the event table/collection.
  Future<void> deleteAllEvents(String tableName);

  /// Stores arbitrary key/value metadata for config purposes.
  @override
  Future<bool> setConfigValue<T>(String key, T value);

  /// Reads arbitrary key/value metadata for config purposes.
  @override
  Future<T?> getConfigValue<T>(String key);

  /// Returns whether a config key exists.
  @override
  Future<bool> containsConfigKey(String key);

  /// Removes a config entry.
  @override
  Future<bool> removeConfig(String key);

  /// Clears all config entries.
  @override
  Future<bool> clearConfig();

  /// Lists all config keys.
  @override
  Future<Set<String>> getConfigKeys();

  /// Ensures the storage backend has an up-to-date schema for a repository.
  ///
  /// Backends that do not use schemas can ignore this call.
  Future<void> ensureSchema(
    String tableName,
    JsonMap<LocalFieldType> schema, {
    required String idFieldName,
  });

  /// Executes a query and returns results from the state table.
  Future<List<LocalFirstEvent<T>>> query<T>(LocalFirstQuery<T> query);

  /// Returns a reactive stream of query results.
  ///
  /// Delegates that support native streams (like Isar) can override this.
  Stream<List<LocalFirstEvent<T>>> watchQuery<T>(LocalFirstQuery<T> query);
}
