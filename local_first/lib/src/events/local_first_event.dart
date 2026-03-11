part of '../../local_first.dart';

/// Represents the synchronization status of an object.
enum SyncStatus {
  /// The object has pending changes that need to be synced.
  pending,

  /// The object is synchronized with the server.
  ok,

  /// The last sync attempt failed (will be retried).
  failed,
}

/// Represents the type of operation performed on an object.
enum SyncOperation {
  /// The object was inserted locally.
  insert,

  /// The object was updated locally.
  update,

  /// The object was deleted locally (soft delete).
  delete,
}

/// Base sync event carrying metadata.
abstract class LocalFirstEvent<T> {
  // Shared payload keys for remote and local.
  // All metadata keys are prefixed with '_' to avoid collision with entity fields.
  static const String kEventId = '_event_id';
  static const String kRepository = '_repository';
  static const String kOperation = '_operation';
  static const String kSyncCreatedAt = '_created_at';
  static const String kData = '_data';
  static const String kDataId = '_data_id';
  static const String kSyncStatus = '_sync_status';
  static const String kLastEventId = '_last_event_id';

  LocalFirstEvent._({
    required this.repository,
    required this.eventId,
    required this.syncStatus,
    required this.syncOperation,
    required this.syncCreatedAt,
  });

  final LocalFirstRepository repository;
  final String eventId;
  final SyncStatus syncStatus;
  final SyncOperation syncOperation;
  final DateTime syncCreatedAt;

  T? get data;
  bool get needSync => syncStatus != SyncStatus.ok;
  bool get isDeleted => syncOperation == SyncOperation.delete;

  /// Must be available for all event kinds.
  String get dataId;

  String get repositoryName => repository.name;

  /// Serialize event to remote JSON.
  JsonMap toJson();

  /// Serialize event metadata for local storage.
  JsonMap toLocalStorageJson();

  /// Clone preserving subtype.
  LocalFirstEvent<T> updateEventState({
    SyncStatus? syncStatus,
    SyncOperation? syncOperation,
  });

  /// Factory used internally to hydrate events stored locally with full metadata.
  factory LocalFirstEvent.fromLocalStorage({
    required LocalFirstRepository repository,
    required JsonMap json,
  }) {
    final itemJson = JsonMap.from(json);
    final dataId = itemJson[kDataId] as String?;
    final lastEventId = itemJson.remove(kLastEventId) as String?;
    final statusIndex = itemJson.remove(kSyncStatus) as int?;
    final opIndex = itemJson.remove(kOperation) as int?;
    final createdAtValue = itemJson.remove(kSyncCreatedAt);
    final eventId = itemJson.remove(kEventId) as String?;
    final createdAt = _parseSyncCreatedAt(createdAtValue);

    if ((eventId ?? lastEventId) == null ||
        statusIndex == null ||
        opIndex == null ||
        createdAt == null) {
      throw FormatException(
        'Invalid local event storage for ${repository.name}',
      );
    }

    final operation = SyncOperation.values[opIndex];
    final baseMeta = (
      id: eventId ?? lastEventId!,
      status: SyncStatus.values[statusIndex],
      createdAt: createdAt,
    );

    if (operation == SyncOperation.delete) {
      if (dataId == null) {
        throw FormatException(
          'Missing data id for delete event in ${repository.name}',
        );
      }
      return LocalFirstDeleteEvent<T>._internal(
        repository: repository,
        eventId: baseMeta.id,
        syncStatus: baseMeta.status,
        syncOperation: operation,
        syncCreatedAt: baseMeta.createdAt,
        dataId: dataId,
      );
    }

    itemJson.remove(kDataId);
    itemJson.putIfAbsent(repository.idFieldName, () => dataId);
    final data = repository.fromJson(itemJson);
    return LocalFirstStateEvent<T>._internal(
      repository: repository,
      data: data,
      eventId: baseMeta.id,
      syncStatus: baseMeta.status,
      syncOperation: operation,
      syncCreatedAt: baseMeta.createdAt,
    );
  }

