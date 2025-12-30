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
  late final Map<String, dynamic> Function(T item) _toJson;
  late final T Function(Map<String, dynamic> json) _fromJson;
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
    required Map<String, dynamic> Function(T item) toJson,
    required T Function(Map<String, dynamic>) fromJson,
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
    required Map<String, dynamic> Function(T item) toJson,
    required T Function(Map<String, dynamic>) fromJson,
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
  Map<String, dynamic> toJson(T item) => _toJson(item);
  T fromJson(Map<String, dynamic> json) => _fromJson(json);
  T resolveConflict(T local, T remote) => _resolveConflict(local, remote);

  bool _isInitialized = false;

  /// Returns true if this repository's storage has been initialized.
  bool get isInitialized => _isInitialized;

  /// Returns the delegate used by this repository.
  LocalFirstStorage get delegate => _client.localStorage;

  /// Saves a remote snapshot without scheduling a push.
  ///
  /// If the local record has pending changes, it is left untouched.
  Future<void> saveRemoteSnapshot(T item) async {
    final existingJson =
        await _client.localStorage.getById(name, getId(item));
    if (existingJson != null) {
      final existing = _eventFromJson(existingJson);
      if (existing.needSync) return;
      final merged = _copyModel(existing.dataAs<T>(), item);
      final operation = existing.syncOperation == SyncOperation.insert
          ? SyncOperation.update
          : existing.syncOperation;
      final updated = LocalFirstEvent(
        data: merged,
        eventId: existing.eventId,
        syncStatus: SyncStatus.ok,
        syncOperation: operation,
        syncCreatedAt: existing.syncCreatedAt,
        syncCreatedAtServer: existing.syncCreatedAtServer,
        serverSequence: existing.serverSequence,
        repositoryName: name,
      );
      await _client.localStorage.update(
        name,
        getId(item),
        _toStorageJson(updated),
      );
      return;
    }

    final snapshot = LocalFirstEvent(
      data: item,
      syncStatus: SyncStatus.ok,
      syncOperation: SyncOperation.insert,
      syncCreatedAt: DateTime.now().toUtc(),
      repositoryName: name,
    );
    await _client.localStorage.insert(
      name,
      _toStorageJson(snapshot),
      idFieldName,
    );
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

  Future<void> _pushLocalEvent(LocalFirstEvent event) async {
    var attempted = false;
    for (var strategy in _syncStrategies) {
      if (!strategy.supportsEvent(event)) {
        continue;
      }
      attempted = true;
      final attemptEvent = event.copyWith(
        syncCreatedAtServer: DateTime.now().toUtc(),
      );
      try {
        final syncResult = await strategy.onPushToRemote(attemptEvent);
        final updatedEvent = syncResult == SyncStatus.ok
            ? attemptEvent.copyWith(syncStatus: SyncStatus.ok)
            : attemptEvent.copyWith(syncStatus: syncResult);
        await _updateEventStatus(updatedEvent);
        if (syncResult == SyncStatus.ok) return;
      } catch (e) {
        final failedEvent = attemptEvent.copyWith(syncStatus: SyncStatus.failed);
        await _updateEventStatus(failedEvent);
      }
    }
    if (!attempted) {
      await _updateEventStatus(event);
    }
  }

  /// Inserts or updates an item (upsert operation).
  ///
  /// If an item with the same ID already exists, it will be updated.
  /// Otherwise, a new item will be inserted.
  ///
  /// The operation is marked as pending and will be synced on next [LocalFirstClient.sync].
  Future<void> upsert(T item, {bool fromRemote = false}) async {
    if (fromRemote) {
      await saveRemoteSnapshot(item);
      return;
    }
    final json = await _client.localStorage.getById(name, getId(item));
    if (json != null) {
      final existing = _eventFromJson(json);
      final merged = _copyModel(existing.dataAs<T>(), item);
      if (_jsonEquals(_toJson(existing.dataAs<T>()), _toJson(merged))) {
        return;
      }
      final wasPendingInsert =
          existing.needSync && existing.syncOperation == SyncOperation.insert;
      final eventId = wasPendingInsert
          ? existing.eventId
          : UuidUtil.generateUuidV7();
      await _update(
        _prepareForUpdate(
          existing,
          merged,
          eventId: eventId,
        ),
        wasPendingInsert: wasPendingInsert,
      );
    } else {
      await _insert(item);
    }
  }

  bool _jsonEquals(Object? left, Object? right) {
    if (identical(left, right)) return true;
    if (left == null || right == null) return left == right;
    if (left is Map && right is Map) {
      if (left.length != right.length) return false;
      for (final entry in left.entries) {
        if (!right.containsKey(entry.key)) return false;
        if (!_jsonEquals(entry.value, right[entry.key])) return false;
      }
      return true;
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var i = 0; i < left.length; i++) {
        if (!_jsonEquals(left[i], right[i])) return false;
      }
      return true;
    }
    return left == right;
  }

  Future<void> _insert(T item) async {
    final event = _prepareForInsert(item);

    final insertFuture = _client.localStorage.insert(
      name,
      _toStorageJson(event),
      idFieldName,
    );

    final pushFuture = _pushLocalEvent(event);
    await Future.wait([pushFuture, insertFuture]);
    await _client.localStorage.registerEvent(
      event.eventId,
      event.syncCreatedAt ?? DateTime.now().toUtc(),
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
      updatedEvent.syncCreatedAt ?? DateTime.now().toUtc(),
    );
    await _pushLocalEvent(updatedEvent);
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
      deleteEvent.syncCreatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> _toStorageJson(LocalFirstEvent event) {
    return {
      ...toJson(event.dataAs<T>()),
      '_event_id': event.eventId,
      '_sync_status': event.syncStatus.index,
      '_sync_operation': event.syncOperation.index,
      '_sync_created_at':
          event.syncCreatedAt?.millisecondsSinceEpoch ??
          DateTime.now().toUtc().millisecondsSinceEpoch,
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
            remoteEvent.syncCreatedAt ?? DateTime.now().toUtc(),
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
          syncCreatedAt: remoteEvent.syncCreatedAt ?? DateTime.now().toUtc(),
          syncCreatedAtServer: createdAtServer,
          serverSequence: remoteEvent.syncServerSequence,
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
            remoteEvent.syncCreatedAt ?? DateTime.now().toUtc(),
          );
        }
        continue;
      }

      final resolved = resolveConflict(localEvent.dataAs<T>(), remoteObj);
      final createdAtServer = localEvent.syncCreatedAtServer ??
          remoteEvent.syncCreatedAtServer ??
          DateTime.now().toUtc();
      final updatedEvent = LocalFirstEvent(
        data: resolved,
        eventId: remoteEvent.eventId,
        syncStatus: SyncStatus.ok,
        syncOperation: SyncOperation.update,
        syncCreatedAt: remoteEvent.syncCreatedAt ?? DateTime.now().toUtc(),
        syncCreatedAtServer: createdAtServer,
        serverSequence: remoteEvent.syncServerSequence,
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
          remoteEvent.syncCreatedAt ?? DateTime.now().toUtc(),
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

  LocalFirstEvent _eventFromJson(Map<String, dynamic> json) {
    final itemJson = Map<String, dynamic>.from(json);
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
          ? DateTime.fromMillisecondsSinceEpoch(
              createdAtServerMs,
              isUtc: true,
            )
          : null,
      serverSequence: serverSequence,
      repositoryName: name,
    );
  }

  T _copyModel(T target, T source) {
    // Shallow copy via JSON round-trip using existing serializers.
    return _fromJson({..._toJson(target), ..._toJson(source)});
  }

  LocalFirstEvent _buildRemoteEvent(
    Map<String, dynamic> json, {
    required SyncOperation operation,
  }) {
    final itemJson = Map<String, dynamic>.from(json);
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
      serverSequence: serverSequence,
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
    final updated =
        event.copyWith(syncCreatedAtServer: DateTime.now().toUtc());
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
    required Map<String, dynamic> Function(T item) toJson,
    required T Function(Map<String, dynamic>) fromJson,
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
