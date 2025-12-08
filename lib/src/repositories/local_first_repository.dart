part of '../../local_first.dart';

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
abstract class LocalFirstRepository<T extends Object> {
  /// The unique name identifier for this repository.
  final String name;

  /// Serialization helpers for the repository items.
  final String Function(T item) _getId;
  final Map<String, dynamic> Function(T item) _toJson;
  final T Function(Map<String, dynamic> json) _fromJson;
  final LocalFirstModel<T> Function(
    LocalFirstModel<T> local,
    LocalFirstModel<T> remote,
  )
  _resolveConflict;

  /// Field name used as identifier in persisted maps.
  final String idFieldName;

  late LocalFirstClient _client;

  late List<DataSyncStrategy> _syncStrategies;

  @visibleForTesting
  void injectDB(LocalFirstClient client) => _client = client;

  /// Creates a new LocalFirstRepository.
  ///
  /// Parameters:
  /// - [name]: Unique identifier for this repository
  /// - [getId]: Returns the primary key of the model
  /// - [toJson]: Serializes the model to Map
  /// - [fromJson]: Deserializes the model from Map
  /// - [onConflict]: Resolves conflicts between local/remote models
  /// - [idFieldName]: Key used to persist the model id (default: `id`)
  LocalFirstRepository({
    required this.name,
    required String Function(T item) getId,
    required Map<String, dynamic> Function(T item) toJson,
    required T Function(Map<String, dynamic>) fromJson,
    required LocalFirstModel<T> Function(
      LocalFirstModel<T> local,
      LocalFirstModel<T> remote,
    )
    onConflict,
    this.idFieldName = 'id',
  }) : _getId = getId,
       _toJson = toJson,
       _fromJson = fromJson,
       _resolveConflict = onConflict;

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
    required LocalFirstModel<T> Function(
      LocalFirstModel<T> local,
      LocalFirstModel<T> remote,
    )
    onConflict,
    String idFieldName,
  }) = _LocalFirstRepository;

  String getId(T item) => _getId(item);
  Map<String, dynamic> toJson(T item) => _toJson(item);
  T fromJson(Map<String, dynamic> json) => _fromJson(json);
  LocalFirstModel<T> resolveConflict(
    LocalFirstModel<T> local,
    LocalFirstModel<T> remote,
  ) => _resolveConflict(local, remote);

  bool _isInitialized = false;

  /// Initializes the repository.
  ///
  /// This is called automatically by [LocalFirstClient.initialize].
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
  }

  /// Resets the repository's initialization state.
  ///
  /// Used internally when clearing all data.
  void reset() {
    _isInitialized = false;
  }

  Future<void> _pushLocalObject(LocalFirstModel<T> object) async {
    for (var strategy in _syncStrategies) {
      try {
        final syncResult = await strategy.onPushToRemote(object);
        if (syncResult != object.status) {
          object._repository._updateObjectStatus(
            object.copyWith(status: syncResult),
          );
        }
        switch (syncResult) {
          case SyncStatus.ok:
            return;
          case SyncStatus.pending:
          case SyncStatus.failed:
            continue;
        }
      } catch (e) {
        object._repository._updateObjectStatus(
          object.copyWith(status: SyncStatus.failed),
        );
      }
    }
  }

  /// Inserts or updates an item (upsert operation).
  ///
  /// If an item with the same ID already exists, it will be updated.
  /// Otherwise, a new item will be inserted.
  ///
  /// The operation is marked as pending and will be synced on next [LocalFirstClient.sync].
  Future<void> upsert(T item) async {
    final json = await _client.localDataSource.getById(name, getId(item));
    if (json != null) {
      await _update(_offlineObjectFromJson(json).copyWith(item: item));
    } else {
      await _insert(item);
    }
  }

  Future<void> _insert(T item) async {
    final offlineObj = LocalFirstModel(
      item: item,
      status: SyncStatus.pending,
      operation: SyncOperation.insert,
      repository: this,
    );

    final insertFuture = _client.localDataSource.insert(
      name,
      offlineObj.toJson(),
      idFieldName,
    );

    final pushFuture = _pushLocalObject(offlineObj);
    await Future.wait([pushFuture, insertFuture]);
  }

  Future<void> _update(LocalFirstModel<T> object) async {
    final updatedObj = object.copyWith(
      status: SyncStatus.pending,
      operation: object.needSync && object.operation == SyncOperation.insert
          ? SyncOperation.insert
          : SyncOperation.update,
    );

    await _client.localDataSource.update(
      name,
      getId(object.item),
      updatedObj.toJson(),
    );

    await _pushLocalObject(updatedObj);
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
    final json = await _client.localDataSource.getById(name, id);
    if (json == null) {
      return;
    }

    final object = _offlineObjectFromJson(json);

    if (object.needSync && object.operation == SyncOperation.insert) {
      await _client.localDataSource.delete(name, id);
      return;
    }

    await _client.localDataSource.update(
      name,
      getId(object.item),
      object //
          .copyWith(status: SyncStatus.pending, operation: SyncOperation.delete)
          .toJson(),
    );
  }

  /// Creates a query for this node.
  ///
  /// Use this to perform filtered, ordered, and paginated queries.
  ///
  /// Example:
  /// ```dart
  /// final activeUsers = await userNode
  ///   .query()
  ///   .where('status', isEqualTo: 'active')
  ///   .getAll();
  /// ```
  LocalFirstQuery<T> query() {
    return LocalFirstQuery<T>(
      repositoryName: name,
      delegate: _client.localDataSource,
      fromJson: fromJson,
      repository: this,
    );
  }

  Future<void> _mergeRemoteItems(LocalFirstModels remoteObjects) async {
    final LocalFirstModels<T> allLocal = await _getAll(includeDeleted: true);
    final Map<String, LocalFirstModel<T>> localMap = {
      for (var obj in allLocal) getId(obj.item): obj,
    };

    for (final LocalFirstModel remote in remoteObjects) {
      final remoteObj = remote as LocalFirstModel<T>;
      final remoteId = getId(remoteObj.item);
      final localObj = localMap[remoteId];

      if (remoteObj.isDeleted) {
        if (localObj != null && !localObj.needSync) {
          await _client.localDataSource.delete(name, remoteId);
        }
        continue;
      }

      if (localObj == null) {
        await _client.localDataSource.insert(
          name,
          remoteObj.toJson(),
          idFieldName,
        );
        continue;
      }

      final resolved = resolveConflict(localObj, remoteObj);
      final updatedObj = resolved.copyWith(
        status: SyncStatus.ok,
        operation: SyncOperation.update,
      );
      await _client.localDataSource.update(name, remoteId, updatedObj.toJson());
    }
  }

  Future<List<LocalFirstModel<T>>> getPendingObjects() async {
    final allObjects = await _getAll(includeDeleted: true);
    return allObjects.where((obj) => obj.needSync).toList();
  }

  Future<List<LocalFirstModel<T>>> _getAll({
    bool includeDeleted = false,
  }) async {
    final maps = await _client.localDataSource.getAll(name);
    return maps
        .map(_offlineObjectFromJson)
        .where((obj) => includeDeleted || !obj.isDeleted)
        .toList();
  }

  Future<void> _updateObjectStatus(LocalFirstModel obj) async {
    await _client.localDataSource.update(
      name,
      getId(obj.item as T),
      obj.toJson(),
    );
  }

  LocalFirstModel<T> _offlineObjectFromJson(Map<String, dynamic> json) {
    final status = SyncStatus.values[json['_sync_status'] as int];
    final operation = SyncOperation.values[json['_sync_operation'] as int];

    final itemJson = Map<String, dynamic>.from(json)
      ..remove('_sync_status')
      ..remove('_sync_operation')
      ..remove('_sync_created_at');

    return LocalFirstModel(
      item: fromJson(itemJson),
      status: status,
      operation: operation,
      repository: this,
    );
  }

  LocalFirstModel<T> _buildRemoteObject(
    Map<String, dynamic> json, {
    required SyncOperation operation,
  }) {
    return LocalFirstModel<T>(
      item: _fromJson(json),
      status: SyncStatus.ok,
      operation: operation,
      repository: this,
    );
  }

  Future<LocalFirstModel<T>?> _getById(String id) async {
    final json = await _client.localDataSource.getById(name, id);
    if (json == null) {
      return null;
    }
    return _offlineObjectFromJson(json);
  }
}

final class _LocalFirstRepository<T extends Object>
    extends LocalFirstRepository<T> {
  _LocalFirstRepository({
    required super.name,
    required super.getId,
    required super.toJson,
    required super.fromJson,
    required super.onConflict,
    super.idFieldName,
  });
}
