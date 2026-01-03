part of '../../local_first.dart';

/// Base contract for events with synchronization metadata.
abstract class LocalFirstEvent<T extends Object> {
  LocalFirstEvent({
    required this.repositoryName,
    required this.syncStatus,
    String? eventId,
    DateTime? syncCreatedAt,
    DateTime? syncCreatedAtServer,
    this.syncServerSequence,
  }) : eventId = eventId ?? UuidUtil.generateUuidV7(),
       syncCreatedAt = (syncCreatedAt ?? DateTime.now()).toUtc(),
       syncCreatedAtServer = syncCreatedAtServer?.toUtc() {
    assert(T != Object, 'LocalFirstEvent<T> requires a concrete type');
  }

  /// Unique identifier for this event.
  final String eventId;

  /// Sync status (pending/failed/ok).
  final SyncStatus syncStatus;

  /// The operation represented by this event.
  SyncOperation get syncOperation;

  /// Client-side creation timestamp (UTC).
  final DateTime syncCreatedAt;

  /// Server-side creation timestamp (UTC), when available.
  final DateTime? syncCreatedAtServer;

  /// Server sequence that produced this event.
  final int? syncServerSequence;

  /// Repository this event belongs to.
  final String repositoryName;

  /// Returns true if this object has pending changes that need sync.
  bool get needSync => syncStatus != SyncStatus.ok;

  /// Returns true if this object is marked as deleted.
  bool get isDeleted;

  JsonMap toJson();

  static LocalFirstEvent<T> fromJson<T extends Object>(
    JsonMap json, {
    required T Function(JsonMap) fromJson,
  }) {
    final opValue = json['sync_operation'];
    final op = opValue is int
        ? SyncOperation.values[opValue]
        : SyncOperation.values.firstWhere((v) => v.name == (opValue as String));
    switch (op) {
      case SyncOperation.insert:
        return InsertEvent.fromJson<T>(json, fromJson: fromJson);
      case SyncOperation.update:
        return UpdateEvent.fromJson<T>(json, fromJson: fromJson);
      case SyncOperation.delete:
        return DeleteEvent.fromJson<T>(json);
    }
  }
}

abstract class LocalFirstUpsertEvent<T extends Object>
    extends LocalFirstEvent<T> {
  LocalFirstUpsertEvent({
    required super.repositoryName,
    required super.syncStatus,
    super.eventId,
    super.syncCreatedAt,
    super.syncCreatedAtServer,
    super.syncServerSequence,
  });

  /// Domain data associated with the event.
  T get data;

  bool isA<U>() => data is U;
  U dataAs<U extends Object>() => data as U;
}

/// Insert event carrying full data payload.
class InsertEvent<T extends Object> extends LocalFirstUpsertEvent<T> {
  InsertEvent({
    required this.data,
    required super.repositoryName,
    super.syncStatus = SyncStatus.pending,
    super.eventId,
    super.syncCreatedAt,
    super.syncCreatedAtServer,
    super.syncServerSequence,
  });

  @override
  final T data;

  @override
  bool get isDeleted => false;

  @override
  SyncOperation get syncOperation => SyncOperation.insert;

  InsertEvent copyWith({
    T? data,
    String? eventId,
    SyncStatus? syncStatus,
    DateTime? syncCreatedAt,
    DateTime? syncCreatedAtServer,
    int? syncServerSequence,
    String? repositoryName,
  }) {
    return InsertEvent(
      data: data ?? this.data,
      repositoryName: repositoryName ?? this.repositoryName,
      syncStatus: syncStatus ?? this.syncStatus,
      eventId: eventId ?? this.eventId,
      syncCreatedAt: syncCreatedAt ?? this.syncCreatedAt,
      syncCreatedAtServer: syncCreatedAtServer ?? this.syncCreatedAtServer,
      syncServerSequence: syncServerSequence ?? this.syncServerSequence,
    );
  }

