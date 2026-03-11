part of '../../local_first.dart';

/// In-memory implementation of [LocalFirstStorage] for fast tests and demos.
class InMemoryLocalFirstStorage implements LocalFirstStorage {
  bool _initialized = false;

  String _namespace = 'default';

  final Map<String, JsonMap<Map<String, JsonMap>>> _dataByNamespace = {};
  final Map<String, JsonMap<Map<String, JsonMap>>> _eventsByNamespace = {};
  final Map<String, Map<String, Object>> _metadataByNamespace = {};
  final Map<String, JsonMap<Set<_InMemoryQueryObserver>>>
  _observersByNamespace = {};
  final Map<String, JsonMap<JsonMap<LocalFieldType>>> _schemasByNamespace = {};

  JsonMap<Map<String, JsonMap>> get _data =>
      _dataByNamespace.putIfAbsent(_namespace, () => {});
  JsonMap<Map<String, JsonMap>> get _events =>
      _eventsByNamespace.putIfAbsent(_namespace, () => {});
  Map<String, Object> get _metadata =>
      _metadataByNamespace.putIfAbsent(_namespace, () => {});
  JsonMap<Set<_InMemoryQueryObserver>> get _observers =>
      _observersByNamespace.putIfAbsent(_namespace, () => {});
  JsonMap<JsonMap<LocalFieldType>> get _schemas =>
      _schemasByNamespace.putIfAbsent(_namespace, () => {});

  static const Set<String> _metadataKeys = {
    LocalFirstEvent.kEventId,
    LocalFirstEvent.kDataId,
    LocalFirstEvent.kSyncStatus,
    LocalFirstEvent.kOperation,
    LocalFirstEvent.kSyncCreatedAt,
  };

  /// Marks this in-memory storage as initialized.
  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  /// Tears down the storage, closing watchers and clearing initialization flag.
  ///
  /// If [preserveObservers] is true, observers are kept alive so they can
  /// continue receiving updates after a namespace change.
  @override
  Future<void> close({bool preserveObservers = false}) async {
    if (!_initialized) return;
    if (!preserveObservers) {
      for (final observerSet in _observersByNamespace.values) {
        for (final observer in observerSet.values.expand((o) => o).toList()) {
          await observer.controller.close();
        }
        observerSet.clear();
      }
    }
    _initialized = false;
  }

  /// Switches the active namespace, reinitializing internal data so each
  /// tenant/user gets isolated state.
  ///
  /// Observers are preserved across namespace changes. After switching,
  /// all active observers will re-emit their query results with data
  /// from the new namespace.
  ///
  /// - [namespace]: Logical bucket name (for example, a user id).
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<void> useNamespace(String namespace) async {
    if (_namespace == namespace) return;

    // Preserve observers across namespace change
    await close(preserveObservers: true);
    _namespace = namespace;
    await initialize();

    // Re-emit results to all active observers with data from the new namespace
    for (final repositoryName in _observers.keys.toList()) {
      await _notifyWatchers(repositoryName);
    }
  }

  @visibleForTesting
  /// Adds a closed watcher to simulate a disposed stream during tests.
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
  /// Number of active observers for a repository, useful in tests.
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

  /// Removes all data, events and metadata for the current namespace to reset
  /// the in-memory database.
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

  /// Stores schema metadata; helpful when tests emulate SQL-like validation.
  ///
  /// - [tableName]: Repository name this schema belongs to.
  /// - [schema]: Column types keyed by field, used by backends that validate.
  /// - [idFieldName]: Primary key field name for the repository.
  @override
  Future<void> ensureSchema(
    String tableName,
    JsonMap<LocalFieldType> schema, {
    required String idFieldName,
  }) async {
    _schemas[tableName] = Map.unmodifiable(schema);
  }

  /// Returns all non-deleted records for a repository.
  ///
  /// - [tableName]: Repository name to query.
  ///
  /// Throws [StateError] if called before [initialize].
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

  /// Returns all events for a repository merged with their latest state.
  ///
  /// - [tableName]: Repository name to query.
  ///
  /// Throws [StateError] if called before [initialize].
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

  /// Returns a record by id if it exists and is not marked as deleted.
  ///
  /// - [tableName]: Repository name.
  /// - [id]: Record id.
  ///
  /// Throws [StateError] if called before [initialize].
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

