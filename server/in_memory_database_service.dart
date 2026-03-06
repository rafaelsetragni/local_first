import 'database_service.dart';

/// In-memory [DatabaseService] for testing.
///
/// Stores all data in plain Dart maps/lists. No external dependencies required.
class InMemoryDatabaseService implements DatabaseService {
  final Map<String, List<Map<String, dynamic>>> _collections = {};
  final Map<String, int> _sequenceCounters = {};
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> open() async {
    _connected = true;
  }

  @override
  Future<void> close() async {
    _connected = false;
  }

  @override
  Future<void> ensureIndexes(List<String> repositories) async {
    // No-op: in-memory storage doesn't need indexes.
    // Pre-create collections so getCollectionNames returns them.
    for (final repo in repositories) {
      _collections.putIfAbsent(repo, () => []);
    }
  }

  @override
  Future<List<String>> getCollectionNames() async {
    return _collections.keys
        .where((k) => !k.startsWith('_'))
        .toList();
  }

  @override
  Future<int> collectionCount(String collection) async {
    return _collections[collection]?.length ?? 0;
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
    final docs = _collections[collection];
    if (docs == null || docs.isEmpty) return null;

    var filtered = List<Map<String, dynamic>>.from(docs);

    if (eqField != null) {
      filtered = filtered.where((d) => d[eqField] == eqValue).toList();
    }

    if (filtered.isEmpty) return null;

    if (sortByField != null) {
      filtered.sort((a, b) {
        final av = a[sortByField] as Comparable? ?? 0;
        final bv = b[sortByField] as Comparable? ?? 0;
        return sortDescending ? bv.compareTo(av) : av.compareTo(bv);
      });
    }

    // Return a copy to prevent mutation
    return Map<String, dynamic>.from(filtered.first);
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
    final docs = _collections[collection];
    if (docs == null || docs.isEmpty) return [];

    var filtered = List<Map<String, dynamic>>.from(docs);

    if (eqField != null) {
      filtered = filtered.where((d) => d[eqField] == eqValue).toList();
    }

    if (gtField != null && gtValue != null) {
      filtered = filtered.where((d) {
        final v = d[gtField];
        if (v is Comparable && gtValue is Comparable) {
          return v.compareTo(gtValue) > 0;
        }
        return false;
      }).toList();
    }

    if (sortByField != null) {
      filtered.sort((a, b) {
        final av = a[sortByField] as Comparable? ?? 0;
        final bv = b[sortByField] as Comparable? ?? 0;
        return sortDescending ? bv.compareTo(av) : av.compareTo(bv);
      });
    }

    if (limit != null && limit > 0 && filtered.length > limit) {
      filtered = filtered.sublist(0, limit);
    }

    // Return copies to prevent mutation
    return filtered.map((d) => Map<String, dynamic>.from(d)).toList();
  }

  @override
  Future<void> insertOne(String collection, Map<String, dynamic> doc) async {
    _collections.putIfAbsent(collection, () => []);
    _collections[collection]!.add(Map<String, dynamic>.from(doc));
  }

  @override
  Future<int> getNextSequence(String repositoryName) async {
    _sequenceCounters[repositoryName] =
        (_sequenceCounters[repositoryName] ?? 0) + 1;
    return _sequenceCounters[repositoryName]!;
  }
}
