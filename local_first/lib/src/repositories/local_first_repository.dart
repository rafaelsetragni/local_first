part of '../../local_first.dart';

/// Convenience alias for lists of events.
typedef LocalFirstEvents<T> = List<LocalFirstEvent<T>>;
typedef LocalFirstEventsDynamic = List<LocalFirstEvent>;

/// Repository responsible for persisting domain objects and emitting events.
class LocalFirstRepository<T extends Object> {
  LocalFirstRepository._({
    required this.name,
    required this.getId,
    required this.toJson,
    required this.fromJson,
    required this.onConflict,
    required this.schema,
    required this.idFieldName,
  });

  factory LocalFirstRepository.create({
    required String name,
    required String Function(T model) getId,
    required Map<String, dynamic> Function(T model) toJson,
    required T Function(Map<String, dynamic> json) fromJson,
    required T Function(T local, T remote) onConflict,
    Map<String, LocalFieldType> schema = const {},
    String idFieldName = 'id',
  }) {
    return LocalFirstRepository._(
      name: name,
      getId: getId,
      toJson: toJson,
      fromJson: fromJson,
      onConflict: onConflict,
      schema: schema,
      idFieldName: idFieldName,
    );
  }

  final String name;
  final String Function(T model) getId;
  final Map<String, dynamic> Function(T model) toJson;
  final T Function(Map<String, dynamic> json) fromJson;
  final T Function(T local, T remote) onConflict;
  final Map<String, LocalFieldType> schema;
  final String idFieldName;

  LocalFirstClient? _client;
  List<DataSyncStrategy> _syncStrategies = [];
  bool _initialized = false;

  LocalFirstStorage get _storage {
    final client = _client;
    if (client == null) {
      throw StateError('Repository is not attached to a LocalFirstClient.');
    }
    return client.localStorage;
  }

  /// Ensures schema exists.
  Future<void> initialize() async {
    if (_initialized) return;
    await _storage.ensureSchema(name, schema, idFieldName: idFieldName);
    _initialized = true;
  }

  /// Resets initialization flag.
  void reset() {
    _initialized = false;
  }

  /// Builds a query for this repository.
  LocalFirstQuery<T> query() {
    return LocalFirstQuery<T>(
      repositoryName: name,
      delegate: _storage,
      fromEvent: _mapToEvent,
    );
  }

  /// Inserts or updates a record locally, marking it for sync.
  Future<void> upsert(T model) async {
    await initialize();
    final id = getId(model);
    final existing = await _storage.getById(name, id);
    final now = DateTime.now().toUtc();

    final createdAt = _decodeDate(existing?['created_at']) ?? now;
    final eventId =
        (existing?['event_id'] as String?) ?? UuidUtil.generateUuidV7();

    if (existing == null) {
      final event = LocalFirstEvent.createLocalInsert<T>(
        repositoryName: name,
        recordId: id,
        data: model,
        createdAt: now,
        eventId: eventId,
      );
      await _saveEventAndData(event, existingExists: false);
      return;
    }

    final existingOperation = _decodeOperation(existing['operation']);
    final existingStatus = _decodeStatus(existing['status']);

    final event = (existingStatus == SyncStatus.pending &&
            existingOperation == SyncOperation.insert)
        ? LocalFirstEvent.createLocalInsert<T>(
            repositoryName: name,
            recordId: id,
            data: model,
            createdAt: createdAt,
            eventId: eventId,
          )
        : LocalFirstEvent.createLocalUpdate<T>(
            repositoryName: name,
            recordId: id,
            data: model,
            createdAt: createdAt,
            eventId: eventId,
          );

    await _saveEventAndData(event, existingExists: true);
  }

  /// Deletes a record. Pending inserts are removed; otherwise marked as delete.
  Future<void> delete(String id) async {
    await initialize();
    final existing = await _storage.getById(name, id);
    if (existing == null) return;

    final status = _decodeStatus(existing['status']);
    final operation = _decodeOperation(existing['operation']);

    if (status == SyncStatus.pending && operation == SyncOperation.insert) {
      await _storage.delete(name, id);
      return;
    }

    final createdAt =
        _decodeDate(existing['created_at']) ?? DateTime.now().toUtc();
    final eventId =
        (existing['event_id'] as String?) ?? UuidUtil.generateUuidV7();

    final event = LocalFirstEvent.createLocalDelete<T>(
      repositoryName: name,
      recordId: id,
      data: fromJson(existing),
      createdAt: createdAt,
      eventId: eventId,
    );
    await _saveEventAndData(event, existingExists: true);
  }