  /// Returns whether a record id exists in the state table.
  ///
  /// - [tableName]: Repository name.
  /// - [id]: Record id.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<bool> containsId(String tableName, String id) async {
    _ensureInitialized();
    return _data[tableName]?.containsKey(id) ?? false;
  }

  /// Returns an event by id merged with its associated state data.
  ///
  /// - [tableName]: Repository name.
  /// - [id]: Event id.
  ///
  /// Throws [StateError] if called before [initialize].
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

  /// Inserts a record into the state table and notifies watchers.
  ///
  /// - [tableName]: Repository name.
  /// - [item]: Record payload including metadata.
  /// - [idField]: Field name used as primary key.
  ///
  /// Throws [StateError] if called before [initialize]. Throws [ArgumentError]
  /// if the payload is missing a valid id.
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

  /// Inserts an event for a record and triggers watcher updates.
  ///
  /// - [tableName]: Repository name.
  /// - [item]: Event payload including metadata.
  /// - [idField]: Field name used as event id.
  ///
  /// Throws [StateError] if called before [initialize]. Throws [ArgumentError]
  /// if the payload is missing a valid id.
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

  /// Updates an existing record and notifies watchers.
  ///
  /// - [tableName]: Repository name.
  /// - [id]: Record id.
  /// - [item]: Updated payload including metadata.
  ///
  /// Throws [StateError] if called before [initialize].
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

  /// Updates an existing event entry.
  ///
  /// - [tableName]: Repository name.
  /// - [id]: Event id.
  /// - [item]: Updated payload including metadata.
  ///
  /// Throws [StateError] if called before [initialize].
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

  /// Deletes a record and notifies watchers.
  ///
  /// - [repositoryName]: Repository name.
  /// - [id]: Record id to delete.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<void> delete(String repositoryName, String id) async {
    _ensureInitialized();
    _data[repositoryName]?.remove(id);
    await _notifyWatchers(repositoryName);
  }

  /// Deletes a single event and notifies watchers.
  ///
  /// - [repositoryName]: Repository name.
  /// - [id]: Event id to delete.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<void> deleteEvent(String repositoryName, String id) async {
    _ensureInitialized();
    _events[repositoryName]?.remove(id);
    await _notifyWatchers(repositoryName);
  }

  /// Clears all records for the repository.
  ///
  /// - [tableName]: Repository name whose records should be dropped.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<void> deleteAll(String tableName) async {
    _ensureInitialized();
    _data[tableName]?.clear();
    await _notifyWatchers(tableName);
  }

  /// Clears all events for the repository.
  ///
  /// - [tableName]: Repository name whose events should be dropped.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<void> deleteAllEvents(String tableName) async {
    _ensureInitialized();
    _events[tableName]?.clear();
    await _notifyWatchers(tableName);
  }

  bool _isSupportedConfigValue(Object value) {
    if (value is bool || value is int || value is double || value is String) {
      return true;
    }
    if (value is List<String>) return true;
    if (value is List && value.every((e) => e is String)) return true;
    return false;
  }

  /// Returns whether a config key exists in the current namespace.
  ///
  /// - [key]: Config key to check. Namespacing is handled internally.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<bool> containsConfigKey(String key) async {
    _ensureInitialized();
    return _metadata.containsKey(key);
  }

  /// Stores a config value in memory.
  ///
  /// - [key]: Config key to write. Namespacing is handled internally.
  /// - [value]: Allowed types: bool, int, double, String or `List<String>`.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<bool> setConfigValue<T>(String key, T value) async {
    _ensureInitialized();
    if (value is! Object || !_isSupportedConfigValue(value)) {
      throw ArgumentError(
        'Unsupported config value type ${value.runtimeType}. '
        'Allowed: bool, int, double, String, List<String>.',
      );
    }
    _metadata[key] = value is List ? List<String>.from(value) : value;
    return true;
  }

  /// Reads a config value using the provided generic type.
  ///
  /// - [key]: Config key to read. Namespacing is handled internally.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<T?> getConfigValue<T>(String key) async {
    _ensureInitialized();
    final value = _metadata[key];
    if (value == null) return null;
    if (T == dynamic) return value as T;
    if (value is List<String>) {
      if (value is T) return value as T;
      return null;
    }
    if (value is T) return value as T;
    return null;
  }

  /// Removes a config entry from the current namespace.
  ///
  /// - [key]: Config key to remove. Namespacing is handled internally.
  ///
  /// Throws [StateError] if called before [initialize].
  @override
  Future<bool> removeConfig(String key) async {
    _ensureInitialized();
    _metadata.remove(key);
    return true;
  }

  /// Clears all config metadata for the current namespace.
  @override
  Future<bool> clearConfig() async {
    _ensureInitialized();
    _metadata.clear();
    return true;
  }

  /// Lists config keys stored in the current namespace.
  @override
  Future<Set<String>> getConfigKeys() async {
    _ensureInitialized();
    return _metadata.keys.toSet();
  }

  /// Executes an in-memory query with filtering, sorting and pagination.
  ///
  /// Useful for tests and quick demos without a real database. Throws
  /// [StateError] if called before [initialize].
  ///
  /// - [query]: Query definition including filters, sorts and pagination.
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
      final merged = await _attachEventMetadata(
        query.repositoryName,
        normalized,
      );
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

  /// Watches a query and emits updates whenever data changes, mimicking a
  /// reactive database stream.
  ///
  /// - [query]: Query definition to observe.
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
      () =>
          payload[LocalFirstEvent.kDataId] ??
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
  _InMemoryQueryObserver({required this.emit, required this.controller});

  final Future<void> Function() emit;
  final StreamController<List<LocalFirstEvent<T>>> controller;
}
