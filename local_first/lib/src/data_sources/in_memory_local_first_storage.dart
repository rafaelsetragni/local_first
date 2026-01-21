part of '../../local_first.dart';

/// In-memory implementation of [LocalFirstStorage] for fast tests and demos.
class InMemoryLocalFirstStorage implements LocalFirstStorage {
  bool _initialized = false;

  final JsonMap<Map<String, JsonMap>> _data = {};
  final JsonMap<Map<String, JsonMap>> _events = {};
  final Map<String, String> _metadata = {};
  final JsonMap<Set<_InMemoryQueryObserver>> _observers = {};
  final JsonMap<JsonMap<LocalFieldType>> _schemas = {};

  static const Set<String> _metadataKeys = {
    LocalFirstEvent.kEventId,
    LocalFirstEvent.kDataId,
    LocalFirstEvent.kSyncStatus,
    LocalFirstEvent.kOperation,
    LocalFirstEvent.kSyncCreatedAt,
  };

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<void> close() async {
    if (!_initialized) return;
    for (final observer in _observers.values.expand((o) => o).toList()) {
      await observer.controller.close();
    }
    _observers.clear();
    _initialized = false;
  }

  @visibleForTesting
  Future<void> addClosedObserverForTest(String repositoryName) async {
    final controller =
        StreamController<List<LocalFirstEvent<dynamic>>>.broadcast();
    await controller.close();
    final observer = _InMemoryQueryObserver<dynamic>(
      emit: () async {},
      controller: controller,
    );
    _observers
        .putIfAbsent(repositoryName, () => <_InMemoryQueryObserver>{})
        .add(observer);
    await observer.emit();
  }

