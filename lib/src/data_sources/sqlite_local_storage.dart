part of '../../local_first.dart';

/// SQLite implementation of [LocalFirstStorage].
///
/// Stores each repository as a table with `id` and `data` (JSON string) columns,
/// plus a metadata table for key/value pairs. Queries reuse the default
/// in-memory filtering from [LocalFirstStorage.query], while write operations
/// trigger watchers to re-run their queries.
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
  final String _namespace;
  final DatabaseFactory _factory;

  Database? _db;
  bool _initialized = false;

  final Map<String, Set<_SqliteQueryObserver>> _observers = {};
  final Map<String, Map<String, LocalFieldType>> _schemas = {};

  static final RegExp _validName = RegExp(r'^[a-zA-Z0-9_]+$');

  String get _metadataTable => '${_namespace}__metadata';

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

    final path = databasePath ?? p.join(await getDatabasesPath(), databaseName);

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

  @override
  Future<void> clearAllData() async {
    final db = await _database;
    final prefix = '${_namespace}__';

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE ?",
      ['$prefix%'],
    );

    for (final row in tables) {
      final name = row['name'] as String;
      await db.delete(name);
      final repositoryName = name.substring(prefix.length);
      await _notifyWatchers(repositoryName);
    }

    await db.delete(_metadataTable);
    await _ensureMetadataTable();
  }

  @override
  Future<void> ensureSchema(
    String tableName,
    Map<String, LocalFieldType> schema, {
    required String idFieldName,
  }) async {
    _schemas[tableName] = Map.unmodifiable(schema);
    await _ensureTable(tableName);
  }

  @override
  Future<List<Map<String, dynamic>>> getAll(String tableName) async {
    final db = await _database;
    await _ensureTable(tableName);
    final resolvedTable = _tableName(tableName);

    final rows = await db.query(resolvedTable);
    return rows
        .map((row) => row['data'])
        .whereType<String>()
        .map((json) => Map<String, dynamic>.from(jsonDecode(json) as Map))
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> getById(String tableName, String id) async {
    final db = await _database;
    await _ensureTable(tableName);
    final resolvedTable = _tableName(tableName);

    final rows = await db.query(
      resolvedTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final data = rows.first['data'];
    if (data is! String) return null;

    return Map<String, dynamic>.from(jsonDecode(data) as Map);
  }

  @override
  Future<void> insert(
    String tableName,
    Map<String, dynamic> item,
    String idField,
  ) async {
    final db = await _database;
    await _ensureTable(tableName);
    final resolvedTable = _tableName(tableName);

    final id = item[idField];
    if (id is! String) {
      throw ArgumentError('Item is missing string id field "$idField".');
    }

    final schema = _schemaFor(tableName);
    final row = _encodeRowForStorage(schema, item, id);

    await db.insert(
      resolvedTable,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _notifyWatchers(tableName);
  }

  @override
  Future<void> update(
    String tableName,
    String id,
    Map<String, dynamic> item,
  ) async {
    final db = await _database;
    await _ensureTable(tableName);
    final resolvedTable = _tableName(tableName);

    final schema = _schemaFor(tableName);
    final row = _encodeRowForStorage(schema, item, id);

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
    await _ensureTable(repositoryName);

    await db.delete(resolvedTable, where: 'id = ?', whereArgs: [id]);
    await _notifyWatchers(repositoryName);
  }

  @override
  Future<void> deleteAll(String tableName) async {
    final db = await _database;
    await _ensureTable(tableName);
    final resolvedTable = _tableName(tableName);

    await db.delete(resolvedTable);
    await _notifyWatchers(tableName);
  }

  @override
  Future<void> setMeta(String key, String value) async {
    final db = await _database;
    await _ensureMetadataTable();

    await db.insert(_metadataTable, {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<String?> getMeta(String key) async {
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
    return value is String ? value : null;
  }

  @override
  Stream<List<Map<String, dynamic>>> watchQuery(LocalFirstQuery query) {
    if (!_initialized) {
      throw StateError(
        'SqliteLocalFirstStorage not initialized. Call initialize() first.',
      );
    }

    final observer = _SqliteQueryObserver(
      query,
      StreamController<List<Map<String, dynamic>>>.broadcast(),
    );

    _observers
        .putIfAbsent(query.repositoryName, () => <_SqliteQueryObserver>{})
        .add(observer);

    Future<void> emit() async {
      try {
        final results = await this.query(query);
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

  Map<String, LocalFieldType> _schemaFor(String repositoryName) {
    return _schemas[repositoryName] ?? const {};
  }

  Future<void> _ensureTable(String repositoryName) async {
    final db = await _database;
    final resolvedTableName = _tableName(repositoryName);
    final schema = _schemaFor(repositoryName);
    const reservedColumns = {
      'id',
      'data',
      '_sync_status',
      '_sync_operation',
      '_sync_created_at',
    };

    final columnDefinitions = StringBuffer(
      'id TEXT PRIMARY KEY, '
      'data TEXT NOT NULL, '
      '_sync_status INTEGER, '
      '_sync_operation INTEGER, '
      '_sync_created_at INTEGER',
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

    for (final entry in schema.entries) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS ${resolvedTableName}__${entry.key} '
        'ON $resolvedTableName("${entry.key}")',
      );
    }
  }

  String _tableName(String name) {
    _validateIdentifier(name, 'tableName');
    return '${_namespace}__$name';
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

  Map<String, Object?> _encodeRowForStorage(
    Map<String, LocalFieldType> schema,
    Map<String, dynamic> item,
    String id,
  ) {
    final row = <String, Object?>{
      'id': id,
      'data': jsonEncode(_normalizeJsonMap(item)),
      '_sync_status': item['_sync_status'],
      '_sync_operation': item['_sync_operation'],
      '_sync_created_at': item['_sync_created_at'],
    };

    for (final entry in schema.entries) {
      row[entry.key] = _encodeValue(entry.value, item[entry.key]);
    }

    return row;
  }

  Map<String, dynamic> _normalizeJsonMap(Map<String, dynamic> map) {
    return map.map((key, value) => MapEntry(key, _normalizeJsonValue(value)));
  }

  dynamic _normalizeJsonValue(dynamic value) {
    if (value is DateTime) {
      return value.toIso8601String();
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
  Future<List<Map<String, dynamic>>> query(
    LocalFirstQuery<LocalFirstModel> query,
  ) async {
    final db = await _database;
    await _ensureTable(query.repositoryName);
    final resolvedTable = _tableName(query.repositoryName);
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
        return '"$field"';
      }
      args.add('\$.$field');
      return 'json_extract(data, ?)';
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

    final sql = StringBuffer('SELECT data FROM $resolvedTable');
    if (whereClauses.isNotEmpty) {
      sql.write(' WHERE ${whereClauses.join(' AND ')}');
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

    return rows
        .map((row) => row['data'])
        .whereType<String>()
        .map((json) => Map<String, dynamic>.from(jsonDecode(json) as Map))
        .toList();
  }
}

class _SqliteQueryObserver {
  _SqliteQueryObserver(this.query, this.controller);

  final LocalFirstQuery query;
  final StreamController<List<Map<String, dynamic>>> controller;
}
