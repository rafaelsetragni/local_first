part of '../../local_first.dart';

/// Implementation of [LocalFirstStorage] using Hive CE.
///
/// Features:
/// - Stores data as JSON in Hive boxes
/// - Each table is a separate box
/// - Metadata (lastSyncAt) is stored in dedicated box
/// - Operations are fast and completely offline
/// - Supports reactive queries with box.watch()
class HiveLocalFirstStorage implements LocalFirstStorage {
  /// Boxes for each table (lazy-loaded)
  final Map<String, Box<Map<dynamic, dynamic>>> _boxes = {};

  /// Box for sync metadata
  late Box<dynamic> _metadataBox;

  /// Initialization control flag
  bool _initialized = false;

  /// Custom path (useful for testing)
  final String? customPath;

  /// Namespace used to isolate data per user/session.
  String _namespace;

  String get namespace => _namespace;

  final HiveInterface _hive;
  final Future<void> Function() _initFlutter;

  /// Creates a new HiveLocalFirstStorage.
  ///
  /// Parameters:
  /// - [customPath]: Optional custom path for Hive storage (useful for tests)
  /// - [namespace]: Optional namespace to database
  /// - [hive]: Optional Hive interface (useful for tests/mocking)
  /// - [initFlutter]: Optional initializer for Hive Flutter (useful for tests)
  HiveLocalFirstStorage({
    this.customPath,
    String? namespace,
    HiveInterface? hive,
    Future<void> Function()? initFlutter,
  }) : _namespace = namespace ?? 'default',
       _hive = hive ?? Hive,
       _initFlutter = initFlutter ?? Hive.initFlutter;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    // Initialize Hive
    if (customPath != null) {
      _hive.init(customPath);
    } else {
      await _initFlutter();
    }

    // Open metadata box
    _metadataBox = await _hive.openBox<dynamic>(_metadataBoxName);