  @visibleForTesting
  int observerCount(String repositoryName) =>
      _observers[repositoryName]?.length ?? 0;

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'InMemoryLocalFirstStorage not initialized. Call initialize() first.',
      );
    }
  }

  Map<String, JsonMap> _tableData(String tableName) =>
      _data.putIfAbsent(tableName, () => {});

  Map<String, JsonMap> _tableEvents(String tableName) =>
      _events.putIfAbsent(tableName, () => {});

  @override
  Future<void> clearAllData() async {
    _ensureInitialized();
    final repositoriesToNotify = <String>{
      ..._data.keys,
      ..._events.keys,
      ..._observers.keys,
    };
    _data.clear();
    _events.clear();
    _metadata.clear();
    for (final repository in repositoriesToNotify) {
      await _notifyWatchers(repository);
    }
  }

  @override
  Future<void> ensureSchema(
    String tableName,
    JsonMap<LocalFieldType> schema, {
    required String idFieldName,
  }) async {
    _schemas[tableName] = Map.unmodifiable(schema);
  }

  @override
  Future<List<JsonMap>> getAll(String tableName) async {
    _ensureInitialized();
    final table = _data[tableName];
    if (table == null) return const [];

    final items = <JsonMap>[];
    for (final raw in table.values) {
      final normalized = _normalizeLegacyMap(JsonMap.from(raw));
      final merged = await _attachEventMetadata(tableName, normalized);
      if (merged[LocalFirstEvent.kOperation] == SyncOperation.delete.index) {
        continue;
      }
      items.add(merged);
    }
    return items;
  }

  @override
  Future<List<JsonMap>> getAllEvents(String tableName) async {
    _ensureInitialized();
    final events = _events[tableName];
    if (events == null) return const [];

    final dataTable = _data[tableName] ?? const {};
    final items = <JsonMap>[];
    for (final event in events.values) {
      final normalized = _normalizeLegacyMap(JsonMap.from(event));
      final dataId = normalized[LocalFirstEvent.kDataId] as String?;
      final data = dataId != null ? dataTable[dataId] : null;
      items.add(
        _mergeEventWithData(
          normalized,
          data,
          lastEventId: normalized[LocalFirstEvent.kEventId],
        ),
      );
    }
    return items;
  }

  @override
  Future<JsonMap?> getById(String tableName, String id) async {
    _ensureInitialized();
    final table = _data[tableName];
    if (table == null) return null;

    final raw = table[id];
    if (raw == null) return null;
    final merged = await _attachEventMetadata(tableName, JsonMap.from(raw));
    if (merged[LocalFirstEvent.kOperation] == SyncOperation.delete.index) {
      return null;
    }
    return merged;
  }

  @override
  Future<bool> containsId(String tableName, String id) async {
    _ensureInitialized();
    return _data[tableName]?.containsKey(id) ?? false;
  }

  @override
  Future<JsonMap?> getEventById(String tableName, String id) async {
    _ensureInitialized();
    final events = _events[tableName];
    if (events == null) return null;

    final meta = events[id];
    if (meta == null) return null;
    final dataId = meta[LocalFirstEvent.kDataId] as String?;
    final dataTable = _data[tableName];
    final data = dataId != null && dataTable != null ? dataTable[dataId] : null;
    return _mergeEventWithData(
      JsonMap.from(meta),
      data,
      lastEventId: meta[LocalFirstEvent.kEventId],
    );
  }

  @override
  Future<void> insert(String tableName, JsonMap item, String idField) async {
    _ensureInitialized();
    final normalized = _normalizeLegacyMap(JsonMap.from(item));
    final id = normalized[idField];
    if (id is! String) {
      throw ArgumentError('Item is missing string id field "$idField".');
    }

    final payload = _stripMetadata(normalized);
    final lastEventId =
        normalized[LocalFirstEvent.kLastEventId] ?? normalized['_lasteventId'];
    if (lastEventId is String) {
      payload[LocalFirstEvent.kLastEventId] = lastEventId;
    }

    _tableData(tableName)[id] = payload;
    await _notifyWatchers(tableName);
  }

  @override
  Future<void> insertEvent(
    String tableName,
    JsonMap item,
    String idField,
  ) async {
    _ensureInitialized();
    final normalized = _normalizeLegacyMap(JsonMap.from(item));
    final id = normalized[idField];
    if (id is! String) {
      throw ArgumentError('Event is missing string id field "$idField".');
    }

    final payload = _buildEventPayload(
      idField: idField,
      id: id,
      item: normalized,
    );
    _tableEvents(tableName)[id] = payload;
    await _notifyWatchers(tableName);
  }

  @override
  Future<void> update(String tableName, String id, JsonMap item) async {
    _ensureInitialized();
    final normalized = _normalizeLegacyMap(JsonMap.from(item));
    final payload = _stripMetadata(normalized);
    final lastEventId =
        normalized[LocalFirstEvent.kLastEventId] ?? normalized['_lasteventId'];
    if (lastEventId is String) {
      payload[LocalFirstEvent.kLastEventId] = lastEventId;
    }
    _tableData(tableName)[id] = payload;
    await _notifyWatchers(tableName);
  }

  @override
  Future<void> updateEvent(String tableName, String id, JsonMap item) async {
    _ensureInitialized();
    final normalized = _normalizeLegacyMap(JsonMap.from(item));
    final payload = _buildEventPayload(
      idField: LocalFirstEvent.kEventId,
      id: id,
      item: normalized,
    );
    _tableEvents(tableName)[id] = payload;
    await _notifyWatchers(tableName);
  }

  @override
  Future<void> delete(String repositoryName, String id) async {
    _ensureInitialized();
    _data[repositoryName]?.remove(id);
    await _notifyWatchers(repositoryName);
  }

  @override
  Future<void> deleteEvent(String repositoryName, String id) async {
    _ensureInitialized();
    _events[repositoryName]?.remove(id);
    await _notifyWatchers(repositoryName);
  }

  @override
  Future<void> deleteAll(String tableName) async {
    _ensureInitialized();
    _data[tableName]?.clear();
    await _notifyWatchers(tableName);
  }

  @override
  Future<void> deleteAllEvents(String tableName) async {
    _ensureInitialized();
    _events[tableName]?.clear();
    await _notifyWatchers(tableName);
  }

  @override
  Future<void> setConfigValue(String key, String value) async {
    _ensureInitialized();
    _metadata[key] = value;
  }

  @override
  Future<String?> getConfigValue(String key) async {
    _ensureInitialized();
    return _metadata[key];
  }

  @override
  Future<List<LocalFirstEvent<T>>> query<T>(LocalFirstQuery<T> query) async {
    _ensureInitialized();
    final dataTable = _data[query.repositoryName] ?? const {};
    final eventTable = _events[query.repositoryName] ?? const {};
    final repo = query.repository;

    for (final filter in query.filters) {
      if (filter.whereIn != null && filter.whereIn!.isEmpty) {
        return const [];
      }
    }

    final results = <JsonMap>[];
    for (final raw in dataTable.values) {
      final normalized = _normalizeLegacyMap(JsonMap.from(raw));
      final merged = await _attachEventMetadata(query.repositoryName, normalized);
      if (!query.includeDeleted &&
          merged[LocalFirstEvent.kOperation] == SyncOperation.delete.index) {
        continue;
      }

      var matches = true;
      for (final filter in query.filters) {
        if (!filter.matches(merged)) {
          matches = false;
          break;
        }
      }

      if (matches) {
        results.add(merged);
      }
    }

    if (query.includeDeleted) {
      for (final raw in eventTable.values) {
        final normalized = _normalizeLegacyMap(JsonMap.from(raw));
        if (!_hasRequiredEventFields(normalized)) continue;
        if (normalized[LocalFirstEvent.kOperation] !=
            SyncOperation.delete.index) {
          continue;
        }
        results.add(normalized);
      }
    }

    if (query.sorts.isNotEmpty) {
      results.sort((a, b) {
        for (final sort in query.sorts) {
          final aValue = a[sort.field];
          final bValue = b[sort.field];

          var comparison = 0;
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

    final start = query.offset ?? 0;
    final end = query.limit != null ? start + query.limit! : null;
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
        // ignore malformed entries
      }
    }
    return query.includeDeleted
        ? events
        : events.where((e) => !e.isDeleted).toList();
  }

  @override
  Stream<List<LocalFirstEvent<T>>> watchQuery<T>(LocalFirstQuery<T> query) {
    _ensureInitialized();
    final controller = StreamController<List<LocalFirstEvent<T>>>.broadcast();
    final observer = _InMemoryQueryObserver<T>(
      emit: () async {
        try {
          final results = await this.query<T>(query);
          if (!controller.isClosed) controller.add(results);
        } catch (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        }
      },
      controller: controller,
    );

    _observers
        .putIfAbsent(query.repositoryName, () => <_InMemoryQueryObserver>{})
        .add(observer);

    controller
      ..onListen = observer.emit
      ..onCancel = () {
        final observers = _observers[query.repositoryName];
        observers?.remove(observer);
        if (observers != null && observers.isEmpty) {
          _observers.remove(query.repositoryName);
        }
      };

    return controller.stream;
  }

  Future<void> _notifyWatchers(String repositoryName) async {
    final observers = _observers[repositoryName];
    if (observers == null || observers.isEmpty) return;

    for (final observer in List.of(observers)) {
      if (observer.controller.isClosed) {
        observers.remove(observer);
        continue;
      }
      await observer.emit();
    }
  }

  JsonMap _stripMetadata(JsonMap source) {
    final copy = JsonMap.from(source);
    copy.removeWhere((key, _) => _metadataKeys.contains(key));
    return copy;
  }

  JsonMap _buildEventPayload({
    required String idField,
    required String id,
    required JsonMap item,
  }) {
    final payload = JsonMap.from(item);
    payload[LocalFirstEvent.kEventId] = id;
    payload.putIfAbsent(
      LocalFirstEvent.kDataId,
      () => payload[LocalFirstEvent.kDataId] ??
          payload['dataId'] ??
          payload[idField],
    );
    return payload;
  }

  Future<JsonMap> _attachEventMetadata(String tableName, JsonMap data) async {
    final merged = JsonMap.from(data);
    final lastEventId = data[LocalFirstEvent.kLastEventId];
    if (lastEventId is! String) return merged;

    final eventTable = _events[tableName];
    final meta = eventTable != null ? eventTable[lastEventId] : null;
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

  bool _hasRequiredEventFields(JsonMap json) {
    return json.containsKey(LocalFirstEvent.kEventId) &&
        json.containsKey(LocalFirstEvent.kSyncStatus) &&
        json.containsKey(LocalFirstEvent.kOperation) &&
        json.containsKey(LocalFirstEvent.kSyncCreatedAt);
  }
}

class _InMemoryQueryObserver<T> {
  _InMemoryQueryObserver({
    required this.emit,
    required this.controller,
  });

  final Future<void> Function() emit;
  final StreamController<List<LocalFirstEvent<T>>> controller;
}
