part of '../../local_first.dart';

/// Supported primitive field types for schema-aware storage backends.
enum LocalFieldType { text, integer, real, boolean, datetime, blob }

/// Represents a data collection (similar to a table).
///
/// Each repository manages a specific type of object and handles CRUD operations
/// independently. Repositories can be used standalone or by inheritance.
///
/// Example:
/// ```dart
/// class ChatService extends LocalFirstRepository<Chat> {
///   ChatService()
///     : super(
///         'chat',
///         getId: (chat) => chat.id,
///         toJson: (chat) => chat.toJson(),
///         fromJson: Chat.fromJson,
///         onConflict: (local, remote) => remote,
///       );
/// }
/// ```
abstract class LocalFirstRepository<T> {
  /// The unique name identifier for this repository.
  final String name;

  /// Serialization helpers for the repository items.
  final String Function(T item) _getId;
  final Map<String, dynamic> Function(T item) _toJson;
  final T Function(Map<String, dynamic> json) _fromJson;
  final T Function(T local, T remote) _resolveConflict;

  /// Field name used as identifier in persisted maps.
  final String idFieldName;

  /// Schema definition for native storage backends (e.g. SQLite).
  final Map<String, LocalFieldType> schema;

  late LocalFirstClient _client;

  late List<DataSyncStrategy> _syncStrategies;

  /// Creates a new LocalFirstRepository.
  ///
  /// Parameters:
  /// - [name]: Unique identifier for this repository
  /// - [getId]: Returns the primary key of the model
  /// - [toJson]: Serializes the model to Map
  /// - [fromJson]: Deserializes the model from Map
  /// - [onConflict]: Resolves conflicts between local/remote models
  /// - [idFieldName]: Key used to persist the model id (default: `id`)
  /// - [schema]: Optional schema used by SQL backends for column creation
  LocalFirstRepository({
    required this.name,
    required String Function(T item) getId,
    required Map<String, dynamic> Function(T item) toJson,
    required T Function(Map<String, dynamic>) fromJson,
    required T Function(T local, T remote) onConflict,
    this.idFieldName = 'id',
    Map<String, LocalFieldType> schema = const {},
  }) : _getId = getId,
       _toJson = toJson,
       _fromJson = fromJson,
       _resolveConflict = onConflict,
       schema = Map.unmodifiable(schema);

  /// Creates a configured instance of LocalFirstRepository.
  ///
  /// Use this factory when you prefer not to use inheritance.
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
  factory LocalFirstRepository.create({
    required String name,
    required String Function(T item) getId,
    required Map<String, dynamic> Function(T item) toJson,
    required T Function(Map<String, dynamic>) fromJson,
    required T Function(T local, T remote) onConflict,
    String idFieldName,
    Map<String, LocalFieldType> schema,
  }) = _LocalFirstRepository;

  String getId(T item) => _getId(item);
  Map<String, dynamic> toJson(T item) => _toJson(item);
  T fromJson(Map<String, dynamic> json) => _fromJson(json);
  T resolveConflict(T local, T remote) => _resolveConflict(local, remote);

  bool _isInitialized = false;

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

  /// Pushes a state event through all sync strategies, updating its status.
  Future<LocalFirstEvent<T>> _pushLocalEvent(LocalFirstEvent<T> event) async {
    var current = event;

    for (var strategy in _syncStrategies) {
      try {
        final syncResult = await strategy.onPushToRemote(current);
        current = current.copyWith(syncStatus: syncResult);
        if (syncResult == SyncStatus.ok) {
          await _updateEventStatus(current);
          return current;
        }
      } catch (e) {
        current = current.copyWith(syncStatus: SyncStatus.failed);
      }
    }

    await _updateEventStatus(current);
    return current;
  }

  /// Inserts or updates an item (upsert operation).
  ///
  /// If an item with the same ID already exists, it will be updated.
  /// Otherwise, a new item will be inserted.
  ///
  /// The operation is marked as pending and will be synced on next [LocalFirstClient.sync].
  Future<void> upsert(dynamic item, {required bool needSync}) async {
    final LocalFirstEvent<T> event = item is LocalFirstEvent<T>
        ? item
        : LocalFirstEvent<T>(state: item as T);
    final adjusted = event.copyWith(
      syncStatus: needSync ? SyncStatus.pending : SyncStatus.ok,
    );

    final json = await _client.localStorage.getById(name, getId(event.state));
    if (json != null) {
      final existing = _eventFromJson(json);
      await _update(_prepareForUpdate(_copyEvent(existing, adjusted),
          needSync: needSync));
    } else {
      await _insert(_prepareForInsert(adjusted, needSync: needSync));
    }
  }

  Future<void> _insert(LocalFirstEvent<T> item) async {
    final model = item;

    await _client.localStorage.insert(name, _toDataJson(model), idFieldName);

    await _persistEvent(model);
    if (model.needSync) {
      await _pushLocalEvent(model);
    }
  }

