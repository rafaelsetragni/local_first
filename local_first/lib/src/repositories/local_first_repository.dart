part of '../../local_first.dart';

/// Convenience alias for lists of events.
typedef LocalFirstEvents<T> = List<LocalFirstEvent<T>>;

/// Repository responsible for persisting domain objects and emitting events.
class LocalFirstRepository<T extends Object> {
  LocalFirstRepository._({
    required this.name,
    required this.getId,
    required this.toJson,
    required this.fromJson,
    LocalFirstEvent<T> Function(
      LocalFirstEvent<T> local,
      LocalFirstEvent<T> remote,
    )?
        onConflictEvent,
    required this.schema,
    required this.idFieldName,
  }) : onConflictEvent = onConflictEvent ?? ConflictUtil.lastWriteWins;

  factory LocalFirstRepository.create({
    required String name,
    required String Function(T model) getId,
    required JsonMap<dynamic> Function(T model) toJson,
    required T Function(JsonMap<dynamic> json) fromJson,
    LocalFirstEvent<T> Function(
      LocalFirstEvent<T> local,
      LocalFirstEvent<T> remote,
    )?
        onConflictEvent,
    JsonMap<LocalFieldType> schema = const {},
    String idFieldName = 'id',
  }) {
    return LocalFirstRepository._(
      name: name,
      getId: getId,
      toJson: toJson,
      fromJson: fromJson,
      onConflictEvent: onConflictEvent,
      schema: schema,
      idFieldName: idFieldName,
  );
  }

  final String name;
  final String Function(T model) getId;
  final JsonMap<dynamic> Function(T model) toJson;
  final T Function(JsonMap<dynamic> json) fromJson;
  final LocalFirstEvent<T> Function(
    LocalFirstEvent<T> local,
    LocalFirstEvent<T> remote,
  )
  onConflictEvent;
  final JsonMap<LocalFieldType> schema;
  final String idFieldName;

  LocalFirstClient? _client;
  bool _initialized = false;

  // Reserved for future sync strategy integration.
  // ignore: unused_field
  List<dynamic> _syncStrategies = [];

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

    final latestEvent = await _latestEventFor(id);
    final createdAt = latestEvent?.syncCreatedAt ?? now;
    final eventId = latestEvent?.eventId ?? UuidUtil.generateUuidV7();

