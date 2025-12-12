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

    for (final observers in _observers.values) {
      for (final observer in observers) {
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
  Future<List<Map<String, dynamic>>> getAll(String tableName) async {
    final db = await _database;
    final resolvedTable = _tableName(tableName);
    await _ensureTable(resolvedTable);

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
    final resolvedTable = _tableName(tableName);
    await _ensureTable(resolvedTable);

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
    final resolvedTable = _tableName(tableName);
    await _ensureTable(resolvedTable);

    final id = item[idField];
    if (id is! String) {
      throw ArgumentError('Item is missing string id field "$idField".');
    }

    await db.insert(resolvedTable, {
      'id': id,
      'data': jsonEncode(item),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await _notifyWatchers(tableName);
  }

  @override
  Future<void> update(
    String tableName,
    String id,
    Map<String, dynamic> item,
  ) async {
    final db = await _database;
    final resolvedTable = _tableName(tableName);
    await _ensureTable(resolvedTable);

    await db.insert(resolvedTable, {
      'id': id,
      'data': jsonEncode(item),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await _notifyWatchers(tableName);
  }

  @override
  Future<void> delete(String repositoryName, String id) async {
    final db = await _database;
    final resolvedTable = _tableName(repositoryName);
    await _ensureTable(resolvedTable);

    await db.delete(resolvedTable, where: 'id = ?', whereArgs: [id]);
    await _notifyWatchers(repositoryName);
  }

  @override
  Future<void> deleteAll(String tableName) async {
    final db = await _database;
    final resolvedTable = _tableName(tableName);
    await _ensureTable(resolvedTable);

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

  Future<void> _ensureTable(String resolvedTableName) async {
    final db = await _database;
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $resolvedTableName (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
    );
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
    final resolvedTable = _tableName(query.repositoryName);
    await _ensureTable(resolvedTable);

    // Fast path: whereIn with empty list can never match
    for (final filter in query.filters) {
      if (filter.whereIn != null && filter.whereIn!.isEmpty) {
        return const [];
      }
    }

    Object? normalizeValue(dynamic value) {
      if (value is bool) return value ? 1 : 0;
      return value;
    }

    final whereClauses = <String>[];
    final orderClauses = <String>[];
    final args = <Object?>[];

    for (final filter in query.filters) {
      final path = '\$.${filter.field}';

      if (filter.isNull != null) {
        whereClauses.add(
          'json_extract(data, ?) IS ${filter.isNull! ? '' : 'NOT '}NULL',
        );
        args.add(path);
        continue;
      }

      if (filter.isEqualTo != null) {
        whereClauses.add('json_extract(data, ?) = ?');
        args
          ..add(path)
          ..add(normalizeValue(filter.isEqualTo));
      }

      if (filter.isNotEqualTo != null) {
        whereClauses.add('json_extract(data, ?) != ?');
        args
          ..add(path)
          ..add(normalizeValue(filter.isNotEqualTo));
      }

      if (filter.isLessThan != null) {
        whereClauses.add('json_extract(data, ?) < ?');
        args
          ..add(path)
          ..add(normalizeValue(filter.isLessThan));
      }

      if (filter.isLessThanOrEqualTo != null) {
        whereClauses.add('json_extract(data, ?) <= ?');
        args
          ..add(path)
          ..add(normalizeValue(filter.isLessThanOrEqualTo));
      }

      if (filter.isGreaterThan != null) {
        whereClauses.add('json_extract(data, ?) > ?');
        args
          ..add(path)
          ..add(normalizeValue(filter.isGreaterThan));
      }

      if (filter.isGreaterThanOrEqualTo != null) {
        whereClauses.add('json_extract(data, ?) >= ?');
        args
          ..add(path)
          ..add(normalizeValue(filter.isGreaterThanOrEqualTo));
      }

      if (filter.whereIn != null) {
        final placeholders = List.filled(
          filter.whereIn!.length,
          '?',
        ).join(', ');
        whereClauses.add('json_extract(data, ?) IN ($placeholders)');
        args.add(path);
        args.addAll(filter.whereIn!.map<Object?>(normalizeValue));
      }

      if (filter.whereNotIn != null && filter.whereNotIn!.isNotEmpty) {
        final placeholders = List.filled(
          filter.whereNotIn!.length,
          '?',
        ).join(', ');
        whereClauses.add('json_extract(data, ?) NOT IN ($placeholders)');
        args.add(path);
        args.addAll(filter.whereNotIn!.map<Object?>(normalizeValue));
      }
    }

    for (final sort in query.sorts) {
      orderClauses.add(
        'json_extract(data, ?) ${sort.descending ? 'DESC' : 'ASC'}',
      );
      args.add('\$.${sort.field}');
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
