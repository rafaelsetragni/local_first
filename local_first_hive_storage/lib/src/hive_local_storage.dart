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
  final JsonMap<BoxBase<Map<dynamic, dynamic>>> _boxes = {};

  /// Box for sync metadata
  late Box<dynamic> _metadataBox;

  /// Initialization control flag
  bool _initialized = false;

  /// Custom path (useful for testing)
  final String? customPath;

  /// Namespace used to isolate data per user/session.
  String _namespace;

  /// Current namespace that scopes box directories.
  String get namespace => _namespace;

  final HiveInterface _hive;
  final Future<void> Function([String? subDir]) _initFlutter;
  final Set<String> _lazyCollections;

  static const Set<String> _metadataKeys = {
    LocalFirstEvent.kEventId,
    LocalFirstEvent.kDataId,
    LocalFirstEvent.kSyncStatus,
    LocalFirstEvent.kOperation,
    LocalFirstEvent.kSyncCreatedAt,
  };

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

  /// Opens Hive boxes for the current namespace so reads/writes can start.
  ///
  /// Throws [StateError] if initialization fails.
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

  /// Closes all opened Hive boxes and resets state.
  @override
  Future<void> close() async {
    if (!_initialized) return;

    await _closeAllBoxes();
    await _metadataBox.close();

    _initialized = false;
  }

  /// Changes the active namespace, closing any open boxes.
  /// Switches to a different namespace, reopening boxes so each user/session
  /// gets its own set of Hive boxes.
  ///
  /// - [namespace]: Logical bucket name (for example, a user id).
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<void> useNamespace(String namespace) async {
    if (_namespace == namespace) return;
    _namespace = namespace;

    if (!_initialized) return;

    await close();
    await initialize();
  }

  Future<void> _closeAllBoxes() async {
    for (var box in _boxes.values.toList()) {
      try {
        await box.close();
      } catch (_) {
        // Ignore close errors to keep shutdown robust (tests may delete temp dirs).
        continue;
      }
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

  @visibleForTesting
  void addBoxToCacheForTest(
    String tableName,
    BoxBase<Map<dynamic, dynamic>> box, {
    bool isEvent = false,
  }) {
    _boxes[_boxCacheKey(tableName, isEvent: isEvent)] = box;
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

  /// Returns all non-deleted records for the given table.
  ///
  /// - [tableName]: Repository name to read from.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<List<JsonMap>> getAll(String tableName) async {
    final box = await _getBox(tableName);
    final keys = box.keys.cast<String>();
    final List<JsonMap> items = [];
    for (final key in keys) {
      final raw = await _readBoxValue(box, key);
      if (raw == null) continue;
      final merged = await _attachEventMetadata(tableName, raw);
      if (merged['operation'] == SyncOperation.delete.index) continue;
      items.add(merged);
    }
    return items;
  }

  /// Returns all events, merged with their associated state data.
  ///
  /// - [tableName]: Repository name to read from.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<List<JsonMap>> getAllEvents(String tableName) async {
    final eventBox = await _getBox(tableName, isEvent: true);
    final dataBox = await _getBox(tableName);
    final keys = eventBox.keys.cast<String>();
    final List<JsonMap> items = [];
    for (final key in keys) {
      final meta = await _readBoxValue(eventBox, key);
      if (meta == null) continue;
      final dataId = meta['dataId'] as String?;
      final data = dataId != null ? await _readBoxValue(dataBox, dataId) : null;
      items.add(_mergeEventWithData(meta, data, lastEventId: meta['eventId']));
    }
    return items;
  }

  /// Fetches a record by id, excluding tombstoned entries.
  ///
  /// - [tableName]: Repository name to read from.
  /// - [id]: Record id.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<JsonMap?> getById(String tableName, String id) {
    return _getBox(tableName).then((box) async {
      final rawItem = await _readBoxValue(box, id);
      if (rawItem == null) return null;
      final merged = await _attachEventMetadata(tableName, rawItem);
      if (merged['operation'] == SyncOperation.delete.index) return null;
      return merged;
    });
  }

  /// Fetches an event by id merged with its data payload.
  ///
  /// - [tableName]: Repository name to read from.
  /// - [id]: Event id.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<JsonMap?> getEventById(String tableName, String id) {
    return _getBox(tableName, isEvent: true).then((eventBox) async {
      final meta = await _readBoxValue(eventBox, id);
      if (meta == null) return null;
      final dataId = meta['dataId'] as String?;
      final dataBox = await _getBox(tableName);
      final data = dataId != null ? await _readBoxValue(dataBox, dataId) : null;
      return _mergeEventWithData(meta, data, lastEventId: meta['eventId']);
    });
  }

  /// Inserts or replaces a record in the state box.
  ///
  /// - [tableName]: Repository name to write to.
  /// - [item]: Record payload including metadata.
  /// - [idField]: Field used as primary key.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<void> insert(String tableName, JsonMap item, String idField) async {
    final box = await _getBox(tableName);

    final id = item[idField] as String;
    final payload = _stripMetadata(item);
    final lastEventId = item[LocalFirstEvent.kLastEventId];
    if (lastEventId is String) {
      payload[LocalFirstEvent.kLastEventId] = lastEventId;
    }
    await box.put(id, payload);
  }

  /// Inserts or replaces an event in the event box.
  ///
  /// - [tableName]: Repository name to write to.
  /// - [item]: Event payload including metadata.
  /// - [idField]: Field used as event id.
  ///
  /// Throws [StateError] if called before [initialize]. Throws [ArgumentError]
  /// if the payload is missing a valid id.
  @override
  Future<void> insertEvent(
    String tableName,
    JsonMap item,
    String idField,
  ) async {
    final box = await _getBox(tableName, isEvent: true);

    final id = item[idField] as String;
    final meta = {
      'eventId': id,
      'dataId': item['dataId'],
      'syncStatus': item['syncStatus'],
      'operation': item['operation'],
      'createdAt': item['createdAt'],
    };
    await box.put(id, meta);
  }

  /// Updates an existing record payload.
  ///
  /// - [tableName]: Repository name to write to.
  /// - [id]: Record id.
  /// - [item]: Updated payload.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<void> update(String tableName, String id, JsonMap item) async {
    final box = await _getBox(tableName);

    final payload = _stripMetadata(item);
    final lastEventId = item['_lasteventId'];
    if (lastEventId is String) {
      payload['_lasteventId'] = lastEventId;
    }
    await box.put(id, payload);
  }

  /// Updates an existing event payload.
  ///
  /// - [tableName]: Repository name to write to.
  /// - [id]: Event id.
  /// - [item]: Updated payload.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<void> updateEvent(String tableName, String id, JsonMap item) async {
    final box = await _getBox(tableName, isEvent: true);

    final meta = {
      'eventId': id,
      'dataId': item['dataId'] ?? id,
      'syncStatus': item['syncStatus'],
      'operation': item['operation'],
      'createdAt': item['createdAt'],
    };
    await box.put(id, meta);
  }

  /// Deletes a record from the state box.
  ///
  /// - [repositoryName]: Repository name whose record should be removed.
  /// - [id]: Record id.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<void> delete(String repositoryName, String id) async {
    final box = await _getBox(repositoryName);
    await box.delete(id);
  }

  /// Deletes a stored event.
  ///
  /// - [repositoryName]: Repository name whose event should be removed.
  /// - [id]: Event id.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<void> deleteEvent(String repositoryName, String id) async {
    final box = await _getBox(repositoryName, isEvent: true);
    await box.delete(id);
  }

  /// Clears all records for the specified table.
  ///
  /// - [tableName]: Repository name whose records should be dropped.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<void> deleteAll(String tableName) async {
    final box = await _getBox(tableName);
    await box.clear();
  }

  /// Clears all events for the specified table.
  ///
  /// - [tableName]: Repository name whose events should be dropped.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<void> deleteAllEvents(String tableName) async {
    final box = await _getBox(tableName, isEvent: true);
    await box.clear();
  }

  bool _isSupportedConfigValue(Object value) {
    if (value is bool || value is int || value is double || value is String) {
      return true;
    }
    if (value is List && value.every((e) => e is String)) return true;
    return false;
  }

  /// Returns whether a config key is present in Hive metadata.
  ///
  /// - [key]: Config key to check.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<bool> containsConfigKey(String key) async {
    if (!_initialized) {
      throw StateError(
        'HiveLocalFirstStorage not initialized. Call initialize() first.',
      );
    }
    return _metadataBox.containsKey(key);
  }

  /// Stores a config value in Hive metadata.
  ///
  /// - [key]: Config key to write.
  /// - [value]: Allowed types: bool, int, double, String or List<String>.
  ///
  /// Throws [StateError] if called before [initialize]. Throws [ArgumentError]
  /// when the value type is unsupported.
  @override
  Future<bool> setConfigValue<T>(String key, T value) async {
    if (!_initialized) {
      throw StateError(
        'HiveLocalFirstStorage not initialized. Call initialize() first.',
      );
    }
    if (value is! Object || !_isSupportedConfigValue(value)) {
      throw ArgumentError(
        'Unsupported config value type ${value.runtimeType}. '
        'Allowed: bool, int, double, String, List<String>.',
      );
    }
    await _metadataBox.put(
      key,
      value is List ? List<String>.from(value) : value,
    );
    return true;
  }

  /// Reads a config value from Hive metadata using the requested type.
  ///
  /// - [key]: Config key to read.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<T?> getConfigValue<T>(String key) async {
    if (!_initialized) {
      throw StateError(
        'HiveLocalFirstStorage not initialized. Call initialize() first.',
      );
    }
    final value = _metadataBox.get(key);
    if (value == null) return null;
    if (T == dynamic) return value as T;
    if (!_isSupportedConfigValue(value)) return null;
    if (value is List<String>) {
      if (value is T) return value as T;
      return null;
    }
    if (value is T) return value;
    return null;
  }

  /// Removes a namespaced config entry.
  ///
  /// - [key]: Config key to remove.
  @override
  Future<bool> removeConfig(String key) async {
    if (!_initialized) {
      throw StateError(
        'HiveLocalFirstStorage not initialized. Call initialize() first.',
      );
    }
    await _metadataBox.delete(key);
    return true;
  }

  /// Clears all config metadata stored in Hive.
  @override
  Future<bool> clearConfig() async {
    if (!_initialized) {
      throw StateError(
        'HiveLocalFirstStorage not initialized. Call initialize() first.',
      );
    }
    await _metadataBox.clear();
    return true;
  }

  /// Lists config keys currently stored in the metadata box.
  @override
  Future<Set<String>> getConfigKeys() async {
    if (!_initialized) {
      throw StateError(
        'HiveLocalFirstStorage not initialized. Call initialize() first.',
      );
    }
    return _metadataBox.keys.cast<String>().toSet();
  }

  /// Returns whether the state box contains the given id.
  @override
  Future<bool> containsId(String tableName, String id) async {
    final box = await _getBox(tableName);
    return box.containsKey(id);
  }

  /// Ensures schema compatibility; Hive stores maps so no-op here.
  ///
  /// - [tableName]: Repository name.
  /// - [schema]: Column types keyed by field.
  /// - [idFieldName]: Primary key field name.
  @override
  Future<void> ensureSchema(
    String tableName,
    JsonMap<LocalFieldType> schema, {
    required String idFieldName,
  }) async {
    // Hive stores Map payloads; no schema enforcement required.
    return;
  }

  /// Deletes all boxes and metadata for the current namespace, then
  /// reinitializes the namespace so it is empty and ready to use.
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

  JsonMap _stripMetadata(JsonMap source) {
    final copy = JsonMap.from(source);
    copy.removeWhere((key, _) => _metadataKeys.contains(key));
    return copy;
  }

  Future<JsonMap?> _readBoxValue(
    BoxBase<Map<dynamic, dynamic>> box,
    String key,
  ) async {
    final raw = box is LazyBox<Map>
        ? await box.get(key)
        : (box as Box<Map<dynamic, dynamic>>).get(key);
    if (raw == null) return null;
    return _normalizeLegacyMap(JsonMap.from(raw));
  }

  Future<JsonMap> _attachEventMetadata(String tableName, JsonMap data) async {
    final merged = JsonMap.from(data);
    final lastEventId = data[LocalFirstEvent.kLastEventId];
    if (lastEventId is! String) return merged;

    final eventBox = await _getBox(tableName, isEvent: true);
    final meta = await _readBoxValue(eventBox, lastEventId);
    if (meta != null) {
      merged.addAll(meta);
    }
    merged[LocalFirstEvent.kLastEventId] = lastEventId;
    return merged;
  }

  JsonMap _mergeEventWithData(
    JsonMap meta,
    JsonMap? data, {
    Object? lastEventId,
  }) {
    final merged = <String, dynamic>{if (data != null) ...data, ...meta};
    final dataId = meta[LocalFirstEvent.kDataId];
    if (dataId is String) {
      merged.putIfAbsent('id', () => dataId);
    }
    if (lastEventId is String) {
      merged[LocalFirstEvent.kLastEventId] = lastEventId;
    }
    return merged;
  }

  JsonMap _normalizeLegacyMap(JsonMap map) {
    final normalized = JsonMap.from(map);
    final legacyToNew = {
      '_event_id': LocalFirstEvent.kEventId,
      '_data_id': LocalFirstEvent.kDataId,
      '_sync_status': LocalFirstEvent.kSyncStatus,
      '_sync_operation': LocalFirstEvent.kOperation,
      '_sync_created_at': LocalFirstEvent.kSyncCreatedAt,
      '_last_event_id': LocalFirstEvent.kLastEventId,
      '_lasteventId': LocalFirstEvent.kLastEventId,
    };
    for (final entry in legacyToNew.entries) {
      if (normalized.containsKey(entry.key)) {
        normalized[entry.value] = normalized.remove(entry.key);
      }
    }
    return normalized;
  }

  // ============================================
  // Query Support (optimized for Hive)
  // ============================================

  /// Executes a query against Hive data with in-memory filtering.
  ///
  /// - [query]: Query definition including filters, sorts and pagination.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<List<LocalFirstEvent<T>>> query<T>(LocalFirstQuery<T> query) async {
    if (!_initialized) {
      throw StateError(
        'HiveLocalFirstStorage not initialized. Call initialize() first.',
      );
    }

    final box = await _getBox(query.repositoryName);
    final eventBox = await _getBox(query.repositoryName, isEvent: true);
    final repo = query.repository;

    // Optimization: iterate lazily instead of loading everything at once
    final results = <JsonMap>[];

    // Collect items that match filters
    for (var key in box.keys) {
      final rawItem = await _readBoxValue(box, key);
      if (rawItem == null) continue;

      final item = await _attachEventMetadata(query.repositoryName, rawItem);
      if (!query.includeDeleted &&
          item['operation'] == SyncOperation.delete.index) {
        continue;
      }

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

    // When including deletes, also surface delete events (even if data row still exists).
    if (query.includeDeleted) {
      for (var key in eventBox.keys) {
        final rawEvent = await _readBoxValue(eventBox, key);
        if (rawEvent == null) continue;
        if (!_hasRequiredEventFields(rawEvent)) continue;
        if (rawEvent['operation'] != SyncOperation.delete.index) continue;
        results.add(rawEvent);
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

    final sliced = (start > 0 || end != null)
        ? results.sublist(
            start,
            end != null && end < results.length ? end : results.length,
          )
        : results;

    final events = <LocalFirstEvent<T>>[];
    for (final json in sliced) {
      if (!_hasRequiredEventFields(json)) continue;
      try {
        events.add(
          LocalFirstEvent.fromLocalStorage(repository: repo, json: json),
        );
      } catch (_) {
        // ignore malformed legacy entries
      }
    }
    return query.includeDeleted
        ? events
        : events.where((e) => !e.isDeleted).toList();
  }

  /// Watches a query and emits updates when underlying boxes change.
  ///
  /// - [query]: Query definition to observe.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Stream<List<LocalFirstEvent<T>>> watchQuery<T>(LocalFirstQuery<T> query) {
    if (!_initialized) {
      throw StateError(
        'HiveLocalFirstStorage not initialized. Call initialize() first.',
      );
    }

    final controller = StreamController<List<LocalFirstEvent<T>>>.broadcast();
    StreamSubscription? dataSub;
    StreamSubscription? eventSub;

    Future<void> emitCurrent() async {
      try {
        final results = await this.query<T>(query);
        controller.add(results);
      } catch (e, st) {
        controller.addError(e, st);
      }
    }

    controller.onListen = () async {
      try {
        await emitCurrent();
        final box = await _getBox(query.repositoryName);
        final eventBox = await _getBox(query.repositoryName, isEvent: true);
        dataSub = box.watch().listen((_) => emitCurrent());
        eventSub = eventBox.watch().listen((_) => emitCurrent());
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
      }
    };

    controller.onCancel = () async {
      await dataSub?.cancel();
      await eventSub?.cancel();
    };

    return controller.stream;
  }

  bool _hasRequiredEventFields(JsonMap json) {
    return json.containsKey(LocalFirstEvent.kEventId) &&
        json.containsKey(LocalFirstEvent.kSyncStatus) &&
        json.containsKey(LocalFirstEvent.kOperation) &&
        json.containsKey(LocalFirstEvent.kSyncCreatedAt);
  }
}
