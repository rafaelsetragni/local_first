/// Abstract database service interface for the sync server.
///
/// This abstraction allows the server to work with different database
/// implementations: [MongoDatabaseService] for production and
/// [InMemoryDatabaseService] for testing.
abstract class DatabaseService {
  /// Whether the database connection is active.
  bool get isConnected;

  /// Opens the database connection.
  Future<void> open();

  /// Closes the database connection.
  Future<void> close();

  /// Ensures required indexes exist for the given repositories.
  Future<void> ensureIndexes(List<String> repositories);

  /// Returns the names of all collections in the database.
  Future<List<String>> getCollectionNames();

  /// Returns the number of documents in a collection.
  Future<int> collectionCount(String collection);

  /// Finds a single document matching the given criteria.
  ///
  /// - [eqField]/[eqValue]: equality filter (e.g. `_event_id` == value)
  /// - [sortByField]/[sortDescending]: optional sort before picking the first doc
  /// - [limit]: ignored for findOne (always returns at most 1)
  Future<Map<String, dynamic>?> findOne(
    String collection, {
    String? eqField,
    dynamic eqValue,
    String? sortByField,
    bool sortDescending = false,
    int? limit,
  });

  /// Finds all documents matching the given criteria.
  ///
  /// - [eqField]/[eqValue]: equality filter
  /// - [gtField]/[gtValue]: greater-than filter
  /// - [sortByField]/[sortDescending]: ordering
  /// - [limit]: max number of results
  Future<List<Map<String, dynamic>>> find(
    String collection, {
    String? eqField,
    dynamic eqValue,
    String? gtField,
    dynamic gtValue,
    String? sortByField,
    bool sortDescending = false,
    int? limit,
  });

  /// Inserts a single document into the collection.
  Future<void> insertOne(String collection, Map<String, dynamic> doc);

  /// Atomically increments and returns the next sequence number for a repository.
  Future<int> getNextSequence(String repositoryName);
}
