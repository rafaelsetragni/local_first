part of '../../local_first.dart';

/// Supported primitive field types for schema-aware storage backends.
enum LocalFieldType { text, integer, real, boolean, datetime, blob }

/// Represents a data collection (similar to a table).
///
/// Each repository manages a specific type of object and handles CRUD operations
/// independently. Repositories can be used standalone, by inheritance, or as a
/// mixin.
///
/// Example:
/// ```dart
/// class ChatService with LocalFirstRepository<Chat> {
///   ChatService() {
///     initLocalFirstRepository(
///       name: 'chat',
///       getId: (chat) => chat.id,
///       toJson: (chat) => chat.toJson(),
///       fromJson: Chat.fromJson,
///       onConflict: (local, remote) => remote,
///     );
///   }
/// }
/// ```
mixin LocalFirstRepository<T extends Object> {
  /// The unique name identifier for this repository.
  late final String name;

  /// Serialization helpers for the repository items.
  late final String Function(T item) _getId;
  late final JsonMap Function(T item) _toJson;
  late final T Function(JsonMap json) _fromJson;
  late final T Function(T local, T remote) _resolveConflict;

  /// Field name used as identifier in persisted maps.
  late final String idFieldName;

  /// Schema definition for native storage backends (e.g. SQLite).
  late final Map<String, LocalFieldType> schema;

  late LocalFirstClient _client;

  late List<DataSyncStrategy> _syncStrategies;

  bool _isConfigured = false;

  /// Initializes a repository mixed into another class.
  ///
  /// Call this from your constructor when using [LocalFirstRepository]
  /// as a mixin.
  @protected
  void initLocalFirstRepository({
    required String name,
    required String Function(T item) getId,
    required JsonMap Function(T item) toJson,
    required T Function(JsonMap) fromJson,
    required T Function(T local, T remote) onConflict,
    String idFieldName = 'id',
    Map<String, LocalFieldType> schema = const {},
  }) {
    if (_isConfigured) {
      throw StateError('LocalFirstRepository already configured');
    }
    this.name = name;
    _getId = getId;
    _toJson = toJson;
    _fromJson = fromJson;
    _resolveConflict = onConflict;
    this.idFieldName = idFieldName;
    this.schema = Map.unmodifiable(schema);
    _isConfigured = true;
  }

  /// Creates a configured instance of LocalFirstRepository.
  ///
  /// Use this when you prefer not to mix it into another class.
  ///
  /// Example:
  /// ```dart
  /// final userRepo = LocalFirstRepository.create(
  ///   'users',
  ///   getId: (user) => user.id,
  ///   toJson: (user) => user.toJson(),
  ///   fromJson: User.fromJson,
  ///   onConflict: (local, remote) => local,
  /// );
  /// ```
  static LocalFirstRepository<T> create<T extends Object>({
    required String name,
    required String Function(T item) getId,
    required JsonMap Function(T item) toJson,
    required T Function(JsonMap) fromJson,
    required T Function(T local, T remote) onConflict,
    String idFieldName = 'id',
    Map<String, LocalFieldType> schema = const {},
  }) {
    return _LocalFirstRepository<T>(
      name: name,
      getId: getId,
      toJson: toJson,
      fromJson: fromJson,
      onConflict: onConflict,
      idFieldName: idFieldName,
      schema: schema,
    );
  }

  @mustCallSuper
  String getId(T item) => _getId(item);
  JsonMap toJson(T item) => _toJson(item);
  T fromJson(JsonMap json) => _fromJson(json);
  T resolveConflict(T local, T remote) => _resolveConflict(local, remote);

  bool _isInitialized = false;

  /// Returns true if this repository's storage has been initialized.
  bool get isInitialized => _isInitialized;

  /// Returns the delegate used by this repository.
  LocalFirstStorage get delegate => _client.localStorage;

  /// Saves a remote snapshot without scheduling a push.
  ///
  /// Consumes a full remote event (with metadata) and applies conflict
  /// resolution before persisting locally.
  Future<void> saveRemoteSnapshot(LocalFirstEvent remoteEvent) async {
    final remoteData = remoteEvent.dataAs<T>();
    final remoteId = getId(remoteData);

    final existingJson = await _client.localStorage.getById(name, remoteId);

    if (existingJson == null) {
      final snapshot = remoteEvent.copyWith(
        syncStatus: SyncStatus.ok,
        repositoryName: name,
      );
      await _client.localStorage.insert(
        name,
        _toStorageJson(snapshot),
        idFieldName,
      );
      if (remoteEvent.eventId.isNotEmpty) {
        await _client.localStorage.registerEvent(
          remoteEvent.eventId,
          remoteEvent.syncCreatedAt,
        );
      }
      return;
    }

    final existing = _eventFromJson(existingJson);

    if (existing.needSync) {
      final merged = resolveConflict(existing.dataAs<T>(), remoteData);
      final pending = existing.copyWith(data: merged);
      await _client.localStorage.update(
        name,
        remoteId,
        _toStorageJson(pending),
      );
      if (remoteEvent.eventId.isNotEmpty) {
        await _client.localStorage.registerEvent(
          remoteEvent.eventId,
          remoteEvent.syncCreatedAt,
        );
      }
      return;
    }
    final operation = remoteEvent.syncOperation == SyncOperation.insert
        ? SyncOperation.update
        : remoteEvent.syncOperation;

    final updated = remoteEvent.copyWith(
      syncStatus: SyncStatus.ok,
      syncOperation: operation,
      syncCreatedAt: remoteEvent.syncCreatedAt,
      repositoryName: name,
    );

    await _client.localStorage.update(name, remoteId, _toStorageJson(updated));

    if (remoteEvent.eventId.isNotEmpty) {
      await _client.localStorage.registerEvent(
        remoteEvent.eventId,
        remoteEvent.syncCreatedAt,
      );
    }
  }

  /// Initializes the repository.
  ///
  /// This is called automatically by [LocalFirstClient.initialize].
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _client.localStorage.ensureSchema(
      name,
      schema,
      idFieldName: idFieldName,
    );
    _isInitialized = true;
  }

  /// Resets the repository's initialization state.
  ///
  /// Used internally when clearing all data.
  void reset() {
    _isInitialized = false;
  }

  Future<void> _pushLocalEventToRemote(LocalFirstEvent event) async {
    assert(event.needSync, 'Only pending events should be pushed to remote');

    final supported = _syncStrategies
        .where((strategy) => strategy.supportsEvent(event))
        .toList();
    if (supported.isEmpty) return;

    final results = await Future.wait(
      supported.map((strategy) async {
        try {
          return await strategy.onPushToRemote(event);
        } catch (_) {
          return SyncStatus.failed;
        }
      }),
    );

    // Choose the highest status returned (by enum index).
    final statuses = [event.syncStatus, ...results];
    final newStatus = statuses.reduce((a, b) => a.index >= b.index ? a : b);

    if (newStatus != event.syncStatus) {
      final updatedEvent = event.copyWith(syncStatus: newStatus);
      await _updateEventStatus(updatedEvent);
    }
  }

  /// Inserts or updates an item (upsert operation).
  ///
  /// If an item with the same ID already exists, it will be updated.
  /// Otherwise, a new item will be inserted.
  ///
  /// The operation is marked as pending and will be synced on next [LocalFirstClient.sync].
  Future<void> upsert(T item) async {
    final json = await _client.localStorage.getById(name, getId(item));
    if (json != null) {
      final existing = _eventFromJson(json);
      final merged = resolveConflict(existing.dataAs<T>(), item);
      if (JsonUtil.equals(_toJson(existing.dataAs<T>()), _toJson(merged))) {
        return;
      }
      final wasPendingInsert =
          existing.needSync && existing.syncOperation == SyncOperation.insert;
      final eventId = wasPendingInsert
          ? existing.eventId
          : UuidUtil.generateUuidV7();
      await _update(
        _prepareForUpdate(existing, merged, eventId: eventId),
        wasPendingInsert: wasPendingInsert,
      );
    } else {
      await _insert(item);
    }
  }

  Future<void> _insert(T item) async {
    final event = _prepareForInsert(item);

    final insertFuture = _client.localStorage.insert(
      name,
      _toStorageJson(event),
      idFieldName,
    );

    final pushFuture = _pushLocalEventToRemote(event);
    await Future.wait([pushFuture, insertFuture]);
    await _client.localStorage.registerEvent(
      event.eventId,
      event.syncCreatedAt,
    );
  }

  Future<void> _update(
    LocalFirstEvent event, {
    required bool wasPendingInsert,
  }) async {
    final eventForUpdate = wasPendingInsert
        ? event
        : event.copyWith(syncOperation: SyncOperation.update);
    final updatedEvent = eventForUpdate.copyWith(
      syncStatus: SyncStatus.pending,
    );

    await _client.localStorage.update(
      name,
      getId(updatedEvent.dataAs<T>()),
      _toStorageJson(updatedEvent),
    );

    await _client.localStorage.registerEvent(
      updatedEvent.eventId,
      updatedEvent.syncCreatedAt,
    );
    await _pushLocalEventToRemote(updatedEvent);
    if (wasPendingInsert) {
      final synced = updatedEvent.copyWith(syncStatus: SyncStatus.ok);
      await _updateEventStatus(synced);
    }
  }

  /// Deletes an item by its ID (soft delete).
  ///
  /// The item is marked as deleted and will be synced on next [LocalFirstClient.sync].
  /// If the item was inserted locally and not yet synced, it will be permanently
  /// removed from local storage.
  ///
  /// Parameters:
  /// - [id]: The unique identifier of the item to delete
  Future<void> delete(String id) async {
    final json = await _client.localStorage.getById(name, id);
    if (json == null) {
      return;
    }

    final event = _eventFromJson(json);

    if (event.needSync && event.syncOperation == SyncOperation.insert) {
      await _client.localStorage.delete(name, id);
      return;
    }

    final deleteEvent = LocalFirstEvent(
      data: event.data,
      eventId: UuidUtil.generateUuidV7(),
      syncStatus: SyncStatus.pending,
      syncOperation: SyncOperation.delete,
      syncCreatedAt: DateTime.now().toUtc(),
      repositoryName: name,
    );

    await _client.localStorage.update(
      name,
      getId(deleteEvent.dataAs<T>()),
      _toStorageJson(deleteEvent),
    );
    await _client.localStorage.registerEvent(
      deleteEvent.eventId,
      deleteEvent.syncCreatedAt,
    );
  }

  JsonMap _toStorageJson(LocalFirstEvent event) {
    return {
      ...toJson(event.dataAs<T>()),
      '_event_id': event.eventId,
      '_sync_status': event.syncStatus.index,
      '_sync_operation': event.syncOperation.index,
      '_sync_created_at': event.syncCreatedAt.millisecondsSinceEpoch,
      '_sync_created_at_server':
          event.syncCreatedAtServer?.millisecondsSinceEpoch,
      '_server_sequence': event.syncServerSequence,
    };
  }

  LocalFirstEvent _prepareForInsert(T model) {
    return LocalFirstEvent(
      data: model,
      syncStatus: SyncStatus.pending,
      syncOperation: SyncOperation.insert,
      syncCreatedAt: DateTime.now().toUtc(),
      repositoryName: name,
    );
  }

  LocalFirstEvent _prepareForUpdate(
    LocalFirstEvent existing,
    T model, {
    required String eventId,
  }) {
    return LocalFirstEvent(
      data: model,
      eventId: eventId,
      syncStatus: existing.syncStatus,
      syncOperation: existing.syncOperation,
      syncCreatedAt: existing.syncCreatedAt,
      repositoryName: name,
    );
  }

  /// Creates a query for this node.
  ///
  /// Use this to perform filtered, ordered, and paginated queries.
  ///
  /// Example:
  /// ```dart
  /// final activeUsers = await userRepository
  ///   .query()
  ///   .where('status', isEqualTo: 'active')
  ///   .getAll();
  /// ```
  LocalFirstQuery<T> query() {
    return LocalFirstQuery<T>(
      repositoryName: name,
      delegate: _client.localStorage,
      repository: this,
    );
  }

  Future<void> _mergeRemoteItems(List<LocalFirstEvent> remoteEvents) async {
    final allLocal = await _getAllEvents(includeDeleted: true);
    final Map<String, LocalFirstEvent> localMap = {
      for (var event in allLocal) getId(event.dataAs<T>()): event,
    };

    for (final remoteEvent in remoteEvents) {
      final remoteObj = remoteEvent.data;
      if (remoteObj is! T) {
        continue;
      }
      final remoteId = getId(remoteObj);
      final localEvent = localMap[remoteId];
      final remoteEventId = remoteEvent.eventId;
      if (remoteEventId.isNotEmpty &&
          await _client.localStorage.isEventRegistered(remoteEventId)) {
        if (localEvent != null &&
            localEvent.eventId == remoteEventId &&
            localEvent.syncCreatedAtServer == null) {
          await _updateEventServerTimestamp(localEvent);
        }
        continue;
      }

      if (remoteEvent.isDeleted) {
        if (localEvent != null && !localEvent.needSync) {
          await _client.localStorage.delete(name, remoteId);
          continue;
        }
        if (remoteEventId.isNotEmpty) {
          await _client.localStorage.registerEvent(
            remoteEventId,
            remoteEvent.syncCreatedAt,
          );
        }
        continue;
      }

      if (localEvent == null) {
        final createdAtServer =
            remoteEvent.syncCreatedAtServer ?? DateTime.now().toUtc();
        final insertEvent = LocalFirstEvent(
          data: remoteObj,
          eventId: remoteEvent.eventId,
          syncStatus: SyncStatus.ok,
          syncOperation: remoteEvent.syncOperation,
          syncCreatedAt: remoteEvent.syncCreatedAt,
          syncCreatedAtServer: createdAtServer,
          syncServerSequence: remoteEvent.syncServerSequence,
          repositoryName: name,
        );
        await _client.localStorage.insert(
          name,
          _toStorageJson(insertEvent),
          idFieldName,
        );
        if (remoteEventId.isNotEmpty) {
          await _client.localStorage.registerEvent(
            remoteEventId,
            remoteEvent.syncCreatedAt,
          );
        }
        continue;
      }

      final resolved = resolveConflict(localEvent.dataAs<T>(), remoteObj);
      final createdAtServer =
          localEvent.syncCreatedAtServer ??
          remoteEvent.syncCreatedAtServer ??
          DateTime.now().toUtc();
      final updatedEvent = LocalFirstEvent(
        data: resolved,
        eventId: remoteEvent.eventId,
        syncStatus: SyncStatus.ok,
        syncOperation: SyncOperation.update,
        syncCreatedAt: remoteEvent.syncCreatedAt,
        syncCreatedAtServer: createdAtServer,
        syncServerSequence: remoteEvent.syncServerSequence,
        repositoryName: name,
      );
      await _client.localStorage.update(
        name,
        remoteId,
        _toStorageJson(updatedEvent),
      );
      if (remoteEventId.isNotEmpty) {
        await _client.localStorage.registerEvent(
          remoteEventId,
          remoteEvent.syncCreatedAt,
        );
      }
    }
  }

  Future<List<LocalFirstEvent>> getPendingObjects() async {
    final allObjects = await _getAllEvents(includeDeleted: true);
    return allObjects.where((event) => event.needSync).toList();
  }

  Future<List<LocalFirstEvent>> _getAllEvents({
    bool includeDeleted = false,
  }) async {
    final maps = await _client.localStorage.getAll(name);
    return maps //
        .map(_eventFromJson)
        .where((event) => includeDeleted || !event.isDeleted)
        .toList();
  }

  Future<void> _updateEventStatus(LocalFirstEvent event) async {
    await _client.localStorage.update(
      name,
      getId(event.dataAs<T>()),
      _toStorageJson(event),
    );
  }

  LocalFirstEvent _eventFromJson(JsonMap json) {
    final itemJson = JsonMap.from(json);
    final eventId = itemJson.remove('_event_id')?.toString();
    final statusIndex = itemJson.remove('_sync_status') as int?;
    final opIndex = itemJson.remove('_sync_operation') as int?;
    final createdAtMs = itemJson.remove('_sync_created_at') as int?;
    final createdAtServerMs =
        itemJson.remove('_sync_created_at_server') as int?;
    final serverSequence = itemJson.remove('_server_sequence') as int?;

    final model = fromJson(itemJson);
    return LocalFirstEvent(
      data: model,
      eventId: eventId,
      syncStatus: statusIndex != null
          ? SyncStatus.values[statusIndex]
          : SyncStatus.ok,
      syncOperation: opIndex != null
          ? SyncOperation.values[opIndex]
          : SyncOperation.insert,
      syncCreatedAt: createdAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true)
          : null,
      syncCreatedAtServer: createdAtServerMs != null
          ? DateTime.fromMillisecondsSinceEpoch(createdAtServerMs, isUtc: true)
          : null,
      syncServerSequence: serverSequence,
      repositoryName: name,
    );
  }

  LocalFirstEvent _buildRemoteEvent(
    JsonMap json, {
    required SyncOperation operation,
  }) {
    final itemJson = JsonMap.from(json);
    final eventId = itemJson.remove('event_id')?.toString();
    final serverSequence = _parseRemoteInt(itemJson.remove('server_sequence'));
    final createdAtClient = _parseRemoteDate(itemJson['created_at_client']);
    final createdAtServer = _parseRemoteDate(itemJson['created_at_server']);
    itemJson.remove('created_at_client');
    itemJson.remove('created_at_server');
    final now = DateTime.now().toUtc();
    final resolvedCreatedAtClient = createdAtClient ?? now;
    final resolvedCreatedAtServer = createdAtServer;
    return LocalFirstEvent(
      data: _fromJson(itemJson),
      eventId: eventId,
      syncStatus: SyncStatus.ok,
      syncOperation: operation,
      syncCreatedAt: resolvedCreatedAtClient,
      syncCreatedAtServer: resolvedCreatedAtServer,
      syncServerSequence: serverSequence,
      repositoryName: name,
    );
  }

  DateTime? _parseRemoteDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    if (value is String) {
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }

  int? _parseRemoteInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return int.tryParse(value.toString());
  }

  Future<void> _updateEventServerTimestamp(LocalFirstEvent event) async {
    final updated = event.copyWith(syncCreatedAtServer: DateTime.now().toUtc());
    await _client.localStorage.update(
      name,
      getId(updated.dataAs<T>()),
      _toStorageJson(updated),
    );
  }

  Future<LocalFirstEvent?> _getById(String id) async {
    final json = await _client.localStorage.getById(name, id);
    if (json == null) {
      return null;
    }
    return _eventFromJson(json);
  }
}

final class _LocalFirstRepository<T extends Object>
    with LocalFirstRepository<T> {
  _LocalFirstRepository({
    required String name,
    required String Function(T item) getId,
    required JsonMap Function(T item) toJson,
    required T Function(JsonMap) fromJson,
    required T Function(T local, T remote) onConflict,
    String idFieldName = 'id',
    Map<String, LocalFieldType> schema = const {},
  }) {
    initLocalFirstRepository(
      name: name,
      getId: getId,
      toJson: toJson,
      fromJson: fromJson,
      onConflict: onConflict,
      idFieldName: idFieldName,
      schema: schema,
    );
  }
}
