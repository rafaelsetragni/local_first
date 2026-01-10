// ignore_for_file: unused_import

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:local_first/local_first.dart';
import 'package:path/path.dart' as p;

/// Implementation of [LocalFirstStorage] using Hive CE.
///
/// Features:
/// - Stores data as JSON in Hive boxes
/// - Each table is a separate box (state and events) under a namespace-specific
///   directory
/// - Metadata (lastSyncAt) is stored in dedicated box
/// - Operations are fast and completely offline
/// - Supports reactive queries with box.watch()
class HiveLocalFirstStorage implements LocalFirstStorage {
  /// Boxes for each table (lazy-loaded)
  final Map<String, BoxBase<Map<dynamic, dynamic>>> _boxes = {};

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
  final Future<void> Function([String? subDir]) _initFlutter;
  final Set<String> _lazyCollections;

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
    Future<void> Function([String? subDir])? initFlutter,
    Set<String> lazyCollections = const {},
  }) : _namespace = namespace ?? 'default',
       _hive = hive ?? Hive,
       _initFlutter = initFlutter ?? Hive.initFlutter,
       _lazyCollections = lazyCollections;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    // Initialize Hive
    if (customPath != null) {
      _hive.init(p.join(customPath!, _namespace));
    } else {
      await _initFlutter(_namespace);
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

    await close();
    await initialize();
  }

  Future<void> _closeAllBoxes() async {
    for (var box in _boxes.values) {
      await box.close();
    }
    _boxes.clear();
  }

  String get _metadataBoxName => 'offline_metadata';

  String _boxName(String tableName, {bool isEvent = false}) {
    return isEvent ? '${tableName}__events' : tableName;
  }

  String _boxCacheKey(String tableName, {bool isEvent = false}) {
    return '${isEvent ? 'events' : 'state'}::$tableName';
  }

  /// Gets or creates a box for the table.
  Future<BoxBase<Map<dynamic, dynamic>>> _getBox(
    String tableName, {
    bool isEvent = false,
  }) async {
    if (!_initialized) {
      throw StateError(
        'HiveLocalFirstStorage not initialized. Call initialize() first.',
      );
    }

    final cacheKey = _boxCacheKey(tableName, isEvent: isEvent);
    if (_boxes.containsKey(cacheKey)) {
      return _boxes[cacheKey]!;
    }

    final resolvedName = _boxName(tableName, isEvent: isEvent);
    // Open box and store in cache
    final bool useLazy = !isEvent && _lazyCollections.contains(tableName);
    final box = useLazy
        ? await _hive.openLazyBox<Map>(resolvedName)
        : await _hive.openBox<Map>(resolvedName);
    _boxes[cacheKey] = box;
    return box;
  }

  @override
  Future<List<Map<String, dynamic>>> getAll(String tableName) async {
    final box = await _getBox(tableName);

    if (box is LazyBox<Map>) {
      final keys = box.keys.cast<String>();
      final List<Map<String, dynamic>> items = [];
      for (final key in keys) {
        final raw = await box.get(key);
        if (raw != null) {
          items.add(Map<String, dynamic>.from(raw));
        }
      }
      return items;
    }

    // Convert Hive values to List<Map<String, dynamic>>
    return (box as Box<Map<dynamic, dynamic>>).values
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getAllEvents(String tableName) async {
    final box = await _getBox(tableName, isEvent: true);

    if (box is LazyBox<Map>) {
      final keys = box.keys.cast<String>();
      final List<Map<String, dynamic>> items = [];
      for (final key in keys) {
        final raw = await box.get(key);
        if (raw != null) {
          items.add(Map<String, dynamic>.from(raw));
        }
      }
      return items;
    }

    return (box as Box<Map<dynamic, dynamic>>).values
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  @override
  Future<Map<String, dynamic>?> getById(String tableName, String id) {
    return _getBox(tableName).then((box) async {
      if (box is LazyBox<Map>) {
        final rawItem = await box.get(id);
        return rawItem != null ? Map<String, dynamic>.from(rawItem) : null;
      }
      final rawItem = (box as Box<Map<dynamic, dynamic>>).get(id);
      return rawItem != null ? Map<String, dynamic>.from(rawItem) : null;
    });
  }

  @override
  Future<Map<String, dynamic>?> getEventById(String tableName, String id) {
    return _getBox(tableName, isEvent: true).then((box) async {
      if (box is LazyBox<Map>) {
        final rawItem = await box.get(id);
        return rawItem != null ? Map<String, dynamic>.from(rawItem) : null;
      }
      final rawItem = (box as Box<Map<dynamic, dynamic>>).get(id);
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
  Future<void> insertEvent(
    String tableName,
    Map<String, dynamic> item,
    String idField,
  ) async {
    final box = await _getBox(tableName, isEvent: true);

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
  Future<void> updateEvent(
    String tableName,
    String id,
    Map<String, dynamic> item,
  ) async {
    final box = await _getBox(tableName, isEvent: true);

    await box.put(id, item);
  }

  @override
  Future<void> delete(String repositoryName, String id) async {
    final box = await _getBox(repositoryName);
    await box.delete(id);
  }

  @override
  Future<void> deleteEvent(String repositoryName, String id) async {
    final box = await _getBox(repositoryName, isEvent: true);
    await box.delete(id);
  }

  @override
  Future<void> deleteAll(String tableName) async {
    final box = await _getBox(tableName);
    await box.clear();
  }

  @override
  Future<void> deleteAllEvents(String tableName) async {
    final box = await _getBox(tableName, isEvent: true);
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
  Future<void> ensureSchema(
    String tableName,
    Map<String, LocalFieldType> schema, {
    required String idFieldName,
  }) async {
    // Hive stores Map payloads; no schema enforcement required.
    return;
  }

  @override
  Future<void> clearAllData() async {
    if (!_initialized) {
      throw StateError(
        'HiveLocalFirstStorage not initialized. Call initialize() first.',
      );
    }

    // List all boxes to delete
    final boxesToDelete = <String>[for (final box in _boxes.values) box.name];

    // Clear contents of all open boxes
    for (var box in _boxes.values) {
      await box.clear();
    }

    // Clear metadata
    await _metadataBox.clear();

    // Close all open boxes
    for (var box in _boxes.values) {
      await box.close();
    }
    _boxes.clear();

    // Close metadata box
    await _metadataBox.close();

    // Delete each box from disk individually (if present)
    for (var boxName in boxesToDelete) {
      try {
        await _hive.deleteBoxFromDisk(boxName);
      } catch (e) {
        // Ignore errors if the box does not exist
      }
    }

    // Delete metadata box from disk
    try {
      await _hive.deleteBoxFromDisk(_metadataBoxName);
    } catch (e) {
      // Ignore errors if the box does not exist
    }

    // Re-initialize
    _initialized = false;
    await initialize();
  }

  // ============================================
  // Query Support (optimized for Hive)
  // ============================================

  @override
  Future<List<Map<String, dynamic>>> query(LocalFirstQuery query) async {
    if (!_initialized) {
      throw StateError(
        'HiveLocalFirstStorage not initialized. Call initialize() first.',
      );
    }

    final box = await _getBox(query.repositoryName);

    // Optimization: iterate lazily instead of loading everything at once
    final results = <Map<String, dynamic>>[];

    // Collect items that match filters
    for (var key in box.keys) {
      final rawItem = box is LazyBox<Map>
          ? await box.get(key)
          : (box as Box<Map<dynamic, dynamic>>).get(key);
      if (rawItem == null) continue;

      // Convert Map<dynamic, dynamic> to Map<String, dynamic>
      final item = Map<String, dynamic>.from(rawItem);

      // Apply filters
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

    // Apply sorting
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

    // Apply offset and limit (pagination)
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