    if (existing == null || latestEvent == null) {
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

    final existingOperation = latestEvent.syncOperation;
    final existingStatus = latestEvent.syncStatus;

    final event =
        (existingStatus == SyncStatus.pending &&
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

    final latestEvent = await _latestEventFor(id);
    final status = latestEvent?.syncStatus ?? SyncStatus.ok;
    final operation = latestEvent?.syncOperation ?? SyncOperation.insert;

    if (status == SyncStatus.pending && operation == SyncOperation.insert) {
      await _storage.delete(name, id);
      return;
    }

    final createdAt = latestEvent?.syncCreatedAt ?? DateTime.now().toUtc();
    final eventId = latestEvent?.eventId ?? UuidUtil.generateUuidV7();

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
    final events = await _storage.getEvents(repositoryName: name);
    final byRecord = <String, Map<String, dynamic>>{};
    for (final e in events) {
      final rid = e['record_id']?.toString();
      if (rid == null) continue;
      final created = e['created_at'];
      final prev = byRecord[rid];
      final prevTs = prev?['created_at'];
      final isNewer = created is int && (prevTs is! int || created > prevTs);
      if (prev == null || isNewer) {
        byRecord[rid] = e;
      }
    }
    return byRecord.values
        .map((e) => LocalFirstEvent.fromJson<T>(e, fromJson: fromJson))
        .where((e) => e.syncStatus != SyncStatus.ok)
        .toList();
  }

  /// Resolves conflict using provided resolver.
  LocalFirstEvent<T> resolveConflict(
    LocalFirstEvent<T> local,
    LocalFirstEvent<T> remote,
  ) =>
      onConflictEvent(local, remote);

  /// Applies incoming remote events.
  Future<void> _mergeRemoteItems(LocalFirstEvents<T> remote) async {
    await initialize();
    for (final event in remote) {
      final existing = await _storage.getById(name, event.recordId);
      final latestLocalEvent = await _latestEventFor(event.recordId);
      _requireRemoteServerSequence(event);

      if (event.syncOperation == SyncOperation.delete) {
        final status = latestLocalEvent?.syncStatus ?? SyncStatus.ok;
        final op = latestLocalEvent?.syncOperation ?? SyncOperation.insert;

        // Always log the remote delete and mark as synchronized.
        await _storage.pullRemoteEvent({
          ...event.toJson(toJson: toJson),
          'status': SyncStatus.ok.index,
        });

        // Delete local data if it exists, even if local insert was pending.
        if (existing != null) {
          await _storage.delete(name, event.recordId);
        }

        // If it was a pending insert, keep the log entry but remove the data row
        // so it won't be re-pushed as a resurrection.
        if (status != SyncStatus.ok && op == SyncOperation.insert) {
          continue;
        }
        continue;
      }

      // Insert/update
      if (existing == null) {
        final applied = LocalFirstEvent.createFromRemote<T>(
          repositoryName: event.repositoryName,
          recordId: event.recordId,
          operation: event.syncOperation,
          data: event.data,
          createdAt: event.syncCreatedAt,
          eventId: event.eventId,
          serverSequence: _requireRemoteServerSequence(event),
        );
        await _saveEventAndData(applied, existingExists: false);
        continue;
      }

      final localEvent =
          latestLocalEvent ??
          LocalFirstEvent.createLocalUpdate<T>(
            repositoryName: name,
            recordId: event.recordId,
            data: fromJson(existing),
            createdAt:
                _decodeDate(existing['created_at']) ?? event.syncCreatedAt,
            eventId: existing['event_id'] as String?,
          );

      final applied = resolveConflict(localEvent, event);
      await _saveEventAndData(applied, existingExists: true);
    }
  }

  /// Applies incoming remote events expressed as raw JSON maps.
  ///
  /// Handles idempotence by consulting the event log before constructing
  /// [LocalFirstEvent] instances.
  Future<void> _mergeRemoteEventMaps(List<JsonMap<dynamic>> rawEvents) async {
    final eventsToApply = <LocalFirstEvent<T>>[];
    for (final raw in rawEvents) {
      final eventId = raw['event_id'] as String?;
      if (eventId == null || eventId.isEmpty) {
        throw FormatException('Missing event_id for repository $name');
      }
      final serverSeq = raw['server_sequence'];
      if (serverSeq == null || serverSeq is! int) {
        throw FormatException('Missing server_sequence for repository $name');
      }

      final payload = raw['payload'];
      final recordId =
          raw['record_id'] ??
          raw[idFieldName] ??
          (payload is Map ? payload[idFieldName] : null);
      if (recordId == null) {
        throw FormatException('Missing record_id for repository $name');
      }
      final normalized = {...raw, 'record_id': recordId.toString()};

      final already = await _storage.getEventById(eventId);
      if (already != null) {
        await _storage.pullRemoteEvent({
          ...normalized,
          'status': SyncStatus.ok.index,
        });
        continue;
      }

      await _storage.pullRemoteEvent(normalized);
      eventsToApply.add(
        LocalFirstEvent.fromJson<T>(normalized, fromJson: fromJson),
      );
    }

    await _mergeRemoteItems(eventsToApply);
  }

  LocalFirstEvent<T> _mapToEvent(JsonMap<dynamic> map) {
    final model = fromJson(map);
    final serverSequence = map['server_sequence'];
    if (serverSequence == null || serverSequence is! int) {
      throw FormatException('Missing server_sequence for repository $name');
    }
    final event = LocalFirstEvent.createFromRemote<T>(
      repositoryName: name,
      recordId: getId(model),
      operation: _decodeOperation(map['operation']),
      data: model,
      createdAt: _decodeDate(map['created_at']) ?? DateTime.now().toUtc(),
      eventId: map['event_id'] as String?,
      serverSequence: serverSequence,
    );

    return event;
  }

  Future<void> _saveEventAndData(
    LocalFirstEvent<T> event, {
    required bool existingExists,
  }) async {
    final map = toJson(event.data);

    if (existingExists) {
      await _storage.update(name, event.recordId, map);
    } else {
      await _storage.insert(name, map, idFieldName);
    }

    await _storage.pullRemoteEvent(event.toJson(toJson: toJson));
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

  Future<LocalFirstEvent<T>?> _latestEventFor(String recordId) async {
    final events = await _storage.getEvents(repositoryName: name);
    Map<String, dynamic>? selected;
    for (final e in events) {
      if (e['record_id']?.toString() != recordId) continue;
      final ts = e['created_at'];
      final selTs = selected?['created_at'];
      final newer = ts is int && (selTs is! int || ts > selTs);
      if (selected == null || newer) {
        selected = e;
      }
    }
    if (selected == null) return null;
    return LocalFirstEvent.fromJson<T>(selected, fromJson: fromJson);
  }

  /// Marks specific events as synchronized (status ok) within this repository.
  Future<void> markEventsAsSynced(Iterable<LocalFirstEvent> events) async {
    if (events.isEmpty) return;
    if (!_initialized) {
      throw StateError(
        'Repository $name is not initialized. Call initialize/openStorage first.',
      );
    }
    for (final event in events) {
      if (event is! LocalFirstEvent<T>) continue;
      if (event.repositoryName != name) continue;
      final updated = {
        ...event.toJson(toJson: toJson),
        'status': SyncStatus.ok.index,
      };
      await _storage.pullRemoteEvent(updated);
    }
  }

  int _requireRemoteServerSequence(LocalFirstEvent<T> event) {
    final value = event.serverSequence;
    if (value == null) {
      throw FormatException(
        'Missing server_sequence for repository ${event.repositoryName}',
      );
    }
    return value;
  }
}
