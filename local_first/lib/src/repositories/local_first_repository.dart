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
  final JsonMap Function(T item) _toJson;
  final T Function(JsonMap json) _fromJson;
  final LocalFirstEvent<T> Function(
    LocalFirstEvent<T> local,
    LocalFirstEvent<T> remote,
  )?
  _resolveConflictEvent;

  /// Field name used as identifier in persisted maps.
  final String idFieldName;

  /// Schema definition for native storage backends (e.g. SQLite).
  final JsonMap<LocalFieldType> schema;

  late LocalFirstClient _client;

  late List<DataSyncStrategy> _syncStrategies;

  /// Creates a new LocalFirstRepository.
  ///
  /// Parameters:
  /// - [name]: Unique identifier for this repository
  /// - [getId]: Returns the primary key of the model
  /// - [toJson]: Serializes the model to Map
  /// - [fromJson]: Deserializes the model from Map
  /// - [onConflict]: Resolves conflicts between local/remote models (state only)
  /// - [onConflictEvent]: Resolves conflicts using full event metadata
  /// - [idFieldName]: Key used to persist the model id (default: `id`)
  /// - [schema]: Optional schema used by SQL backends for column creation
  LocalFirstRepository({
    required this.name,
    required String Function(T item) getId,
    required JsonMap Function(T item) toJson,
    required T Function(JsonMap) fromJson,
    LocalFirstEvent<T> Function(
      LocalFirstEvent<T> local,
      LocalFirstEvent<T> remote,
    )?
    onConflictEvent,
    this.idFieldName = 'id',
    JsonMap<LocalFieldType> schema = const {},
  }) : _getId = getId,
       _toJson = toJson,
       _fromJson = fromJson,
       _resolveConflictEvent = onConflictEvent,
       schema = Map.unmodifiable(schema);

  /// Creates a configured instance of LocalFirstRepository.
  ///
  /// Use this factory when you prefer not to use inheritance.
  factory LocalFirstRepository.create({
    required String name,
    required String Function(T item) getId,
    required JsonMap Function(T item) toJson,
    required T Function(JsonMap) fromJson,
    LocalFirstEvent<T> Function(
      LocalFirstEvent<T> local,
      LocalFirstEvent<T> remote,
    )?
    onConflictEvent,
    String idFieldName,
    JsonMap<LocalFieldType> schema,
  }) = _LocalFirstRepository;

  String getId(T item) => _getId(item);
  JsonMap toJson(T item) => _toJson(item);
  T fromJson(JsonMap json) => _fromJson(json);

  LocalFirstEvent<T> resolveConflictEvent(
    LocalFirstEvent<T> local,
    LocalFirstEvent<T> remote,
  ) {
    if (_resolveConflictEvent != null) {
      return _resolveConflictEvent(local, remote);
    }
    return ConflictUtil.lastWriteWins(local, remote);
  }

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
  Future<LocalFirstEvent<T>> _pushLocalEventToRemote(
    LocalFirstEvent<T> event,
  ) async {
    var current = event;

    for (var strategy in _syncStrategies) {
      try {
        final syncResult = await strategy.onPushToRemote(current);
        current = current.copyWith(syncStatus: syncResult);
        if (syncResult == SyncStatus.ok) {
          await _updateEventStatus(current);
          return current;
        }
      } catch (_) {
        current = current.copyWith(syncStatus: SyncStatus.failed);
      }
    }

    await _updateEventStatus(current);
    return current;
  }

  /// Inserts or updates an item (upsert operation).
  Future<void> upsert(dynamic item, {bool needSync = true}) async {
    final exists = await _client.localStorage.containsId(name, getId(item));
    final LocalFirstEvent<T> event = item is LocalFirstEvent<T>
        ? item
        : LocalFirstEvent<T>.createNewEvent(
            repository: this,
            state: item as T,
            syncOperation: exists ? SyncOperation.update : SyncOperation.insert,
            syncStatus: needSync ? SyncStatus.pending : SyncStatus.ok,
          );
    await Future.wait([
      if (exists) _updateDataAndEvent(event as LocalFirstStateEvent<T>),
      if (!exists) _insertDataAndEvent(event as LocalFirstStateEvent<T>),
      if (needSync) _pushLocalEventToRemote(event),
    ]);
  }

  /// Deletes an item by its ID (soft delete).
  Future<void> delete(String id, {required bool needSync}) async {
    final events = await _getAllEvents();
    final existing = events
        .where((event) => event.dataId == id)
        .fold<LocalFirstEvent<T>?>(null, (latest, current) {
      if (latest == null) return current;
      return current.syncCreatedAt.isAfter(latest.syncCreatedAt)
          ? current
          : latest;
    });
    if (existing == null) return;

    final deleted = LocalFirstEvent<T>.createNewEvent(
      repository: this,
      syncStatus: needSync ? SyncStatus.pending : SyncStatus.ok,
      syncOperation: SyncOperation.delete,
      dataId: id,
      state: existing is LocalFirstStateEvent<T> ? existing.state : null,
    );

    await _deleteDataAndLogEvent(deleted);
    await _markAllPreviousEventAsOk(deleted);
  }

  JsonMap _toDataJson(LocalFirstStateEvent<T> model) {
    return {
      ...toJson(model.state),
      LocalFirstEvent.kLastEventId: model.eventId,
    };
  }

  Future<void> _persistEvent(LocalFirstEvent<T> event) async {
    await _updateEventRecord(event);
  }

  /// Creates a query for this node.
  LocalFirstQuery<T> query({bool includeDeleted = false}) {
    return LocalFirstQuery<T>(
      repositoryName: name,
      delegate: _client.localStorage,
      fromJson: fromJson,
      repository: this,
      includeDeleted: includeDeleted,
    );
  }

  /// Applies a single remote event, handling operation-specific logic.
  Future<void> mergeRemoteEvent({
    required LocalFirstEvent<T> remoteEvent,
  }) async {
    final typedRemote = remoteEvent.copyWith(syncStatus: SyncStatus.ok);

    final LocalFirstEvent<T>? localPendingEvent =
        await getLastRespectivePendingEvent(reference: typedRemote);

    if (localPendingEvent != null &&
        localPendingEvent.eventId == remoteEvent.eventId) {
      return _confirmEvent(
        remoteEvent: typedRemote,
        localPendingEvent: localPendingEvent,
      );
    }

    return switch (typedRemote.syncOperation) {
      SyncOperation.insert => _mergeInsertEvent(
        remoteEvent: typedRemote as LocalFirstStateEvent<T>,
        localPendingEvent: localPendingEvent,
      ),
      SyncOperation.update => _mergeUpdateEvent(
        remoteEvent: typedRemote as LocalFirstStateEvent<T>,
        localPendingEvent: localPendingEvent,
      ),
      SyncOperation.delete => _mergeDeleteEvent(
        remoteEvent: typedRemote,
        localPendingEvent: localPendingEvent,
      ),
    };
  }

  Future<void> _confirmEvent({
    required LocalFirstEvent<T> remoteEvent,
    required LocalFirstEvent<T> localPendingEvent,
  }) async {
    final confirmed = remoteEvent.copyWith(
      syncCreatedAt: localPendingEvent.syncCreatedAt,
      syncOperation: localPendingEvent.syncOperation,
    );
    await _persistEvent(confirmed);
    await _markAllPreviousEventAsOk(confirmed);
  }

  Future<void> _mergeInsertEvent({
    required LocalFirstStateEvent<T> remoteEvent,
    required LocalFirstEvent<T>? localPendingEvent,
  }) async {
    if (localPendingEvent == null) {
      await _insertDataAndEvent(remoteEvent);
      await _markAllPreviousEventAsOk(remoteEvent);
      return;
    }

    final resolved = resolveConflictEvent(
      localPendingEvent as LocalFirstStateEvent<T>,
      remoteEvent,
    );
    await _updateDataAndEvent(resolved);
    await _markAllPreviousEventAsOk(resolved);
  }

  Future<void> _mergeUpdateEvent({
    required LocalFirstStateEvent<T> remoteEvent,
    required LocalFirstEvent<T>? localPendingEvent,
  }) async {
    if (localPendingEvent == null) {
      final insertLike = remoteEvent.copyWith(
        syncStatus: SyncStatus.ok,
        syncOperation: SyncOperation.insert,
      );
      await _insertDataAndEvent(insertLike);
      await _markAllPreviousEventAsOk(insertLike);
      return;
    }

    if (remoteEvent.eventId == localPendingEvent.eventId) {
      final confirmed = remoteEvent.copyWith(
        syncStatus: SyncStatus.ok,
        syncCreatedAt: localPendingEvent.syncCreatedAt,
        syncOperation: localPendingEvent.syncOperation,
      );
      await _updateDataAndEvent(confirmed);
      await _markAllPreviousEventAsOk(confirmed);
      return;
    }

    final resolved = resolveConflictEvent(
      localPendingEvent as LocalFirstStateEvent<T>,
      remoteEvent,
    );
    await _updateDataAndEvent(resolved);
    await _markAllPreviousEventAsOk(resolved);
  }

  Future<void> _mergeDeleteEvent({
    required LocalFirstEvent<T> remoteEvent,
    required LocalFirstEvent<T>? localPendingEvent,
  }) async {
    final deleted = remoteEvent.copyWith(syncStatus: SyncStatus.ok);
    await _deleteDataAndLogEvent(deleted);
    await _markAllPreviousEventAsOk(localPendingEvent ?? deleted);
  }

  /// Returns all state events that still require sync.
  Future<List<LocalFirstEvent<T>>> getPendingEvents() async {
    final allEvents = await _getAllEvents();
    return allEvents.where((event) => event.needSync).toList();
  }

  Future<List<LocalFirstEvent<T>>> _getAllEvents() async {
    final maps = await _client.localStorage.getAllEvents(name);
    return maps
        .map(
          (json) =>
              LocalFirstEvent<T>.fromLocalStorage(repository: this, json: json),
        )
        .toList();
  }

  Future<LocalFirstEvent<T>?> getLastRespectivePendingEvent({
    required LocalFirstEvent<T> reference,
  }) async {
    final referenceId = reference.dataId;
    final events = await _getAllEvents();
    final pendingForId = events.where(
      (event) => event.needSync && event.dataId == referenceId,
    );
    if (pendingForId.isEmpty) return null;

    return pendingForId.reduce(
      (a, b) => b.syncCreatedAt.isAfter(a.syncCreatedAt) ? b : a,
    );
  }

  Future<void> _markAllPreviousEventAsOk(LocalFirstEvent<T> reference) async {
    final events = await _getAllEvents();
    for (final event in events) {
      final sameData = event.dataId == reference.dataId;
      final isCurrentOrNewer = !event.syncCreatedAt.isBefore(
        reference.syncCreatedAt,
      );
      if (!sameData || isCurrentOrNewer) continue;

      final updated = event.copyWith(syncStatus: SyncStatus.ok);
      await _updateEventRecord(updated);
    }
  }

  Future<void> _insertDataAndEvent(LocalFirstStateEvent<T> event) async {
    await Future.wait([_insertDataFromEvent(event), _persistEvent(event)]);
  }

  Future<void> _updateDataAndEvent(LocalFirstEvent<T> event) async {
    await Future.wait([
      if (event is LocalFirstStateEvent<T>) _updateDataFromEvent(event),
      _persistEvent(event),
    ]);
  }

  Future<void> _deleteDataAndLogEvent(LocalFirstEvent<T> event) async {
    await Future.wait([
      _insertEventRecord(event),
      _deleteDataById(event.dataId),
    ]);
  }

  Future<void> _insertDataFromEvent(LocalFirstStateEvent<T> event) {
    return _client.localStorage.insert(name, _toDataJson(event), idFieldName);
  }

  Future<void> _updateDataFromEvent(LocalFirstStateEvent<T> event) {
    return _client.localStorage.update(
      name,
      event.dataId,
      _toDataJson(event),
    );
  }

  Future<void> _insertEventRecord(LocalFirstEvent<T> event) {
    return _client.localStorage.insertEvent(
      name,
      event.toLocalStorageJson(),
      LocalFirstEvent.kEventId,
    );
  }

  Future<void> _updateEventRecord(LocalFirstEvent<T> event) {
    return _client.localStorage.updateEvent(
      name,
      event.eventId,
      event.toLocalStorageJson(),
    );
  }

  Future<void> _deleteDataById(String id) {
    return _client.localStorage.delete(name, id);
  }

  Future<void> _updateEventStatus(LocalFirstEvent<T> event) async {
    if (event is LocalFirstStateEvent<T>) {
      await _updateDataFromEvent(event);
    }
    await _updateEventRecord(event);
  }
}

final class _LocalFirstRepository<T> extends LocalFirstRepository<T> {
  _LocalFirstRepository({
    required super.name,
    required super.getId,
    required super.toJson,
    required super.fromJson,
    super.onConflictEvent,
    super.idFieldName = 'id',
    super.schema = const {},
  });
}
