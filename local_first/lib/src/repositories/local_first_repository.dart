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
mixin LocalFirstRepository<T> {
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
  static LocalFirstRepository<T> create<T>({
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

  Future<void> _pushLocalEvent(LocalFirstEvent<T> event) async {
    for (var strategy in _syncStrategies) {
      if (!strategy.supportsEvent(event)) {
        continue;
      }
      try {
        final syncResult = await strategy.onPushToRemote(event as dynamic);
        event._setSyncStatus(syncResult);
        if (syncResult == SyncStatus.ok) return;
      } catch (e) {
        event._setSyncStatus(SyncStatus.failed);
      }
    }
    await _updateEventStatus(event);
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
      final merged = _copyModel(existing.data, item);
      final wasPendingInsert =
          existing.needSync && existing.syncOperation == SyncOperation.insert;
      await _update(
        _prepareForUpdate(existing, merged),
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

    final pushFuture = _pushLocalEvent(event);
    await Future.wait([pushFuture, insertFuture]);
  }

  Future<void> _update(
    LocalFirstEvent<T> event, {
    required bool wasPendingInsert,
  }) async {
    final operation =
        wasPendingInsert ? SyncOperation.insert : SyncOperation.update;
    event._setSyncStatus(SyncStatus.pending);
    event._setSyncOperation(operation);

    await _client.localStorage.update(
      name,
      getId(event.data),
      _toStorageJson(event),
    );

    await _pushLocalEvent(event);
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

    event._setSyncStatus(SyncStatus.pending);
    event._setSyncOperation(SyncOperation.delete);

    await _client.localStorage.update(
      name,
      getId(event.data),
      _toStorageJson(event),
    );
  }

  Map<String, dynamic> _toStorageJson(LocalFirstEvent<T> event) {
    return {
      ...toJson(event.data),
      '_sync_status': event.syncStatus.index,
      '_sync_operation': event.syncOperation.index,
      '_sync_created_at':
          event.syncCreatedAt?.millisecondsSinceEpoch ??
          DateTime.now().toUtc().millisecondsSinceEpoch,
    };
  }

  LocalFirstEvent<T> _prepareForInsert(T model) {
    return LocalFirstEvent<T>(
      data: model,
      syncStatus: SyncStatus.pending,
      syncOperation: SyncOperation.insert,
      syncCreatedAt: DateTime.now().toUtc(),
      repositoryName: name,
    );
  }

  LocalFirstEvent<T> _prepareForUpdate(
    LocalFirstEvent<T> existing,
    T model,
  ) {
    return LocalFirstEvent<T>(
      data: model,
      syncStatus: existing.syncStatus,
      syncOperation: existing.syncOperation,
      syncCreatedAt: existing.syncCreatedAt ?? DateTime.now().toUtc(),
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
    final Map<String, LocalFirstEvent<T>> localMap = {
      for (var event in allLocal) getId(event.data): event,
    };

    for (final remoteEvent in remoteEvents) {
      final data = remoteEvent.data;
      if (data is! T) {
        continue;
      }
      final remoteObj = data;
      final remoteId = getId(remoteObj);
      final localEvent = localMap[remoteId];

      if (remoteEvent.isDeleted) {
        if (localEvent != null && !localEvent.needSync) {
          await _client.localStorage.delete(name, remoteId);
        }
        continue;
      }

      if (localEvent == null) {
        final insertEvent = LocalFirstEvent<T>(
          data: remoteObj,
          syncStatus: SyncStatus.ok,
          syncOperation: remoteEvent.syncOperation,
          syncCreatedAt:
              remoteEvent.syncCreatedAt ?? DateTime.now().toUtc(),
          repositoryName: name,
        );
        await _client.localStorage.insert(
          name,
          _toStorageJson(insertEvent),
          idFieldName,
        );
        continue;
      }

      final resolved = resolveConflict(localEvent.data, remoteObj);
      final updatedEvent = LocalFirstEvent<T>(
        data: resolved,
        syncStatus: SyncStatus.ok,
        syncOperation: SyncOperation.update,
        syncCreatedAt:
            remoteEvent.syncCreatedAt ?? DateTime.now().toUtc(),
        repositoryName: name,
      );
      await _client.localStorage.update(
        name,
        remoteId,
        _toStorageJson(updatedEvent),
      );
    }
  }

  Future<List<LocalFirstEvent<T>>> getPendingObjects() async {
    final allObjects = await _getAllEvents(includeDeleted: true);
    return allObjects.where((event) => event.needSync).toList();
  }

  Future<List<LocalFirstEvent<T>>> _getAllEvents({
    bool includeDeleted = false,
  }) async {
    final maps = await _client.localStorage.getAll(name);
    return maps //
        .map(_eventFromJson)
        .where((event) => includeDeleted || !event.isDeleted)
        .toList();
  }

  Future<void> _updateEventStatus(LocalFirstEvent<T> event) async {
    await _client.localStorage.update(
      name,
      getId(event.data),
      _toStorageJson(event),
    );
  }

  LocalFirstEvent<T> _eventFromJson(Map<String, dynamic> json) {
    final itemJson = Map<String, dynamic>.from(json);
    final statusIndex = itemJson.remove('_sync_status') as int?;
    final opIndex = itemJson.remove('_sync_operation') as int?;
    final createdAtMs = itemJson.remove('_sync_created_at') as int?;

    final model = fromJson(itemJson);
    return LocalFirstEvent<T>(
      data: model,
      syncStatus:
          statusIndex != null ? SyncStatus.values[statusIndex] : SyncStatus.ok,
      syncOperation: opIndex != null
          ? SyncOperation.values[opIndex]
          : SyncOperation.insert,
      syncCreatedAt:
          createdAtMs != null
              ? DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true)
              : null,
      repositoryName: name,
    );
  }

  T _copyModel(T target, T source) {
    // Shallow copy via JSON round-trip using existing serializers.
    return _fromJson({..._toJson(target), ..._toJson(source)});
  }

  LocalFirstEvent<T> _buildRemoteEvent(
    Map<String, dynamic> json, {
    required SyncOperation operation,
  }) {
    return LocalFirstEvent<T>(
      data: _fromJson(json),
      syncStatus: SyncStatus.ok,
      syncOperation: operation,
      syncCreatedAt: DateTime.now().toUtc(),
      repositoryName: name,
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

final class _LocalFirstRepository<T>
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