    _initialized = true;
  }

  @override
  Future<void> close() async {
    if (!_initialized) return;

    await _closeAllBoxes();
    await _metadataBox.close();

    _initialized = false;
  }

  /// Changes the active namespace, closing any open boxes.
  Future<void> useNamespace(String namespace) async {
    if (_namespace == namespace) return;
    _namespace = namespace;

    if (!_initialized) return;

    await _closeAllBoxes();
    _boxes.clear();
    await _metadataBox.close();
    _metadataBox = await _hive.openBox<dynamic>(_metadataBoxName);
  }

  Future<void> _closeAllBoxes() async {
    for (var box in _boxes.values) {
      await box.close();
    }
    _boxes.clear();
  }

  String get _metadataBoxName => '${_namespace}__offline_metadata';

  String _boxName(String tableName) => '${_namespace}__$tableName';

  /// Gets or creates a box for the table.
  Future<Box<Map<dynamic, dynamic>>> _getBox(String tableName) async {
    if (!_initialized) {
      throw StateError(
        'HiveLocalFirstStorage not initialized. Call initialize() first.',
      );
    }

    if (_boxes.containsKey(tableName)) {
      return _boxes[tableName]!;
    }

    // Open box and store in cache
    final box = await _hive.openBox<Map>(_boxName(tableName));
    _boxes[tableName] = box;
    return box;
  }

  @override
  Future<List<Map<String, dynamic>>> getAll(String tableName) async {
    final box = await _getBox(tableName);

    // Convert Hive values to List<Map<String, dynamic>>
    return box.values.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  @override
  Future<Map<String, dynamic>?> getById(String tableName, String id) {
    return _getBox(tableName).then((box) {
      final rawItem = box.get(id);
      return rawItem != null ? Map<String, dynamic>.from(rawItem) : null;
    });
  }

  @override
  Future<void> insert(
    String tableName,
    Map<String, dynamic> item,
    String idField,
  ) async {
    final box = await _getBox(tableName);

    final id = item[idField] as String;
    await box.put(id, item);
  }

  @override
  Future<void> update(
    String tableName,
    String id,
    Map<String, dynamic> item,
  ) async {
    final box = await _getBox(tableName);

    await box.put(id, item);
  }

  @override
  Future<void> delete(String repositoryName, String id) async {
    final box = await _getBox(repositoryName);
    await box.delete(id);
  }

  @override
  Future<void> deleteAll(String tableName) async {
    final box = await _getBox(tableName);
    await box.clear();
  }

  @override
  Future<void> setMeta(String key, String value) async {
    if (!_initialized) {
      throw StateError(
        'HiveLocalFirstStorage not initialized. Call initialize() first.',
      );
    }
    await _metadataBox.put(key, value);
  }

  @override
  Future<String?> getMeta(String key) async {
    if (!_initialized) {
      throw StateError(
        'HiveLocalFirstStorage not initialized. Call initialize() first.',
      );
    }
    final value = _metadataBox.get(key);
    return value is String ? value : null;
  }

  @override
  Future<void> clearAllData() async {
    if (!_initialized) {
      throw StateError(
        'HiveLocalFirstStorage not initialized. Call initialize() first.',
      );
    }

    // Lista de todos os boxes para deletar
    final boxesToDelete = <String>[
      for (final entry in _boxes.keys) _boxName(entry),
    ];

    // Limpa conteúdo de todos os boxes abertos
    for (var box in _boxes.values) {
      await box.clear();
    }

    // Limpa metadata
    await _metadataBox.clear();

    // Fecha todos os boxes abertos
    for (var box in _boxes.values) {
      await box.close();
    }
    _boxes.clear();

    // Fecha metadata
    await _metadataBox.close();

    // Deleta cada box do disco individualmente (se houver)
    for (var boxName in boxesToDelete) {
      try {
        await _hive.deleteBoxFromDisk(boxName, path: customPath);
      } catch (e) {
        // Ignora erros se box não existir
      }
    }

    // Deleta metadata box do disco
    try {
      await _hive.deleteBoxFromDisk(_metadataBoxName, path: customPath);
    } catch (e) {
      // Ignora erros se box não existir
    }

    // Re-inicializa
    _initialized = false;
    await initialize();
  }

  // ============================================
  // Query Support (Otimizado para Hive)
  // ============================================

  @override
  Future<List<Map<String, dynamic>>> query(LocalFirstQuery query) async {
    if (!_initialized) {
      throw StateError(
        'HiveLocalFirstStorage not initialized. Call initialize() first.',
      );
    }

    final box = await _getBox(query.repositoryName);

    // Otimização: não carrega tudo de uma vez, itera lazy
    final results = <Map<String, dynamic>>[];

    // Coleta todos os itens que passam pelos filtros
    for (var key in box.keys) {
      final rawItem = box.get(key);
      if (rawItem == null) continue;

      // Converte Map<dynamic, dynamic> para Map<String, dynamic>
      final item = Map<String, dynamic>.from(rawItem);

      // Aplica filtros
      bool matches = true;
      for (var filter in query.filters) {
        if (!filter.matches(item)) {
          matches = false;
          break;
        }
      }

      if (matches) {
        results.add(item);
      }
    }

    // Aplica ordenação
    if (query.sorts.isNotEmpty) {
      results.sort((a, b) {
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

    // Aplica offset e limit (paginação)
    int start = query.offset ?? 0;
    int? end = query.limit != null ? start + query.limit! : null;

    if (start > 0 || end != null) {
      return results.sublist(
        start,
        end != null && end < results.length ? end : results.length,
      );
    }

    return results;
  }

  @override
  Stream<List<Map<String, dynamic>>> watchQuery(LocalFirstQuery query) {
    if (!_initialized) {
      throw StateError(
        'HiveLocalFirstStorage not initialized. Call initialize() first.',
      );
    }

    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    StreamSubscription? sub;

    Future<void> emitCurrent() async {
      try {
        final results = await this.query(query);
        controller.add(results);
      } catch (e, st) {
        controller.addError(e, st);
      }
    }

    controller.onListen = () async {
      await emitCurrent();
      final box = await _getBox(query.repositoryName);
      sub = box.watch().listen((_) => emitCurrent());
    };

    controller.onCancel = () async {
      await sub?.cancel();
    };

    return controller.stream;
  }
}