  /// Builds an event from a remote JSON map.
  static LocalFirstEvent<T> fromRemoteJson<T>({
    required LocalFirstRepository<T> repository,
    required JsonMap json,
  }) {
    try {
      final rawOp = json[kOperation];
      final operation = SyncOperation.values.firstWhere(
        (o) => o.index == rawOp || o.name == rawOp,
        orElse: () => throw FormatException(
          'Invalid sync operation for remote event in ${repository.name}',
        ),
      );
      final rawCreatedAt = json[kSyncCreatedAt];
      if (rawCreatedAt == null) {
        throw FormatException(
          'Missing createdAt for remote event in ${repository.name}',
        );
      }
      final createdAt = rawCreatedAt is DateTime
          ? rawCreatedAt.toUtc()
          : rawCreatedAt is String
          ? DateTime.parse(rawCreatedAt).toUtc()
          : DateTime.fromMillisecondsSinceEpoch(
              rawCreatedAt as int,
              isUtc: true,
            );

      if (operation == SyncOperation.delete) {
        final dataId = json[kDataId] as String?;
        if (dataId == null) {
          throw FormatException(
            'Missing data id for remote delete event in ${repository.name}',
          );
        }
        return LocalFirstDeleteEvent<T>._internal(
          repository: repository,
          eventId: json[kEventId],
          syncStatus: SyncStatus.ok,
          syncOperation: operation,
          syncCreatedAt: createdAt,
          dataId: dataId,
        );
      }

      final stateJson = json[kData];
      if (stateJson == null) {
        throw FormatException(
          'Missing state for remote ${operation.name} event in ${repository.name}',
        );
      }
      return LocalFirstStateEvent<T>._internal(
        repository: repository,
        data: repository.fromJson(JsonMap.from(stateJson)),
        eventId: json[kEventId],
        syncStatus: SyncStatus.ok,
        syncOperation: operation,
        syncCreatedAt: createdAt,
      );
    } catch (e) {
      if (e is FormatException) rethrow;
      throw FormatException(
        'Invalid remote event format for ${repository.name}: $e',
      );
    }
  }

  /// Factory for new insert events.
  static LocalFirstStateEvent<T> createNewInsertEvent<T>({
    required LocalFirstRepository repository,
    required bool needSync,
    required T data,
  }) => LocalFirstStateEvent<T>._internal(
    repository: repository,
    data: data,
    eventId: IdUtil.uuidV7(),
    syncStatus: needSync ? SyncStatus.pending : SyncStatus.ok,
    syncOperation: SyncOperation.insert,
    syncCreatedAt: DateTime.now().toUtc(),
  );

  /// Factory for new update events.
  static LocalFirstEvent<T> createNewUpdateEvent<T>({
    required LocalFirstRepository repository,
    required bool needSync,
    required T data,
  }) => LocalFirstStateEvent<T>._internal(
    repository: repository,
    data: data,
    eventId: IdUtil.uuidV7(),
    syncStatus: needSync ? SyncStatus.pending : SyncStatus.ok,
    syncOperation: SyncOperation.update,
    syncCreatedAt: DateTime.now().toUtc(),
  );

  /// Factory for new delete events.
  static LocalFirstEvent<T> createNewDeleteEvent<T>({
    required LocalFirstRepository repository,
    required bool needSync,
    required String dataId,
  }) {
    assert(T != dynamic, 'Type of data must be specified at delete events');
    return LocalFirstDeleteEvent<T>._internal(
      repository: repository,
      eventId: IdUtil.uuidV7(),
      syncStatus: needSync ? SyncStatus.pending : SyncStatus.ok,
      syncOperation: SyncOperation.delete,
      syncCreatedAt: DateTime.now().toUtc(),
      dataId: dataId,
    );
  }
}