  static InsertEvent<T> fromJson<T extends Object>(
    JsonMap json, {
    required T Function(JsonMap) fromJson,
  }) {
    return InsertEvent<T>(
      data: fromJson(json['data'] as JsonMap),
      repositoryName: json['repository_name'] as String,
      syncStatus: SyncStatus.values[json['sync_status'] as int],
      eventId: json['event_id'] as String?,
      syncCreatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['sync_created_at'] as int,
        isUtc: true,
      ),
      syncCreatedAtServer: (json['sync_created_at_server'] as int?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              json['sync_created_at_server'] as int,
              isUtc: true,
            ),
      syncServerSequence: json['sync_server_sequence'] as int?,
    );
  }

  @override
  JsonMap toJson() => {
    'data': data,
    'repository_name': repositoryName,
    'sync_status': syncStatus.index,
    'sync_operation': syncOperation.index,
    'event_id': eventId,
    'sync_created_at': syncCreatedAt.millisecondsSinceEpoch,
    'sync_created_at_server': syncCreatedAtServer?.millisecondsSinceEpoch,
    'sync_server_sequence': syncServerSequence,
  };
}

/// Update event carrying full data payload.
class UpdateEvent<T extends Object> extends LocalFirstUpsertEvent<T> {
  UpdateEvent({
    required this.data,
    required super.repositoryName,
    super.syncStatus = SyncStatus.pending,
    super.eventId,
    super.syncCreatedAt,
    super.syncCreatedAtServer,
    super.syncServerSequence,
  });

  @override
  final T data;

  @override
  bool get isDeleted => false;

  @override
  SyncOperation get syncOperation => SyncOperation.update;

  UpdateEvent copyWith({
    T? data,
    String? eventId,
    SyncStatus? syncStatus,
    DateTime? syncCreatedAt,
    DateTime? syncCreatedAtServer,
    int? syncServerSequence,
    String? repositoryName,
  }) {
    return UpdateEvent(
      data: data ?? this.data,
      repositoryName: repositoryName ?? this.repositoryName,
      syncStatus: syncStatus ?? this.syncStatus,
      eventId: eventId ?? this.eventId,
      syncCreatedAt: syncCreatedAt ?? this.syncCreatedAt,
      syncCreatedAtServer: syncCreatedAtServer ?? this.syncCreatedAtServer,
      syncServerSequence: syncServerSequence ?? this.syncServerSequence,
    );
  }

  static UpdateEvent<T> fromJson<T extends Object>(
    JsonMap json, {
    required T Function(JsonMap) fromJson,
  }) {
    return UpdateEvent<T>(
      data: fromJson(json['data'] as JsonMap),
      repositoryName: json['repository_name'] as String,
      syncStatus: SyncStatus.values[json['sync_status'] as int],
      eventId: json['event_id'] as String?,
      syncCreatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['sync_created_at'] as int,
        isUtc: true,
      ),
      syncCreatedAtServer: (json['sync_created_at_server'] as int?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              json['sync_created_at_server'] as int,
              isUtc: true,
            ),
      syncServerSequence: json['sync_server_sequence'] as int?,
    );
  }

  @override
  JsonMap toJson() => {
    'data': data,
    'repository_name': repositoryName,
    'sync_status': syncStatus.index,
    'sync_operation': syncOperation.index,
    'event_id': eventId,
    'sync_created_at': syncCreatedAt.millisecondsSinceEpoch,
    'sync_created_at_server': syncCreatedAtServer?.millisecondsSinceEpoch,
    'sync_server_sequence': syncServerSequence,
  };
}

/// Delete event; may carry only the id and optional previous data.
class DeleteEvent<T extends Object> extends LocalFirstEvent<T> {
  DeleteEvent({
    required this.id,
    required super.repositoryName,
    super.syncStatus = SyncStatus.pending,
    super.eventId,
    super.syncCreatedAt,
    super.syncCreatedAtServer,
    super.syncServerSequence,
  });

  /// Identifier of the record being deleted.
  final String id;

  @override
  bool get isDeleted => true;

  @override
  SyncOperation get syncOperation => SyncOperation.delete;

  DeleteEvent copyWith({
    String? id,
    String? eventId,
    SyncStatus? syncStatus,
    DateTime? syncCreatedAt,
    DateTime? syncCreatedAtServer,
    int? syncServerSequence,
    String? repositoryName,
  }) {
    return DeleteEvent(
      id: id ?? this.id,
      repositoryName: repositoryName ?? this.repositoryName,
      syncStatus: syncStatus ?? this.syncStatus,
      eventId: eventId ?? this.eventId,
      syncCreatedAt: syncCreatedAt ?? this.syncCreatedAt,
      syncCreatedAtServer: syncCreatedAtServer ?? this.syncCreatedAtServer,
      syncServerSequence: syncServerSequence ?? this.syncServerSequence,
    );
  }

