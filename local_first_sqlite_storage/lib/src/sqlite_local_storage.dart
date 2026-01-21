import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:local_first/local_first.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// SQLite implementation of [LocalFirstStorage].
///
/// Stores each repository as a table with `id` and `data` (JSON string) columns,
/// plus a metadata table for key/value pairs. Each namespace is isolated into
/// its own database file. Queries reuse the default in-memory filtering from
/// [LocalFirstStorage.query], while write operations trigger watchers to re-run
/// their queries.
class SqliteLocalFirstStorage implements LocalFirstStorage {
  SqliteLocalFirstStorage({
    this.databaseName = 'local_first.db',
    this.databasePath,
    String namespace = 'default',
    DatabaseFactory? dbFactory,
  }) : _namespace = namespace,
       _factory = dbFactory ?? databaseFactory {
    _validateIdentifier(_namespace, 'namespace');
  }

  final String databaseName;
  final String? databasePath;
  String _namespace;
  final DatabaseFactory _factory;

  String get namespace => _namespace;

  Database? _db;
  bool _initialized = false;

  final JsonMap<Set<_SqliteQueryObserver>> _observers = {};
  final JsonMap<JsonMap<LocalFieldType>> _schemas = {};

  static final RegExp _validName = RegExp(r'^[a-zA-Z0-9_]+$');

  String get _metadataTable => 'metadata';

  String get _resolvedDatabaseName =>
      _namespace == 'default' ? databaseName : '${_namespace}__$databaseName';

  Future<String> _databasePath() async {
    if (databasePath != null) return databasePath!;
    return p.join(await getDatabasesPath(), _resolvedDatabaseName);
  }

