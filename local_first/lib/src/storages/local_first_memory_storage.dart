part of '../../local_first.dart';

/// Simple in-memory implementation of [LocalFirstStorage] useful for tests
/// or lightweight scenarios without persistence.
class LocalFirstMemoryStorage implements LocalFirstStorage {
  /// namespace -> table -> id -> row
  final JsonMap<JsonMap<JsonMap<JsonMap<dynamic>>>> _tables = {};

  /// namespace -> repository -> events
  final JsonMap<JsonMap<List<JsonMap<dynamic>>>> _events = {};

  String _namespace = 'default';

  /// Switches the active namespace (similar to selecting a database).
  void useNamespace(String namespace) {
    _namespace = namespace;
    _tables.putIfAbsent(_namespace, () => {});
    _events.putIfAbsent(_namespace, () => {});
  }

  JsonMap<JsonMap<dynamic>> _tablesForNamespace() =>
      _tables.putIfAbsent(_namespace, () => {});

  JsonMap<List<JsonMap<dynamic>>> _eventsForNamespace() =>
      _events.putIfAbsent(_namespace, () => {});

  @override
  Future<void> initialize() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> clearAllData() async {
    _tables.clear();
    _events.clear();
  }

  @override
  Future<List<JsonMap<dynamic>>> getAll(String tableName) async {
    final tables = _tablesForNamespace();
    return tables[tableName]
            ?.values
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];
  }

  @override
  Future<JsonMap<dynamic>?> getById(String tableName, String id) async {
    final table = _tablesForNamespace()[tableName];
    if (table == null) return null;
    final item = table[id];
    return item == null ? null : Map.of(item);
  }

  @override
  Future<void> insert(
    String tableName,
    JsonMap<dynamic> item,
    String idField,
  ) async {
    final id = item[idField] as String;
    final table = _tablesForNamespace().putIfAbsent(tableName, () => {});
    table[id] = Map.of(item);
  }

  @override
  Future<void> update(
    String tableName,
    String id,
    JsonMap<dynamic> item,
  ) async {
    final table = _tablesForNamespace().putIfAbsent(tableName, () => {});
    table[id] = Map.of(item);
  }

  @override
  Future<void> delete(String repositoryName, String id) async {
    _tablesForNamespace()[repositoryName]?.remove(id);
  }

  @override
  Future<void> deleteAll(String tableName) async {
    _tablesForNamespace()[tableName]?.clear();
  }

  @override
  Future<void> pullRemoteEvent(JsonMap<dynamic> event) async {
    final repo = event['repository'] as String? ?? '__default__';
    final list = _eventsForNamespace().putIfAbsent(repo, () => []);
    final existingIndex = list.indexWhere(
      (e) => e['event_id'] == event['event_id'],
    );
    if (existingIndex >= 0) {
      list[existingIndex] = Map.of(event);
    } else {
      list.add(Map.of(event));
    }
  }

  @override
  Future<JsonMap<dynamic>?> getEventById(String eventId) async {
    for (final list in _eventsForNamespace().values) {
      final match = list.firstWhere(
        (e) => e['event_id'] == eventId,
        orElse: () => {},
      );
      if (match.isNotEmpty) return Map.of(match);
    }
    return null;
  }

  @override
  Future<List<JsonMap<dynamic>>> getEvents({String? repositoryName}) async {
    final events = _eventsForNamespace();
    if (repositoryName != null) {
      return events[repositoryName]
              ?.map((e) => Map.of(e))
              .toList(growable: false) ??
          [];
    }
    return events.values
        .expand((e) => e)
        .map((e) => Map.of(e))
        .toList(growable: false);
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    for (final list in _eventsForNamespace().values) {
      list.removeWhere((e) => e['event_id'] == eventId);
    }
  }

  @override
  Future<void> clearEvents() async {
    _eventsForNamespace().clear();
  }

  @override
  Future<void> pruneEvents(DateTime before) async {
    final cutoff = before.toUtc().millisecondsSinceEpoch;
    for (final list in _eventsForNamespace().values) {
      list.removeWhere((e) {
        final ts = e['created_at'];
        return ts is int && ts < cutoff;
      });
    }
  }

  @override
  Future<void> ensureSchema(
    String tableName,
    JsonMap<LocalFieldType> schema, {
    required String idFieldName,
  }) async {}

  @override
  Future<List<JsonMap<dynamic>>> query(LocalFirstQuery query) async {
    var items = await getAll(query.repositoryName);

    if (query.filters.isNotEmpty) {
      items = items.where((item) {
        for (var filter in query.filters) {
          if (!filter.matches(item)) return false;
        }
        return true;
      }).toList();
    }

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

    if (query.offset != null && query.offset! > 0) {
      items = items.skip(query.offset!).toList();
    }
    if (query.limit != null) {
      items = items.take(query.limit!).toList();
    }

    return items;
  }

  @override
  Stream<List<JsonMap<dynamic>>> watchQuery(LocalFirstQuery query) async* {
    // No reactive updates here; just emit the current snapshot.
    yield await this.query(query);
  }
}
