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
abstract class LocalFirstRepository<T extends LocalFirstModel> {
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

  Future<void> _pushLocalObject(T object) async {
    for (var strategy in _syncStrategies) {
      try {
        final syncResult = await strategy.onPushToRemote(object);
        object._setSyncStatus(syncResult);
        if (syncResult == SyncStatus.ok) return;
      } catch (e) {
        object._setSyncStatus(SyncStatus.failed);
      }
    }
    await _updateObjectStatus(object);
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
      final existing = _modelFromJson(json);
      await _update(_prepareForUpdate(_copyModel(existing, item)));
    } else {
      await _insert(item);
    }
  }

  Future<void> _insert(T item) async {
    final model = _prepareForInsert(item);

    final insertFuture = _client.localStorage.insert(
      name,
      _toStorageJson(model),
      idFieldName,
    );

    final pushFuture = _pushLocalObject(model);
    await Future.wait([pushFuture, insertFuture]);
  }

  Future<void> _update(T object) async {
    final operation =
        object.needSync && object.syncOperation == SyncOperation.insert
        ? SyncOperation.insert
        : SyncOperation.update;
    object._setSyncStatus(SyncStatus.pending);
    object._setSyncOperation(operation);

    await _client.localStorage.update(
      name,
      getId(object),
      _toStorageJson(object),
    );

    await _pushLocalObject(object);
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

    final object = _modelFromJson(json);

    if (object.needSync && object.syncOperation == SyncOperation.insert) {
      await _client.localStorage.delete(name, id);
      return;
    }

    object._setSyncStatus(SyncStatus.pending);
    object._setSyncOperation(SyncOperation.delete);

    await _client.localStorage.update(
      name,
      getId(object),
      _toStorageJson(object),
    );
  }

  Map<String, dynamic> _toStorageJson(T model) {
    return {
      ...toJson(model),
      '_sync_status': model.syncStatus.index,
      '_sync_operation': model.syncOperation.index,
      '_sync_created_at':
          model.syncCreatedAt?.millisecondsSinceEpoch ??
          DateTime.now().toUtc().millisecondsSinceEpoch,
    };
  }

  T _prepareForInsert(T model) {
    model._setSyncStatus(SyncStatus.pending);
    model._setSyncOperation(SyncOperation.insert);
    model._setSyncCreatedAt(DateTime.now().toUtc());
    model._setRepositoryName(name);
    return model;
  }

  T _prepareForUpdate(T model) {
    final wasPendingInsert =
        model.needSync && model.syncOperation == SyncOperation.insert;
    final existingCreatedAt = model.syncCreatedAt;

    model._setSyncStatus(SyncStatus.pending);
    final operation = wasPendingInsert
        ? SyncOperation.insert
        : SyncOperation.update;
    model._setSyncOperation(operation);
    model._setRepositoryName(name);
    model._setSyncCreatedAt(existingCreatedAt ?? DateTime.now().toUtc());
    return model;
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
      fromJson: fromJson,
      repository: this,
    );
  }

  Future<void> _mergeRemoteItems(List<dynamic> remoteObjects) async {
    final typedRemote = remoteObjects.cast<T>();
    final LocalFirstModels<T> allLocal = await _getAll(includeDeleted: true);
    final Map<String, T> localMap = {for (var obj in allLocal) getId(obj): obj};

    for (final T remoteObj in typedRemote) {
      final remoteId = getId(remoteObj);
      final localObj = localMap[remoteId];

      if (remoteObj.isDeleted) {
        if (localObj != null && !localObj.needSync) {
          await _client.localStorage.delete(name, remoteId);
        }
        continue;
      }

      if (localObj == null) {
        await _client.localStorage.insert(
          name,
          _toStorageJson(remoteObj),
          idFieldName,
        );
        continue;
      }

      final resolved = resolveConflict(localObj, remoteObj);
      resolved._setSyncStatus(SyncStatus.ok);
      resolved._setSyncOperation(SyncOperation.update);
      await _client.localStorage.update(
        name,
        remoteId,
        _toStorageJson(resolved),
      );
    }
  }

  Future<List<T>> getPendingObjects() async {
    final allObjects = await _getAll(includeDeleted: true);
    return allObjects.where((obj) => obj.needSync).toList();
  }

  Future<List<T>> _getAll({bool includeDeleted = false}) async {
    final maps = await _client.localStorage.getAll(name);
    return maps //
        .map(_modelFromJson)
        .where((obj) => includeDeleted || !obj.isDeleted)
        .toList();
  }

  Future<void> _updateObjectStatus(T obj) async {
    await _client.localStorage.update(name, getId(obj), _toStorageJson(obj));
  }

  T _modelFromJson(Map<String, dynamic> json) {
    final itemJson = Map<String, dynamic>.from(json);
    final statusIndex = itemJson.remove('_sync_status') as int?;
    final opIndex = itemJson.remove('_sync_operation') as int?;
    final createdAtMs = itemJson.remove('_sync_created_at') as int?;

    final model = fromJson(itemJson);
    model._setSyncStatus(
      statusIndex != null ? SyncStatus.values[statusIndex] : SyncStatus.ok,
    );
    model._setSyncOperation(
      opIndex != null ? SyncOperation.values[opIndex] : SyncOperation.insert,
    );
    model._setSyncCreatedAt(
      createdAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true)
          : null,
    );
    model._setRepositoryName(name);
    return model;
  }

  T _copyModel(T target, T source) {
    // Shallow copy via JSON round-trip using existing serializers.
    final merged = _fromJson({..._toJson(target), ..._toJson(source)});
    merged._setSyncStatus(target.syncStatus);
    merged._setSyncOperation(target.syncOperation);
    merged._setSyncCreatedAt(target.syncCreatedAt);
    merged._setRepositoryName(target.repositoryName);
    return merged;
  }

  T _buildRemoteObject(
    Map<String, dynamic> json, {
    required SyncOperation operation,
  }) {
    final model = _fromJson(json);
    model._setSyncStatus(SyncStatus.ok);
    model._setSyncOperation(operation);
    model._setRepositoryName(name);
    model._setSyncCreatedAt(model.syncCreatedAt ?? DateTime.now().toUtc());
    return model;
  }

  Future<T?> _getById(String id) async {
    final json = await _client.localStorage.getById(name, id);
    if (json == null) {
      return null;
    }
    return _modelFromJson(json);
  }
}

final class _LocalFirstRepository<T extends LocalFirstModel>
    extends LocalFirstRepository<T> {
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