final class LocalFirstStateEvent<T> extends LocalFirstEvent<T> {
  LocalFirstStateEvent._internal({
    required super.repository,
    required this.data,
    required super.eventId,
    required super.syncStatus,
    required super.syncOperation,
    required super.syncCreatedAt,
  }) : super._();

  @override
  final T data;

  @override
  String get dataId => repository.getId(data);

  @override
  JsonMap toJson() => {
    LocalFirstEvent.kEventId: eventId,
    LocalFirstEvent.kOperation: syncOperation.index,
    LocalFirstEvent.kSyncCreatedAt: syncCreatedAt.toUtc().toIso8601String(),
    LocalFirstEvent.kData: repository.toJson(data),
    LocalFirstEvent.kDataId: dataId,
  };

  @override
  JsonMap toLocalStorageJson() => {
    LocalFirstEvent.kEventId: eventId,
    LocalFirstEvent.kDataId: dataId,
    LocalFirstEvent.kSyncStatus: syncStatus.index,
    LocalFirstEvent.kOperation: syncOperation.index,
    LocalFirstEvent.kSyncCreatedAt: syncCreatedAt
        .toUtc()
        .millisecondsSinceEpoch,
  };

  @override
  LocalFirstStateEvent<T> updateEventState({
    SyncStatus? syncStatus,
    SyncOperation? syncOperation,
  }) => LocalFirstStateEvent<T>._internal(
    eventId: eventId,
    repository: repository,
    data: data,
    syncStatus: syncStatus ?? this.syncStatus,
    syncOperation: syncOperation ?? this.syncOperation,
    syncCreatedAt: syncCreatedAt,
  );
}

final class LocalFirstDeleteEvent<T> extends LocalFirstEvent<T> {
  LocalFirstDeleteEvent._internal({
    required super.repository,
    required super.eventId,
    required super.syncStatus,
    required super.syncOperation,
    required super.syncCreatedAt,
    required this.dataId,
  }) : super._();

  @override
  final String dataId;

  @override
  JsonMap toJson() => {
    LocalFirstEvent.kEventId: eventId,
    LocalFirstEvent.kOperation: syncOperation.index,
    LocalFirstEvent.kSyncCreatedAt: syncCreatedAt.toUtc().toIso8601String(),
    LocalFirstEvent.kDataId: dataId,
  };

  @override
  JsonMap toLocalStorageJson() => {
    LocalFirstEvent.kEventId: eventId,
    LocalFirstEvent.kDataId: dataId,
    LocalFirstEvent.kSyncStatus: syncStatus.index,
    LocalFirstEvent.kOperation: syncOperation.index,
    LocalFirstEvent.kSyncCreatedAt: syncCreatedAt
        .toUtc()
        .millisecondsSinceEpoch,
  };

  @override
  LocalFirstDeleteEvent<T> updateEventState({
    SyncStatus? syncStatus,
    SyncOperation? syncOperation,
  }) => LocalFirstDeleteEvent<T>._internal(
    repository: repository,
    eventId: eventId,
    syncStatus: syncStatus ?? this.syncStatus,
    syncOperation: syncOperation ?? this.syncOperation,
    syncCreatedAt: syncCreatedAt,
    dataId: dataId,
  );

  @override
  T? get data => null;
}

/// Extension methods for lists of models with sync metadata.
extension LocalFirstEventsToJson<T> on LocalFirstEvents<T> {
  /// Converts a list of objects to the sync JSON format.
  ///
  /// Groups objects by operation type (insert, update, delete) as expected
  /// by the push endpoint.
  List<JsonMap> toJson() => [for (var event in this) event.toJson()];
}

DateTime? _parseSyncCreatedAt(dynamic value) {
  if (value is DateTime) return value.toUtc();
  if (value is int) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    } catch (_) {
      return null;
    }
  }
  if (value is String) {
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}