  static DeleteEvent<T> fromJson<T extends Object>(JsonMap json) {
    return DeleteEvent<T>(
      id: json['id'] as String,
      repositoryName: json['repository_name'] as String,
      syncStatus: SyncStatus.values[json['sync_status'] as int],
      eventId: json['event_id'] as String?,
      syncCreatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['sync_created_at'] as int,
        isUtc: true,
      ),
      syncCreatedAtServer: (json['sync_created_at_server'] as int?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              json['sync_created_at_server'] as int,
              isUtc: true,
            ),
      syncServerSequence: json['sync_server_sequence'] as int?,
    );
  }

  @override
  JsonMap toJson() => {
    'id': id,
    'repository_name': repositoryName,
    'sync_status': syncStatus.index,
    'sync_operation': syncOperation.index,
    'event_id': eventId,
    'sync_created_at': syncCreatedAt.millisecondsSinceEpoch,
    'sync_created_at_server': syncCreatedAtServer?.millisecondsSinceEpoch,
    'sync_server_sequence': syncServerSequence,
  };
}

/// Extension methods for lists of events with sync metadata.
extension LocalFirstEventsX on List<LocalFirstEvent> {
  /// Converts a list of events to the sync JSON format.
  ///
  /// Uses the provided [client] to resolve serializer and id field for each
  /// repository. Groups by repository name, then by operation:
  /// - `insert`/`update`: list of full objects + metadata
  /// - `delete`: list of ids
  ///
  /// Throws [StateError] if an event is missing an id or `syncCreatedAt`.
  JsonMap toJson({
    required LocalFirstRepository repository,
    required LocalFirstClient client,
  }) {
    final JsonMap<JsonMap<List<dynamic>>> changes = {};

    for (var event in this) {
      final repo = client.getRepositoryByName(event.repositoryName);
      if (repo == null) {
        throw StateError(
          'Repository "${event.repositoryName}" not found for event ${event.eventId}',
        );
      }

      final JsonMap<List> repoChanges = changes.putIfAbsent(
        event.repositoryName,
        () => {},
      );

      switch (event.syncOperation) {
        case SyncOperation.insert:
          final insertEvent = event as InsertEvent;
          final serializedData = JsonMap.from(repo.toJson(insertEvent.data));
          final idValue = serializedData[repo.idFieldName]?.toString();
          if (idValue == null || idValue.isEmpty) {
            throw StateError(
              'Missing or empty "${repo.idFieldName}" for event ${event.eventId}',
            );
          }
          final JsonMap itemJson = JsonMap.from(serializedData);
          itemJson['event_id'] = event.eventId;
          final createdAtClient = event.syncCreatedAt;
          itemJson['created_at_client'] = createdAtClient.toIso8601String();
          itemJson['created_at_server'] = event.syncCreatedAtServer?.toJson();
          repoChanges.putIfAbsent('insert', () => <JsonMap>[]).add(itemJson);
          break;
        case SyncOperation.update:
          final updateEvent = event as UpdateEvent;
          final serializedData = JsonMap.from(repo.toJson(updateEvent.data));
          final idValue = serializedData[repo.idFieldName]?.toString();
          if (idValue == null || idValue.isEmpty) {
            throw StateError(
              'Missing or empty "${repo.idFieldName}" for event ${event.eventId}',
            );
          }
          final JsonMap itemJson = JsonMap.from(serializedData);
          itemJson['event_id'] = event.eventId;
          final createdAtClient = event.syncCreatedAt;
          itemJson['created_at_client'] = createdAtClient.toIso8601String();
          itemJson['created_at_server'] = event.syncCreatedAtServer?.toJson();
          repoChanges.putIfAbsent('update', () => <JsonMap>[]).add(itemJson);
          break;
        case SyncOperation.delete:
          final deleteEvent = event as DeleteEvent;
          final idValue = deleteEvent.id;
          if (idValue.isEmpty) {
            throw StateError('Missing id for delete event ${event.eventId}');
          }
          repoChanges.putIfAbsent('delete', () => <String>[]).add(idValue);
          break;
      }
    }

    return changes;
  }
}

/// Represents a response from the server during a pull operation.
///
/// Contains all changes from the server grouped by repository.
typedef LocalFirstRemoteResponse =
    Map<LocalFirstRepository, List<LocalFirstEvent>>;