  Future<void> _update(LocalFirstEvent<T> object) async {
    final model = object;
    await _client.localStorage.update(
      name,
      getId(model.state),
      _toDataJson(model),
    );

    await _persistEvent(model);
    if (model.needSync) {
      await _pushLocalEvent(model);
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
  Future<void> delete(String id, {required bool needSync}) async {
    final json = await _client.localStorage.getById(name, id);
    if (json == null) {
      return;
    }

    final object = _eventFromJson(json);

    final deleted = object.copyWith(
      eventId: LocalFirstIdGenerator.uuidV7(),
      syncStatus: needSync ? SyncStatus.pending : SyncStatus.ok,
      syncOperation: SyncOperation.delete,
    );

    await _client.localStorage.delete(name, getId(deleted.state));
    await _client.localStorage.insertEvent(
      name,
      _toEventJson(deleted),
      '_event_id',
    );
    await _markOlderEventsAsSynced(
      getId(deleted.state),
      excludeEventId: deleted.eventId,
    );
  }

  Map<String, dynamic> _toDataJson(LocalFirstEvent<T> model) {
    return {
      ...toJson(model.state),
      '_last_event_id': model.eventId,
    };
  }

  Map<String, dynamic> _toEventJson(LocalFirstEvent<T> model) {
    final createdAt = model.syncCreatedAt.toUtc();
    return {
      '_event_id': model.eventId,
      '_data_id': getId(model.state),
      '_sync_status': model.syncStatus.index,
      '_sync_operation': model.syncOperation.index,
      '_sync_created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  Future<void> _persistEvent(LocalFirstEvent<T> event) async {
    await _client.localStorage.updateEvent(
      name,
      event.eventId,
      _toEventJson(event),
    );
  }

  LocalFirstEvent<T> _prepareForInsert(
    LocalFirstEvent<T> model, {
    required bool needSync,
  }) {
    return model.copyWith(
      eventId: LocalFirstIdGenerator.uuidV7(),
      syncStatus: needSync ? SyncStatus.pending : SyncStatus.ok,
      syncOperation: SyncOperation.insert,
      syncCreatedAt: model.syncCreatedAt,
      repositoryName: name,
    );
  }

  LocalFirstEvent<T> _prepareForUpdate(
    LocalFirstEvent<T> model, {
    required bool needSync,
  }) {
    final wasPendingInsert =
        model.needSync && model.syncOperation == SyncOperation.insert;
    final existingCreatedAt = model.syncCreatedAt;

    final operation = wasPendingInsert
        ? SyncOperation.insert
        : SyncOperation.update;
    return model.copyWith(
      eventId: LocalFirstIdGenerator.uuidV7(),
      syncStatus: needSync ? SyncStatus.pending : SyncStatus.ok,
      syncOperation: operation,
      repositoryName: name,
      syncCreatedAt: existingCreatedAt,
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
  LocalFirstQuery<T> query({bool includeDeleted = false}) {
    return LocalFirstQuery<T>(
      repositoryName: name,
      delegate: _client.localStorage,
      fromJson: fromJson,
      repository: this,
      includeDeleted: includeDeleted,
    );
  }

  /// Merges remote state events into the local state table and log.
  Future<void> _mergeRemoteEvents(List<dynamic> remoteEvents) async {
    final typedRemote = remoteEvents.cast<LocalFirstEvent<T>>();
    final LocalFirstEvents<T> allLocal = await _getAll(includeDeleted: true);
    final Map<String, LocalFirstEvent<T>> localMap = {
      for (var obj in allLocal) getId(obj.state): obj,
    };

    for (final LocalFirstEvent<T> remoteEvent in typedRemote) {
      final remoteId = getId(remoteEvent.state);
      final remoteOk = remoteEvent.copyWith(syncStatus: SyncStatus.ok);
      final localEvent = localMap[remoteId];

      if (remoteEvent.isDeleted) {
        final deleted = remoteOk.copyWith(syncOperation: SyncOperation.delete);
        await _client.localStorage.insertEvent(
          name,
          _toEventJson(deleted),
          '_event_id',
        );
        await _client.localStorage.delete(name, remoteId);
        await _markOlderEventsAsSynced(
          remoteId,
          excludeEventId: remoteOk.eventId,
        );
        continue;
      }

      if (localEvent == null) {
        await _client.localStorage.insert(
          name,
          _toDataJson(remoteOk),
          idFieldName,
        );
        await _persistEvent(remoteOk);
        await _markOlderEventsAsSynced(
          remoteId,
          excludeEventId: remoteOk.eventId,
        );
        continue;
      }

      if (remoteEvent.eventId == localEvent.eventId) {
        final confirmed = remoteOk.copyWith(
          syncCreatedAt: localEvent.syncCreatedAt,
          syncOperation: localEvent.syncOperation,
        );
        await _client.localStorage.update(
          name,
          remoteId,
          _toDataJson(confirmed),
        );
        await _persistEvent(confirmed);
        continue;
      }

      final resolvedPayload = resolveConflict(
        localEvent.state,
        remoteEvent.state,
      );
      final resolved = LocalFirstEvent<T>(
        state: resolvedPayload,
        eventId: remoteEvent.eventId,
        syncStatus: SyncStatus.ok,
        syncOperation: SyncOperation.update,
        repositoryName: name,
        syncCreatedAt: localEvent.syncCreatedAt,
      );
      await _client.localStorage.update(
        name,
        remoteId,
        _toDataJson(resolved),
      );
      await _persistEvent(resolved);
      await _markOlderEventsAsSynced(
        remoteId,
        excludeEventId: resolved.eventId,
      );
    }
  }

  /// Returns all state events that still require sync.
  Future<List<LocalFirstEvent<T>>> getPendingEvents() async {
    final allEvents = await _getAllEvents();
    return allEvents.where((event) => event.needSync).toList();
  }

  Future<List<LocalFirstEvent<T>>> _getAll({
    bool includeDeleted = false,
  }) async {
    final maps = await _client.localStorage.getAll(name);
    return maps //
        .map(_eventFromJson)
        .where((obj) => includeDeleted || !obj.isDeleted)
        .toList();
  }

  Future<List<LocalFirstEvent<T>>> _getAllEvents() async {
    final maps = await _client.localStorage.getAllEvents(name);
    return maps.map(_eventFromJson).toList();
  }

  Future<void> _markOlderEventsAsSynced(
    String dataId, {
    String? excludeEventId,
  }) async {
    final events = await _getAllEvents();
    for (final event in events) {
      final sameData = getId(event.state) == dataId;
      final isExcluded =
          excludeEventId != null && event.eventId == excludeEventId;
      if (!sameData || isExcluded || !event.needSync) continue;

      final updated = event.copyWith(syncStatus: SyncStatus.ok);
      await _client.localStorage.updateEvent(
        name,
        updated.eventId,
        _toEventJson(updated),
      );
    }
  }

  Future<void> _updateEventStatus(LocalFirstEvent<T> event) async {
    await _client.localStorage.update(
      name,
      getId(event.state),
      _toDataJson(event),
    );
    await _client.localStorage.updateEvent(
      name,
      event.eventId,
      _toEventJson(event),
    );
  }

  LocalFirstEvent<T> _eventFromJson(Map<String, dynamic> json) {
    final itemJson = Map<String, dynamic>.from(json);
    final dataId = itemJson['_data_id'] as String?;
    final lastEventId = itemJson.remove('_last_event_id') as String?;
    final statusIndex = itemJson.remove('_sync_status') as int?;
    final opIndex = itemJson.remove('_sync_operation') as int?;
    final createdAtMs = itemJson.remove('_sync_created_at') as int?;
    final eventId = itemJson.remove('_event_id') as String?;
    itemJson.remove('_data_id');
    // Ensure we have an id for deletes when data row was removed.
    itemJson.putIfAbsent(idFieldName, () => dataId);

    final model = fromJson(itemJson);
    return LocalFirstEvent<T>(
      state: model,
      eventId: eventId ?? lastEventId ?? LocalFirstIdGenerator.uuidV7(),
      syncStatus: statusIndex != null
          ? SyncStatus.values[statusIndex]
          : SyncStatus.ok,
      syncOperation: opIndex != null
          ? SyncOperation.values[opIndex]
          : SyncOperation.insert,
      syncCreatedAt: createdAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true)
          : DateTime.now().toUtc(),
      repositoryName: name,
    );
  }

  LocalFirstEvent<T> _copyEvent(
    LocalFirstEvent<T> target,
    LocalFirstEvent<T> source,
  ) {
    // Shallow copy via JSON round-trip using existing serializers.
    final mergedPayload = _fromJson({
      ..._toJson(target.state),
      ..._toJson(source.state),
    });

    return LocalFirstEvent<T>(
      state: mergedPayload,
      eventId: target.eventId,
      syncStatus: target.syncStatus,
      syncOperation: target.syncOperation,
      syncCreatedAt: target.syncCreatedAt,
      repositoryName: target.repositoryName.isNotEmpty
          ? target.repositoryName
          : source.repositoryName,
    );
  }

  LocalFirstEvent<T> _buildRemoteObject(
    Map<String, dynamic> json, {
    required SyncOperation operation,
  }) {
    final model = _fromJson(json);
    final eventId = json['event_id']?.toString();
    return LocalFirstEvent<T>(
      state: model,
      eventId: eventId,
      syncStatus: SyncStatus.ok,
      syncOperation: operation,
      repositoryName: name,
      syncCreatedAt: DateTime.now().toUtc(),
    );
  }

  Future<LocalFirstEvent<T>?> _getById(String id) async {
    final json = await _client.localStorage.getById(name, id);
    if (json == null) {
      return null;
    }
    return _eventFromJson(json);
  }
}

final class _LocalFirstRepository<T> extends LocalFirstRepository<T> {
  _LocalFirstRepository({
    required super.name,
    required super.getId,
    required super.toJson,
    required super.fromJson,
    required super.onConflict,
    super.idFieldName = 'id',
    super.schema = const {},
  });
}
