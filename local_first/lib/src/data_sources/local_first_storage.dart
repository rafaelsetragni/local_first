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
abstract class LocalFirstStorage {
  /// Initializes the local database.
  ///
  /// Called once during [LocalFirstClient.initialize].
  Future<void> initialize();

  /// Closes the database connection.
  ///
  /// Called when disposing the LocalFirstClient instance.
  Future<void> close();

  /// Clears all data from the database.
  ///
  /// Use with caution as this operation cannot be undone.
  Future<void> clearAllData();

  /// Gets all items from the state table/collection.
  Future<List<Map<String, dynamic>>> getAll(String tableName);

  /// Gets all items from the event log table/collection.
  Future<List<Map<String, dynamic>>> getAllEvents(String tableName);

  /// Gets a single item by its ID.
  ///
  /// Returns null if the item doesn't exist.
  Future<Map<String, dynamic>?> getById(String tableName, String id);

  /// Gets a single event by its event id.
  Future<Map<String, dynamic>?> getEventById(String tableName, String id);

  /// Inserts a new item into the state table/collection.
  Future<void> insert(
    String tableName,
    Map<String, dynamic> item,
    String idField,
  );

  /// Inserts a new event into the event log table/collection.
  Future<void> insertEvent(
    String tableName,
    Map<String, dynamic> item,
    String idField,
  );

  /// Updates an existing item in the state table/collection.
  Future<void> update(String tableName, String id, Map<String, dynamic> item);

  /// Updates an existing event in the event log.
  Future<void> updateEvent(String tableName, String id, Map<String, dynamic> item);

  /// Deletes an item by its ID in the state table.
  Future<void> delete(String repositoryName, String id);

  /// Deletes an event by its ID in the event table.
  Future<void> deleteEvent(String repositoryName, String id);

  /// Deletes all items from the state table/collection.
  Future<void> deleteAll(String tableName);

  /// Deletes all items from the event table/collection.
  Future<void> deleteAllEvents(String tableName);

  /// Stores arbitrary metadata as string by key.
  Future<void> setMeta(String key, String value);

  /// Reads arbitrary metadata stored by key.
  Future<String?> getMeta(String key);

  /// Ensures the storage backend has an up-to-date schema for a repository.
  ///
  /// Backends that do not use schemas can ignore this call.
  Future<void> ensureSchema(
    String tableName,
    Map<String, LocalFieldType> schema, {
    required String idFieldName,
  }) async {}

  /// Executes a query and returns results from the state table.
  ///
  /// Delegates that support native queries (like Isar, Drift) can
  /// override this for optimization. Simple delegates (like Hive) use
  /// the default implementation which filters efficiently in-memory.
  Future<List<Map<String, dynamic>>> query(LocalFirstQuery query) async {
    // Default implementation: fetch all and filter efficiently in memory
    var items = await getAll(query.repositoryName);

    // Apply filters
    if (query.filters.isNotEmpty) {
      items = items.where((item) {
        for (var filter in query.filters) {
          if (!filter.matches(item)) {
            return false;
          }
        }
        return true;
      }).toList();
    }

    // Apply sorting
    if (query.sorts.isNotEmpty) {
      items.sort((a, b) {
        for (var sort in query.sorts) {
          final aValue = a[sort.field];
          final bValue = b[sort.field];

          int comparison = 0;
          if (aValue is Comparable && bValue is Comparable) {
            comparison = aValue.compareTo(bValue);
          }

          if (comparison != 0) {
            return sort.descending ? -comparison : comparison;
          }
        }
        return 0;
      });
    }

    // Apply offset
    if (query.offset != null && query.offset! > 0) {
      items = items.skip(query.offset!).toList();
    }

    // Apply limit
    if (query.limit != null) {
      items = items.take(query.limit!).toList();
    }

    return items;
  }

  /// Returns a reactive stream of query results.
  ///
  /// Delegates that support native streams (like Isar) can override this.
  /// The default implementation emits the initial query result only.
  /// More sophisticated delegates can provide automatic updates when data changes.
  Stream<List<Map<String, dynamic>>> watchQuery(LocalFirstQuery query) async* {
    // Default implementation: emit initial result
    yield await this.query(query);

    // More sophisticated delegates can have native streams with
    // change notifications. The default implementation only emits
    // the initial value.
  }
}