  Future<Database> get _database async {
    if (!_initialized || _db == null) {
      throw StateError(
        'SqliteLocalFirstStorage not initialized. Call initialize() first.',
      );
    }
    return _db!;
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    final path = await _databasePath();

    _db = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS $_metadataTable (key TEXT PRIMARY KEY, value TEXT)',
          );
        },
      ),
    );

    _initialized = true;
    await _ensureMetadataTable(db: _db);
  }

  @override
  Future<void> close() async {
    if (!_initialized) return;

    for (final observers in List.of(_observers.values)) {
      for (final observer in List.of(observers)) {
        await observer.controller.close();
      }
    }
    _observers.clear();

    await _db?.close();
    _db = null;
    _initialized = false;
  }

  /// Changes the active namespace, closing the current database and
  /// opening a separate database file for the new namespace.
  @override
  Future<void> useNamespace(String namespace) async {
    if (_namespace == namespace) return;
    _validateIdentifier(namespace, 'namespace');
    await close();
    _namespace = namespace;
    await initialize();
  }

  @override
  Future<void> clearAllData() async {
    final db = await _database;

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    );

    final repositoriesToNotify = <String>{};
    for (final row in tables) {
      final name = row['name'] as String;
      await db.delete(name);
      final isMetadata = name == _metadataTable;
      final isEventTable = name.endsWith('__events');
      if (!isMetadata && !isEventTable) {
        repositoriesToNotify.add(name);
      }
    }

    for (final repositoryName in repositoriesToNotify) {
      await _notifyWatchers(repositoryName);
    }

    await db.delete(_metadataTable);
    await _ensureMetadataTable();
  }

  @override
  Future<void> ensureSchema(
    String tableName,
    JsonMap<LocalFieldType> schema, {
    required String idFieldName,
  }) async {
    _schemas[tableName] = Map.unmodifiable(schema);
    await _ensureTables(tableName);
  }

  @override
  Future<List<JsonMap>> getAll(String tableName) async {
    final db = await _database;
    await _ensureTables(tableName);
    final dataTable = _tableName(tableName);
    final eventTable = _tableName(tableName, isEvent: true);

    final rows = await db.rawQuery(
      'SELECT d.data, d._lasteventId, '
      'e.eventId, e.syncStatus, e.operation, e.createdAt '
      'FROM $dataTable d '
      'LEFT JOIN $eventTable e ON d._lasteventId = e.eventId',
    );

    return rows
        .map(_decodeJoinedRow)
        .where((row) => row['operation'] != SyncOperation.delete.index)
        .toList();
  }

  @override
  Future<List<JsonMap>> getAllEvents(String tableName) async {
    final db = await _database;
    await _ensureTables(tableName);
    final eventTable = _tableName(tableName, isEvent: true);
    final dataTable = _tableName(tableName);

    final rows = await db.rawQuery(
      'SELECT d.data, d._lasteventId, '
      'e.eventId, e.dataId, e.syncStatus, '
      'e.operation, e.createdAt '
      'FROM $eventTable e '
      'LEFT JOIN $dataTable d ON e.dataId = d.id',
    );

    return rows.map(_decodeJoinedRow).toList();
  }

  @override
  Future<JsonMap?> getById(String tableName, String id) async {
    final db = await _database;
    await _ensureTables(tableName);
    final dataTable = _tableName(tableName);
    final eventTable = _tableName(tableName, isEvent: true);

    final rows = await db.rawQuery(
      'SELECT d.data, d._lasteventId, '
      'e.eventId, e.syncStatus, e.operation, e.createdAt '
      'FROM $dataTable d '
      'LEFT JOIN $eventTable e ON d._lasteventId = e.eventId '
      'WHERE d.id = ? '
      'LIMIT 1',
      [id],
    );

    if (rows.isEmpty || rows.first['data'] == null) return null;
    return _decodeJoinedRow(rows.first);
  }

  @override
  Future<JsonMap?> getEventById(String tableName, String id) async {
    final db = await _database;
    await _ensureTables(tableName);
    final eventTable = _tableName(tableName, isEvent: true);
    final dataTable = _tableName(tableName);

    final rows = await db.rawQuery(
      'SELECT d.data, d._lasteventId, '
      'e.eventId, e.dataId, e.syncStatus, '
      'e.operation, e.createdAt '
      'FROM $eventTable e '
      'LEFT JOIN $dataTable d ON e.dataId = d.id '
      'WHERE e.eventId = ? '
      'LIMIT 1',
      [id],
    );

    if (rows.isEmpty) return null;
    return _decodeJoinedRow(rows.first);
  }

  @override
  Future<void> insert(String tableName, JsonMap item, String idField) async {
    final db = await _database;
    await _ensureTables(tableName);
    final resolvedTable = _tableName(tableName);

    final id = item[idField];
    if (id is! String) {
      throw ArgumentError('Item is missing string id field "$idField".');
    }

    final schema = _schemaFor(tableName);
    final lastEventId = item['_lasteventId'] as String?;
    final row = _encodeDataRow(schema, item, id, lastEventId);

    await db.insert(
      resolvedTable,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _notifyWatchers(tableName);
  }

  @override
  Future<void> insertEvent(
    String tableName,
    JsonMap item,
    String idField,
  ) async {
    final db = await _database;
    await _ensureTables(tableName);
    final resolvedTable = _tableName(tableName, isEvent: true);

    final eventId = item[idField];
    final dataId = item['dataId'] ?? item[idField];
    if (eventId is! String) {
      throw ArgumentError('Item is missing string id field "$idField".');
    }
    if (dataId is! String) {
      throw ArgumentError('Event item is missing data id reference.');
    }

    final row = _encodeEventRow(item, dataId, eventId);

    await db.insert(
      resolvedTable,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _notifyWatchers(tableName);
  }

  @override
  Future<void> update(String tableName, String id, JsonMap item) async {
    final db = await _database;
    await _ensureTables(tableName);
    final resolvedTable = _tableName(tableName);

    final schema = _schemaFor(tableName);
    final eventId = item['_lasteventId'] as String?;
    final row = _encodeDataRow(schema, item, id, eventId);

    await db.insert(
      resolvedTable,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _notifyWatchers(tableName);
  }

  @override
  Future<void> updateEvent(String tableName, String id, JsonMap item) async {
    final db = await _database;
    await _ensureTables(tableName);
    final resolvedTable = _tableName(tableName, isEvent: true);

    final dataId = item['dataId'] ?? id;
    if (dataId is! String) {
      throw ArgumentError('Event item is missing data id reference.');
    }
    final row = _encodeEventRow(item, dataId, id);

    await db.insert(
      resolvedTable,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _notifyWatchers(tableName);
  }

  @override
  Future<void> delete(String repositoryName, String id) async {
    final db = await _database;
    final resolvedTable = _tableName(repositoryName);
    await _ensureDataTable(repositoryName);

    await db.delete(resolvedTable, where: 'id = ?', whereArgs: [id]);
    await _notifyWatchers(repositoryName);
  }

  @override
  Future<void> deleteEvent(String repositoryName, String id) async {
    final db = await _database;
    final resolvedTable = _tableName(repositoryName, isEvent: true);
    await _ensureEventTable(repositoryName);

    await db.delete(resolvedTable, where: 'id = ?', whereArgs: [id]);
    await _notifyWatchers(repositoryName);
  }

  @override
  Future<void> deleteAll(String tableName) async {
    final db = await _database;
    await _ensureDataTable(tableName);
    final resolvedTable = _tableName(tableName);

    await db.delete(resolvedTable);
    await _notifyWatchers(tableName);
  }

  @override
  Future<void> deleteAllEvents(String tableName) async {
    final db = await _database;
    await _ensureEventTable(tableName);
    final resolvedTable = _tableName(tableName, isEvent: true);

    await db.delete(resolvedTable);
    await _notifyWatchers(tableName);
  }

  String _encodeConfigValue(Object value) {
    if (value is bool) return jsonEncode({'t': 'bool', 'v': value});
    if (value is int) return jsonEncode({'t': 'int', 'v': value});
    if (value is double) return jsonEncode({'t': 'double', 'v': value});
    if (value is String) return jsonEncode({'t': 'string', 'v': value});
    if (value is List && value.every((e) => e is String)) {
      return jsonEncode({'t': 'string_list', 'v': List<String>.from(value)});
    }
    throw ArgumentError(
      'Unsupported config value type ${value.runtimeType}. '
      'Allowed: bool, int, double, String, List<String>.',
    );
  }

  T? _decodeConfigValue<T>(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final type = decoded['t'] as String?;
      final value = decoded['v'];
      switch (type) {
        case 'bool':
          return value is bool && (T == bool || T == dynamic) ? value as T : null;
        case 'int':
          return value is int && (T == int || T == dynamic) ? value as T : null;
        case 'double':
          if (value is num && (T == double || T == dynamic)) {
            return value.toDouble() as T;
          }
          return null;
        case 'string':
          return value is String && (T == String || T == dynamic)
              ? value as T
              : null;
        case 'string_list':
          if (value is List && value.every((e) => e is String)) {
            final list = List<String>.from(value);
            if (list is T) return list as T;
          }
          return null;
        default:
          return null;
      }
    } catch (_) {
      if (T == String || T == dynamic) return raw as T;
      return null;
    }
  }

  @override
  Future<bool> containsConfigKey(String key) async {
    final db = await _database;
    await _ensureMetadataTable();
    final rows = await db.query(
      _metadataTable,
      columns: ['key'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<bool> setConfigValue<T>(String key, T value) async {
    final db = await _database;
    await _ensureMetadataTable();

    if (value is! Object) {
      throw ArgumentError('Config value cannot be null.');
    }
    final encoded = _encodeConfigValue(value);
    await db.insert(_metadataTable, {
      'key': key,
      'value': encoded,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  @override
  Future<bool> containsId(String tableName, String id) async {
    final db = await _database;
    await _ensureTables(tableName);
    final resolvedTable = _tableName(tableName);
    final rows = await db.query(
      resolvedTable,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<T?> getConfigValue<T>(String key) async {
    final db = await _database;
    await _ensureMetadataTable();

    final rows = await db.query(
      _metadataTable,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final value = rows.first['value'];
    if (value is! String) return null;
    return _decodeConfigValue<T>(value);
  }

  @override
  Future<bool> removeConfig(String key) async {
    final db = await _database;
    await _ensureMetadataTable();
    await db.delete(_metadataTable, where: 'key = ?', whereArgs: [key]);
    return true;
  }

  @override
  Future<bool> clearConfig() async {
    final db = await _database;
    await _ensureMetadataTable();
    await db.delete(_metadataTable);
    return true;
  }

  @override
  Future<Set<String>> getConfigKeys() async {
    final db = await _database;
    await _ensureMetadataTable();
    final rows = await db.query(_metadataTable, columns: ['key']);
    return rows.map((row) => row['key']).whereType<String>().toSet();
  }

  @override
  Stream<List<LocalFirstEvent<T>>> watchQuery<T>(LocalFirstQuery<T> query) {
    if (!_initialized) {
      throw StateError(
        'SqliteLocalFirstStorage not initialized. Call initialize() first.',
      );
    }

    final observer = _SqliteQueryObserver<T>(
      query,
      StreamController<List<LocalFirstEvent<T>>>.broadcast(),
    );

    _observers
        .putIfAbsent(query.repositoryName, () => <_SqliteQueryObserver>{})
        .add(observer);

    Future<void> emit() async {
      try {
        final results = await this.query<T>(query);
        if (!observer.controller.isClosed) {
          observer.controller.add(results);
        }
      } catch (e, st) {
        if (!observer.controller.isClosed) {
          observer.controller.addError(e, st);
        }
      }
    }

    observer.controller
      ..onListen = emit
      ..onCancel = () {
        final observers = _observers[query.repositoryName];
        observers?.remove(observer);
        if (observers != null && observers.isEmpty) {
          _observers.remove(query.repositoryName);
        }
      };

    return observer.controller.stream;
  }

  Future<void> _ensureMetadataTable({Database? db}) async {
    db ??= await _database;
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $_metadataTable (key TEXT PRIMARY KEY, value TEXT)',
    );
  }

  JsonMap<LocalFieldType> _schemaFor(String repositoryName) {
    return _schemas[repositoryName] ?? const {};
  }

  Future<void> _ensureTables(String repositoryName) async {
    await _ensureDataTable(repositoryName);
    await _ensureEventTable(repositoryName);
  }

  Future<void> _ensureDataTable(String repositoryName) async {
    final db = await _database;
    final resolvedTableName = _tableName(repositoryName);
    final schema = _schemaFor(repositoryName);
    const reservedColumns = {'id', 'data', '_lasteventId'};

    final columnDefinitions = StringBuffer(
      'id TEXT PRIMARY KEY, '
      'data TEXT NOT NULL, '
      '_lasteventId TEXT',
    );

    for (final entry in schema.entries) {
      if (reservedColumns.contains(entry.key)) {
        throw ArgumentError('Field name "${entry.key}" is reserved.');
      }
      _validateIdentifier(entry.key, 'field');
      columnDefinitions.write(', "${entry.key}" ${_sqlTypeFor(entry.value)}');
    }

    await db.execute(
      'CREATE TABLE IF NOT EXISTS $resolvedTableName (${columnDefinitions.toString()})',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS ${resolvedTableName}__last_event '
      'ON $resolvedTableName(_lasteventId)',
    );

    for (final entry in schema.entries) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS ${resolvedTableName}__${entry.key} '
        'ON $resolvedTableName("${entry.key}")',
      );
    }
  }

  Future<void> _ensureEventTable(String repositoryName) async {
    final db = await _database;
    final resolvedTableName = _tableName(repositoryName, isEvent: true);

    await db.execute(
      'CREATE TABLE IF NOT EXISTS $resolvedTableName ('
      'eventId TEXT PRIMARY KEY, '
      'dataId TEXT NOT NULL, '
      'syncStatus INTEGER, '
      'operation INTEGER, '
      'createdAt INTEGER'
      ')',
    );

    await db.execute(
      'CREATE INDEX IF NOT EXISTS ${resolvedTableName}__data '
      'ON $resolvedTableName(dataId)',
    );
  }

  String _tableName(String name, {bool isEvent = false}) {
    _validateIdentifier(name, 'tableName');
    final base = name;
    return isEvent ? '${base}__events' : base;
  }

  static void _validateIdentifier(String name, String label) {
    if (!_validName.hasMatch(name)) {
      throw ArgumentError(
        'Invalid $label "$name". Only alphanumeric and underscore characters '
        'are supported.',
      );
    }
  }

  String _sqlTypeFor(LocalFieldType type) {
    switch (type) {
      case LocalFieldType.text:
        return 'TEXT';
      case LocalFieldType.integer:
        return 'INTEGER';
      case LocalFieldType.real:
        return 'REAL';
      case LocalFieldType.boolean:
        return 'INTEGER';
      case LocalFieldType.datetime:
        return 'INTEGER';
      case LocalFieldType.blob:
        return 'BLOB';
    }
  }

  Object? _encodeValue(LocalFieldType? type, dynamic value) {
    if (value == null) return null;
    switch (type) {
      case LocalFieldType.boolean:
        if (value is num) return value;
        return value == true ? 1 : 0;
      case LocalFieldType.datetime:
        if (value is DateTime) {
          return value.toUtc().millisecondsSinceEpoch;
        }
        if (value is String) {
          final parsed = DateTime.tryParse(value);
          return parsed?.toUtc().millisecondsSinceEpoch;
        }
        return value;
      case LocalFieldType.integer:
        return value is bool ? (value ? 1 : 0) : value;
      case LocalFieldType.real:
        return value;
      case LocalFieldType.text:
        return value;
      case LocalFieldType.blob:
        if (value is List<int>) return Uint8List.fromList(value);
        return value;
      case null:
        return value is bool ? (value ? 1 : 0) : value;
    }
  }

  JsonMap<Object?> _encodeDataRow(
    JsonMap<LocalFieldType> schema,
    JsonMap item,
    String id,
    String? lastEventId,
  ) {
    final payload = JsonMap.from(item);
    const metaKeys = {
      '_lasteventId',
      'eventId',
      'dataId',
      'syncStatus',
      'operation',
      'createdAt',
    };
    payload.removeWhere((key, _) => metaKeys.contains(key));

    final row = <String, Object?>{
      'id': id,
      'data': jsonEncode(_normalizeJsonMap(payload)),
      '_lasteventId': lastEventId,
    };

    for (final entry in schema.entries) {
      row[entry.key] = _encodeValue(entry.value, item[entry.key]);
    }

    return row;
  }

  JsonMap<Object?> _encodeEventRow(
    JsonMap item,
    String dataId,
    String eventId,
  ) {
    return {
      'eventId': eventId,
      'dataId': dataId,
      'syncStatus': item['syncStatus'],
      'operation': item['operation'],
      'createdAt': item['createdAt'],
    };
  }

  JsonMap _decodeJoinedRow(JsonMap<Object?> row) {
    final data = row['data'];
    final map = data is String
        ? JsonMap.from(jsonDecode(data) as Map)
        : <String, dynamic>{};

    final lastEventId = row['_lasteventId'];
    final eventId = row['eventId'];
    final syncStatus = row['syncStatus'];
    final syncOperation = row['operation'];
    final syncCreatedAt = row['createdAt'];
    final dataId = row['dataId'];

    if (lastEventId is String) map['_lasteventId'] = lastEventId;
    if (eventId is String) map['eventId'] = eventId;
    if (dataId is String) {
      map['dataId'] = dataId;
      map.putIfAbsent('id', () => dataId);
    }
    if (syncStatus != null) map['syncStatus'] = syncStatus;
    if (syncOperation != null) map['operation'] = syncOperation;
    if (syncCreatedAt != null) map['createdAt'] = syncCreatedAt;

    return map;
  }

  JsonMap _normalizeJsonMap(JsonMap map) {
    return map.map((key, value) => MapEntry(key, _normalizeJsonValue(value)));
  }

  dynamic _normalizeJsonValue(dynamic value) {
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is List) {
      return value.map(_normalizeJsonValue).toList();
    }
    if (value is Map) {
      return value.map(
        (key, val) => MapEntry(key as Object, _normalizeJsonValue(val)),
      );
    }
    return value;
  }

  Future<void> _notifyWatchers(String repositoryName) async {
    final observers = _observers[repositoryName];
    if (observers == null || observers.isEmpty) return;

    for (final observer in List.of(observers)) {
      if (observer.controller.isClosed) {
        observers.remove(observer);
        continue;
      }
      try {
        final results = await query(observer.query);
        observer.controller.add(results);
      } catch (e, st) {
        observer.controller.addError(e, st);
      }
    }
  }

  @override
  Future<List<LocalFirstEvent<T>>> query<T>(LocalFirstQuery<T> query) async {
    final db = await _database;
    await _ensureTables(query.repositoryName);
    final resolvedTable = _tableName(query.repositoryName);
    final eventTable = _tableName(query.repositoryName, isEvent: true);
    final schema = _schemaFor(query.repositoryName);

    for (final filter in query.filters) {
      if (filter.whereIn != null && filter.whereIn!.isEmpty) {
        return const [];
      }
    }

    final whereClauses = <String>[];
    final orderClauses = <String>[];
    final args = <Object?>[];

    String columnExpr(String field) {
      if (schema.containsKey(field)) {
        return 'd."$field"';
      }
      args.add('\$.$field');
      return 'json_extract(d.data, ?)';
    }

    Object? encode(String field, dynamic value) {
      return _encodeValue(schema[field], value);
    }

    for (final filter in query.filters) {
      final column = columnExpr(filter.field);

      if (filter.isNull != null) {
        whereClauses.add('$column IS ${filter.isNull! ? '' : 'NOT '}NULL');
        continue;
      }

      if (filter.isEqualTo != null) {
        whereClauses.add('$column = ?');
        args.add(encode(filter.field, filter.isEqualTo));
      }

      if (filter.isNotEqualTo != null) {
        whereClauses.add('$column != ?');
        args.add(encode(filter.field, filter.isNotEqualTo));
      }

      if (filter.isLessThan != null) {
        whereClauses.add('$column < ?');
        args.add(encode(filter.field, filter.isLessThan));
      }

      if (filter.isLessThanOrEqualTo != null) {
        whereClauses.add('$column <= ?');
        args.add(encode(filter.field, filter.isLessThanOrEqualTo));
      }

      if (filter.isGreaterThan != null) {
        whereClauses.add('$column > ?');
        args.add(encode(filter.field, filter.isGreaterThan));
      }

      if (filter.isGreaterThanOrEqualTo != null) {
        whereClauses.add('$column >= ?');
        args.add(encode(filter.field, filter.isGreaterThanOrEqualTo));
      }

      if (filter.whereIn != null) {
        final placeholders = List.filled(
          filter.whereIn!.length,
          '?',
        ).join(', ');
        whereClauses.add('$column IN ($placeholders)');
        args.addAll(
          filter.whereIn!.map<Object?>((value) => encode(filter.field, value)),
        );
      }

      if (filter.whereNotIn != null && filter.whereNotIn!.isNotEmpty) {
        final placeholders = List.filled(
          filter.whereNotIn!.length,
          '?',
        ).join(', ');
        whereClauses.add('$column NOT IN ($placeholders)');
        args.addAll(
          filter.whereNotIn!.map<Object?>(
            (value) => encode(filter.field, value),
          ),
        );
      }
    }

    for (final sort in query.sorts) {
      final column = columnExpr(sort.field);
      orderClauses.add('$column ${sort.descending ? 'DESC' : 'ASC'}');
    }

    final sql = StringBuffer(
      'SELECT d.data, d._lasteventId, '
      'e.eventId, e.syncStatus, e.operation, e.createdAt '
      'FROM $resolvedTable d '
      'LEFT JOIN $eventTable e ON d._lasteventId = e.eventId',
    );
    if (whereClauses.isNotEmpty) {
      sql.write(' WHERE ${whereClauses.join(' AND ')}');
    }
    if (!query.includeDeleted) {
      sql.write(whereClauses.isEmpty ? ' WHERE ' : ' AND ');
      sql.write('e.operation != ?');
      args.add(SyncOperation.delete.index);
    }
    if (orderClauses.isNotEmpty) {
      sql.write(' ORDER BY ${orderClauses.join(', ')}');
    }

    if (query.limit != null || query.offset != null) {
      sql.write(' LIMIT ');
      if (query.limit != null) {
        sql.write('?');
        args.add(query.limit);
      } else {
        sql.write('-1');
      }

      if (query.offset != null) {
        sql.write(' OFFSET ?');
        args.add(query.offset);
      }
    }

    final rows = await db.rawQuery(sql.toString(), args);

    final repo = query.repository;
    final mapped = rows.map(_decodeJoinedRow);
    return mapped
        .map(
          (json) =>
              LocalFirstEvent<T>.fromLocalStorage(repository: repo, json: json),
        )
        .toList();
  }
}

class _SqliteQueryObserver<T> {
  _SqliteQueryObserver(this.query, this.controller);

  final LocalFirstQuery<T> query;
  final StreamController<List<LocalFirstEvent<T>>> controller;
}

/// Test helper exposing internal methods of [SqliteLocalFirstStorage] for unit tests.
class TestHelperSqliteLocalFirstStorage {
  final SqliteLocalFirstStorage storage;

  TestHelperSqliteLocalFirstStorage(this.storage);

  Future<Database> get database async => storage._database;
  JsonMap<Set<dynamic>> get observers => storage._observers;
  JsonMap<JsonMap<LocalFieldType>> get schemas => storage._schemas;

  String tableName(String name, {bool isEvent = false}) =>
      storage._tableName(name, isEvent: isEvent);
  JsonMap decodeJoinedRow(JsonMap row) => storage._decodeJoinedRow(row);
  JsonMap<Object?> encodeDataRow(
    JsonMap<LocalFieldType> schema,
    JsonMap item,
    String id,
    String? lastEventId,
  ) => storage._encodeDataRow(schema, item, id, lastEventId);
  Future<void> notifyWatchers(String repositoryName) =>
      storage._notifyWatchers(repositoryName);
  Future<void> ensureTables(String repositoryName) =>
      storage._ensureTables(repositoryName);
  Future<void> ensureDataTable(String repositoryName) =>
      storage._ensureDataTable(repositoryName);
  Future<void> ensureEventTable(String repositoryName) =>
      storage._ensureEventTable(repositoryName);
  Future<void> ensureMetadataTable() => storage._ensureMetadataTable();
  String get metadataTable => storage._metadataTable;
}
