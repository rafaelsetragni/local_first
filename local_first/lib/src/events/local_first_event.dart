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
sealed class LocalFirstEvent<T> {
  // Shared payload keys for remote and local.
  static const String kEventId = '_event_id';
  static const String kRepository = 'repository';
  static const String kOperation = '_sync_operation';
  static const String kSyncCreatedAt = '_sync_created_at';
  static const String kState = 'state';
  static const String kDataId = '_data_id';
  static const String kSyncStatus = '_sync_status';
  static const String kLastEventId = '_last_event_id';

  LocalFirstEvent._({
    required this.repository,
    required this.eventId,
    required this.syncStatus,
    required this.syncOperation,
    required this.syncCreatedAt,
    required this.repositoryName,
  });

  final LocalFirstRepository repository;
  final String eventId;
  final SyncStatus syncStatus;
  final SyncOperation syncOperation;
  final DateTime syncCreatedAt;
  final String repositoryName;

  bool get needSync => syncStatus != SyncStatus.ok;
  bool get isDeleted => syncOperation == SyncOperation.delete;

  /// Must be available for all event kinds.
  String get dataId;

  /// Serialize event to remote JSON.
  JsonMap toJson();

  /// Serialize event metadata for local storage.
  JsonMap toLocalStorageJson();

  /// Clone preserving subtype.
  LocalFirstEvent<T> copyWith({
    SyncStatus? syncStatus,
    SyncOperation? syncOperation,
    String? repositoryName,
    String? eventId,
    DateTime? syncCreatedAt,
    T? state,
    String? dataId,
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
    final createdAtMs = itemJson.remove(kSyncCreatedAt) as int?;
    final eventId = itemJson.remove(kEventId) as String?;

    if ((eventId ?? lastEventId) == null ||
        statusIndex == null ||
        opIndex == null ||
        createdAtMs == null) {
      throw FormatException(
        'Invalid local event storage for ${repository.name}',
      );
    }

    final operation = SyncOperation.values[opIndex];
    final baseMeta = (
      id: eventId ?? lastEventId!,
      status: SyncStatus.values[statusIndex],
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        createdAtMs,
        isUtc: true,
      ),
    );

    if (operation == SyncOperation.delete) {
      if (dataId == null) {
        throw FormatException(
          'Missing data id for delete event in ${repository.name}',
        );
      }
      return LocalFirstDeleteEvent<T>._internal(
        repository: repository,
        repositoryName: repository.name,
        eventId: baseMeta.id,
        syncStatus: baseMeta.status,
        syncOperation: operation,
        syncCreatedAt: baseMeta.createdAt,
        dataId: dataId,
      );
    }

    itemJson.remove(kDataId);
    itemJson.putIfAbsent(repository.idFieldName, () => dataId);
    final model = repository.fromJson(itemJson);
    return LocalFirstStateEvent<T>._internal(
      repository: repository,
      repositoryName: repository.name,
      state: model,
      eventId: baseMeta.id,
      syncStatus: baseMeta.status,
      syncOperation: operation,
      syncCreatedAt: baseMeta.createdAt,
    );
  }

  /// Builds an event from a remote JSON map.
  factory LocalFirstEvent.fromRemoteJson({
    required LocalFirstRepository repository,
    required JsonMap json,
  }) {
    final operation = SyncOperation.values.firstWhere(
      (o) => o.index == json[kOperation] || o.name == json[kOperation],
    );
    final rawCreatedAt = json[kSyncCreatedAt];
    final createdAt = rawCreatedAt is String
        ? (DateTime.tryParse(rawCreatedAt) ?? DateTime.now()).toUtc()
        : DateTime.fromMillisecondsSinceEpoch(
          (rawCreatedAt as int?) ?? 0,
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
        repositoryName: repository.name,
        eventId: json[kEventId],
        syncStatus: SyncStatus.ok,
        syncOperation: operation,
        syncCreatedAt: createdAt,
        dataId: dataId,
      );
    }

    final stateJson = json[kState];
    if (stateJson == null) {
      throw FormatException(
        'Missing state for remote ${operation.name} event in ${repository.name}',
      );
    }
    return LocalFirstStateEvent<T>._internal(
      repository: repository,
      repositoryName: repository.name,
      state: repository.fromJson(JsonMap.from(stateJson)),
      eventId: json[kEventId],
      syncStatus: SyncStatus.ok,
      syncOperation: operation,
      syncCreatedAt: createdAt,
    );
  }

  /// Factory for new local events.
  factory LocalFirstEvent.createNewEvent({
    required LocalFirstRepository repository,
    required SyncStatus syncStatus,
    required SyncOperation syncOperation,
    T? state,
    String? dataId,
  }) {
    switch (syncOperation) {
      case SyncOperation.insert:
      case SyncOperation.update:
        if (state == null) {
          throw ArgumentError('State is required for $syncOperation events');
        }
        return LocalFirstStateEvent<T>._internal(
          repository: repository,
          repositoryName: repository.name,
          state: state,
          eventId: IdUtil.uuidV7(),
          syncStatus: syncStatus,
          syncOperation: syncOperation,
          syncCreatedAt: DateTime.now().toUtc(),
        );
      case SyncOperation.delete:
        final resolvedId =
            dataId ?? (state != null ? repository.getId(state) : null);
        if (resolvedId == null) {
          throw ArgumentError('dataId or state is required for delete events');
        }
        return LocalFirstDeleteEvent<T>._internal(
          repository: repository,
          repositoryName: repository.name,
          eventId: IdUtil.uuidV7(),
          syncStatus: syncStatus,
          syncOperation: SyncOperation.delete,
          syncCreatedAt: DateTime.now().toUtc(),
          dataId: resolvedId,
        );
    }
  }
}

