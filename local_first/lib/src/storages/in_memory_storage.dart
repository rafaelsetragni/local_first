part of '../../local_first.dart';

/// Simple in-memory storage implementation for testing and ephemeral use.
class InMemoryLocalFirstStorage implements LocalFirstStorage {
  final Map<String, Map<String, Map<String, dynamic>>> _tables = {};
  final Map<String, String> _meta = {};
  final Map<String, DateTime> _registeredEvents = {};
  final Map<String, StreamController<List<Map<String, dynamic>>>> _controllers =
      {};
  final Map<String, Map<String, LocalFieldType>> _schemas = {};
  final Map<String, String> _idFields = {};

  bool _opened = false;
  String _namespace = 'default';

  StreamController<List<Map<String, dynamic>>> _controller(String table) {
    return _controllers.putIfAbsent(
      table,
      () => StreamController<List<Map<String, dynamic>>>.broadcast(),
    );
  }

  Future<void> _emit(String table) async {
    final controller = _controller(table);
    if (controller.isClosed) return;
    controller.add(await getAll(table));
  }

  @override
  Future<void> open({String namespace = 'default'}) async {
    _namespace = namespace;
    _opened = true;
  }

  @override
  bool get isOpened => _opened;

  @override
  bool get isClosed => !_opened;

  @override
  String get currentNamespace => _namespace;

  @override
  Future<void> initialize() async {
    _opened = true;
  }

  @override
  Future<void> close() async {
    _opened = false;
    for (final c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
  }

  @override
  Future<void> clearAllData() async {
    _tables.clear();
    _meta.clear();
    _registeredEvents.clear();
    for (final controller in _controllers.values) {
      if (!controller.isClosed) controller.add([]);
    }
  }

  @override
  Future<void> ensureSchema(
    String tableName,
    Map<String, LocalFieldType> schema, {
    required String idFieldName,
  }) async {
    _schemas[tableName] = schema;
    _idFields[tableName] = idFieldName;
  }

  @override
  Future<List<Map<String, dynamic>>> getAll(String tableName) async {
    return _tables[tableName]?.values.map((e) => Map.of(e)).toList() ?? [];
  }

  @override
  Future<Map<String, dynamic>?> getById(String tableName, String id) async {
    return _tables[tableName]?[id];
  }

  @override
  Future<void> insert(
    String tableName,
    Map<String, dynamic> item,
    String idField,
  ) async {
    _tables.putIfAbsent(tableName, () => {});
    _tables[tableName]![item[idField] as String] = item;
    await _emit(tableName);
  }

  @override
  Future<void> update(
    String tableName,
    String id,
    Map<String, dynamic> item,
  ) async {
    _tables.putIfAbsent(tableName, () => {});
    _tables[tableName]![id] = item;
    await _emit(tableName);
  }

  @override
  Future<void> delete(String repositoryName, String id) async {
    _tables[repositoryName]?.remove(id);
    await _emit(repositoryName);
  }

  @override
  Future<void> deleteAll(String tableName) async {
    _tables[tableName]?.clear();
    await _emit(tableName);
  }

  @override
  Future<void> setMeta(String key, String value) async {
    _meta[key] = value;
  }

  @override
  Future<String?> getMeta(String key) async => _meta[key];

  @override
  Future<Map<String, dynamic>> queryTable(
    String tableName, {
    List<QueryFilter> filters = const [],
    List<QuerySort> sorts = const [],
    int? limit,
    int? offset,
  }) async {
    var rows = await getAll(tableName);
    // Apply filters
    for (final filter in filters) {
      rows = rows.where(filter.matches).toList();
    }
    // Apply sorts
    for (final sort in sorts.reversed) {
      rows.sort((a, b) {
        final va = a[sort.field];
        final vb = b[sort.field];
        if (va is Comparable && vb is Comparable) {
          final cmp = va.compareTo(vb);
          return sort.descending ? -cmp : cmp;
        }
        return 0;
      });
    }
    // Offset and limit
    if (offset != null && offset > 0) {
      rows = rows.skip(offset).toList();
    }
    if (limit != null && limit >= 0) {
      rows = rows.take(limit).toList();
    }
    return {'data': rows};
  }

  @override
  Stream<List<Map<String, dynamic>>> watch(String tableName) async* {
    yield await getAll(tableName);
    yield* _controller(tableName).stream;
  }

  @override
  Future<void> registerEvent(String eventId, DateTime createdAt) async {
    _registeredEvents[eventId] = createdAt;
  }

  @override
  Future<bool> isEventRegistered(String eventId) async =>
      _registeredEvents.containsKey(eventId);

  @override
  Future<void> pruneRegisteredEvents(DateTime before) async {
    _registeredEvents.removeWhere((_, ts) => ts.isBefore(before));
  }

  @override
  Future<List<JsonMap<dynamic>>> query(LocalFirstQuery<Object> query) async {
    return _applyQuery(await getAll(query.repositoryName), query);
  }

  @override
  Stream<List<JsonMap<dynamic>>> watchQuery(LocalFirstQuery<Object> query) {
    return watch(
      query.repositoryName,
    ).map((items) => _applyQuery(items, query));
  }

  List<JsonMap<dynamic>> _applyQuery(
    List<JsonMap<dynamic>> items,
    LocalFirstQuery<Object> query,
  ) {
    var filtered = items;

    if (query.filters.isNotEmpty) {
      filtered = filtered
          .where(
            (item) => query.filters.every((filter) => filter.matches(item)),
          )
          .toList();
    }

    if (query.sorts.isNotEmpty) {
      filtered.sort((a, b) {
        for (final sort in query.sorts) {
          final va = a[sort.field];
          final vb = b[sort.field];
          if (va is Comparable && vb is Comparable) {
            final cmp = va.compareTo(vb);
            if (cmp != 0) {
              return sort.descending ? -cmp : cmp;
            }
          }
        }
        return 0;
      });
    }

    if (query.offset != null && query.offset! > 0) {
      filtered = filtered.skip(query.offset!).toList();
    }
    if (query.limit != null) {
      filtered = filtered.take(query.limit!).toList();
    }
    return filtered;
  }
}
