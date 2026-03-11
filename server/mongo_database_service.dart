import 'dart:developer' as dev;
import 'package:mongo_dart/mongo_dart.dart';

import 'database_service.dart';

// IMPORTANT: SelectorBuilder is mutable and accumulates state between calls.
// Using a getter ensures each query starts with a clean slate.
SelectorBuilder get _where => SelectorBuilder();

/// Production [DatabaseService] backed by MongoDB via `mongo_dart`.
class MongoDatabaseService implements DatabaseService {
  static const _logTag = 'MongoDatabaseService';

  final String connectionString;
  Db? _db;

  MongoDatabaseService({required this.connectionString});

  @override
  bool get isConnected => _db?.isConnected ?? false;

  @override
  Future<void> open() async {
    final db = await Db.create(connectionString);
    _db = db;
    await db.open();
    dev.log('Connected to MongoDB at $connectionString', name: _logTag);
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Db get _dbOrThrow {
    final db = _db;
    if (db == null) throw StateError('MongoDB not connected');
    return db;
  }

  @override
  Future<void> ensureIndexes(List<String> repositories) async {
    final db = _dbOrThrow;

    for (final repoName in repositories) {
      final collection = db.collection(repoName);
      try {
        await collection.createIndex(keys: {'serverSequence': 1});
        await collection.createIndex(keys: {'_event_id': 1}, unique: true);
        await collection.createIndex(keys: {'_data_id': 1});
      } catch (e) {
        dev.log('Failed to create indexes for $repoName: $e', name: _logTag);
      }
    }

    try {
      final countersCollection = db.collection('_sequence_counters');
      await countersCollection.createIndex(
        keys: {'repository': 1},
        unique: true,
      );
    } catch (e) {
      dev.log(
        'Failed to create sequence counters collection: $e',
        name: _logTag,
      );
    }
  }

  @override
  Future<List<String>> getCollectionNames() async {
    final db = _dbOrThrow;
    final names = await db.getCollectionNames();
    return names.whereType<String>().toList();
  }

  @override
  Future<int> collectionCount(String collection) async {
    final db = _dbOrThrow;
    return db.collection(collection).count();
  }

  @override
  Future<Map<String, dynamic>?> findOne(
    String collection, {
    String? eqField,
    dynamic eqValue,
    String? sortByField,
    bool sortDescending = false,
    int? limit,
  }) async {
    final db = _dbOrThrow;
    final coll = db.collection(collection);

    var selector = _where;
    if (eqField != null) {
      selector = selector.eq(eqField, eqValue);
    }
    if (sortByField != null) {
      selector = selector.sortBy(sortByField, descending: sortDescending);
    }
    if (limit != null) {
      selector = selector.limit(limit);
    }

    final doc = await coll.findOne(selector);
    if (doc == null) return null;

    // Remove MongoDB internal _id
    final result = Map<String, dynamic>.from(doc)..remove('_id');
    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> find(
    String collection, {
    String? eqField,
    dynamic eqValue,
    String? gtField,
    dynamic gtValue,
    String? sortByField,
    bool sortDescending = false,
    int? limit,
  }) async {
    final db = _dbOrThrow;
    final coll = db.collection(collection);

    var selector = _where;
    if (eqField != null) {
      selector = selector.eq(eqField, eqValue);
    }
    if (gtField != null) {
      selector = selector.gt(gtField, gtValue);
    }
    if (sortByField != null) {
      selector = selector.sortBy(sortByField, descending: sortDescending);
    }
    if (limit != null && limit > 0) {
      selector = selector.limit(limit);
    }

    final cursor = coll.find(selector);
    final results = <Map<String, dynamic>>[];

    await cursor.forEach((doc) {
      final map = Map<String, dynamic>.from(doc)..remove('_id');
      results.add(map);
    });

    return results;
  }

  @override
  Future<void> insertOne(String collection, Map<String, dynamic> doc) async {
    final db = _dbOrThrow;
    await db.collection(collection).insertOne(doc);
  }

  @override
  Future<int> getNextSequence(String repositoryName) async {
    final db = _dbOrThrow;
    final countersCollection = db.collection('_sequence_counters');

    await countersCollection.updateOne(
      _where.eq('repository', repositoryName),
      {
        r'$inc': {'sequence': 1},
        r'$setOnInsert': {'repository': repositoryName},
      },
      upsert: true,
    );

    final doc = await countersCollection.findOne(
      _where.eq('repository', repositoryName),
    );

    return doc?['sequence'] as int? ?? 1;
  }
}