final class LocalFirstStateEvent<T> extends LocalFirstEvent<T> {
  LocalFirstStateEvent._internal({
    required super.repository,
    required this.state,
    required super.eventId,
    required super.syncStatus,
    required super.syncOperation,
    required super.syncCreatedAt,
    required super.repositoryName,
  }) : super._();

  final T state;

  @override
  String get dataId => repository.getId(state);

  @override
  JsonMap toJson() => {
    LocalFirstEvent.kEventId: eventId,
    LocalFirstEvent.kRepository: repositoryName,
    LocalFirstEvent.kOperation: syncOperation.index,
    LocalFirstEvent.kSyncCreatedAt: syncCreatedAt.toUtc().millisecondsSinceEpoch,
    LocalFirstEvent.kState: repository.toJson(state),
    LocalFirstEvent.kSyncStatus: syncStatus.index,
    LocalFirstEvent.kDataId: dataId,
  };

  @override
  JsonMap toLocalStorageJson() => {
    LocalFirstEvent.kEventId: eventId,
    LocalFirstEvent.kDataId: dataId,
    LocalFirstEvent.kSyncStatus: syncStatus.index,
    LocalFirstEvent.kOperation: syncOperation.index,
    LocalFirstEvent.kSyncCreatedAt: syncCreatedAt.toUtc().millisecondsSinceEpoch,
  };

  @override
  LocalFirstStateEvent<T> copyWith({
    SyncStatus? syncStatus,
    SyncOperation? syncOperation,
    String? repositoryName,
    String? eventId,
    DateTime? syncCreatedAt,
    T? state,
    String? dataId,
  }) => LocalFirstStateEvent<T>._internal(
    repository: repository,
    repositoryName: repositoryName ?? this.repositoryName,
    state: state ?? this.state,
    eventId: eventId ?? this.eventId,
    syncStatus: syncStatus ?? this.syncStatus,
    syncOperation: syncOperation ?? this.syncOperation,
    syncCreatedAt: (syncCreatedAt ?? this.syncCreatedAt).toUtc(),
  );
}

final class LocalFirstDeleteEvent<T> extends LocalFirstEvent<T> {
  LocalFirstDeleteEvent._internal({
    required super.repository,
    required super.eventId,
    required super.syncStatus,
    required super.syncOperation,
    required super.syncCreatedAt,
    required super.repositoryName,
    required this.dataId,
  }) : super._();

  @override
  final String dataId;

  @override
  JsonMap toJson() => {
    LocalFirstEvent.kEventId: eventId,
    LocalFirstEvent.kRepository: repositoryName,
    LocalFirstEvent.kOperation: syncOperation.index,
    LocalFirstEvent.kSyncCreatedAt: syncCreatedAt.toUtc().millisecondsSinceEpoch,
    LocalFirstEvent.kSyncStatus: syncStatus.index,
    LocalFirstEvent.kDataId: dataId,
  };

  @override
  JsonMap toLocalStorageJson() => {
    LocalFirstEvent.kEventId: eventId,
    LocalFirstEvent.kDataId: dataId,
    LocalFirstEvent.kSyncStatus: syncStatus.index,
    LocalFirstEvent.kOperation: syncOperation.index,
    LocalFirstEvent.kSyncCreatedAt: syncCreatedAt.toUtc().millisecondsSinceEpoch,
  };

  @override
  LocalFirstDeleteEvent<T> copyWith({
    SyncStatus? syncStatus,
    SyncOperation? syncOperation,
    String? repositoryName,
    String? eventId,
    DateTime? syncCreatedAt,
    T? state,
    String? dataId,
  }) => LocalFirstDeleteEvent<T>._internal(
    repository: repository,
    repositoryName: repositoryName ?? this.repositoryName,
    eventId: eventId ?? this.eventId,
    syncStatus: syncStatus ?? this.syncStatus,
    syncOperation: syncOperation ?? this.syncOperation,
    syncCreatedAt: (syncCreatedAt ?? this.syncCreatedAt).toUtc(),
    dataId: dataId ?? this.dataId,
  );
}

/// Extension methods for lists of models with sync metadata.
extension LocalFirstEventsToJson<T> on LocalFirstEvents<T> {
  /// Converts a list of objects to the sync JSON format.
  ///
  /// Groups objects by operation type (insert, update, delete) as expected
  /// by the push endpoint.
  List<JsonMap> toJson() => [for (var event in this) event.toJson()];
}