  /// Pending events to push.
  Future<List<LocalFirstEvent<T>>> getPendingObjects() async {
    await initialize();
    final all = await _storage.getAll(name);
    return all
        .where((map) => _decodeStatus(map['status']) != SyncStatus.ok)
        .map(_mapToEvent)
        .toList();
  }

  /// Resolves conflict using provided resolver.
  T resolveConflict(T local, T remote) => onConflict(local, remote);

  /// Applies incoming remote events.
  Future<void> _mergeRemoteItems(LocalFirstEvents<T> remote) async {
    await initialize();
    for (final event in remote) {
      final existing = await _storage.getById(name, event.recordId);

      if (event.syncOperation == SyncOperation.delete) {
        if (existing == null) continue;
        final status = _decodeStatus(existing['status']);
        final op = _decodeOperation(existing['operation']);
        if (status != SyncStatus.ok && op == SyncOperation.insert) {
          // Keep local pending insert
          continue;
        }
        await _storage.delete(name, event.recordId);
        await _storage.insertEvent(event.toJson(toJson: toJson));
        continue;
      }

      // Insert/update
      if (existing == null) {
        final applied = LocalFirstEvent.createRemote<T>(
          repositoryName: event.repositoryName,
          recordId: event.recordId,
          operation: event.syncOperation,
          data: event.data,
          createdAt: event.syncCreatedAt,
          eventId: event.eventId,
        );
        await _saveEventAndData(applied, existingExists: false);
        continue;
      }

      final localStatus = _decodeStatus(existing['status']);
      if (localStatus != SyncStatus.ok) {
        // keep local pending change
        continue;
      }

      final localModel = fromJson(existing);
      final mergedModel = onConflict(localModel, event.data);
      final createdAt =
          _decodeDate(existing['created_at']) ?? event.syncCreatedAt;

      final applied = LocalFirstEvent.createRemote<T>(
        repositoryName: name,
        recordId: event.recordId,
        operation: event.syncOperation,
        data: mergedModel,
        createdAt: createdAt,
        eventId: event.eventId,
      );
      await _saveEventAndData(applied, existingExists: true);
    }
  }

  LocalFirstEvent<T> _mapToEvent(Map<String, dynamic> map) {
    final model = fromJson(map);
    final event = LocalFirstEvent.createRemote<T>(
      repositoryName: name,
      recordId: getId(model),
      operation: _decodeOperation(map['operation']),
      data: model,
      createdAt: _decodeDate(map['created_at']) ?? DateTime.now().toUtc(),
      eventId: map['event_id'] as String?,
    );

    return event;
  }

  Future<void> _saveEventAndData(
    LocalFirstEvent<T> event, {
    required bool existingExists,
  }) async {
    final map = {
      ...toJson(event.data),
      'status': event.syncStatus.index,
      'operation': event.syncOperation.index,
      'created_at': event.syncCreatedAt.millisecondsSinceEpoch,
      'event_id': event.eventId,
    };

    if (existingExists) {
      await _storage.update(name, event.recordId, map);
    } else {
      await _storage.insert(name, map, idFieldName);
    }

    await _storage.insertEvent(event.toJson(toJson: toJson));
  }

  SyncStatus _decodeStatus(dynamic value) {
    if (value is int && value >= 0 && value < SyncStatus.values.length) {
      return SyncStatus.values[value];
    }
    return SyncStatus.pending;
  }

  SyncOperation _decodeOperation(dynamic value) {
    if (value is int && value >= 0 && value < SyncOperation.values.length) {
      return SyncOperation.values[value];
    }
    return SyncOperation.insert;
  }

  DateTime? _decodeDate(dynamic value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    if (value is DateTime) return value.toUtc();
    return null;
  }
}
