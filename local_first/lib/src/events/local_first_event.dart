part of '../../local_first.dart';

/// Represents the synchronization status of an object.
enum SyncStatus {
  /// The object has pending changes that need to be synced.
  pending,

  /// The last sync attempt failed (will be retried).
  failed,

  /// The object is synchronized with the server.
  ok,
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

/// Wrapper for an event applied to a repository record.
class LocalFirstEvent<T> {
  LocalFirstEvent._internal({
    required this.repositoryName,
    required this.recordId,
    required this.syncOperation,
    required this.data,
    required this.syncStatus,
    required DateTime syncCreatedAt,
    required String? eventId,
  }) : eventId = eventId ?? UuidUtil.generateUuidV7(),
       syncCreatedAt = syncCreatedAt.toUtc();

  final String repositoryName;
  final String recordId;
  final String eventId;
  final SyncOperation syncOperation;
  final SyncStatus syncStatus;
  final DateTime syncCreatedAt;
  final T data;

  bool get isDelete => syncOperation == SyncOperation.delete;

  /// Returns a copy of this event with selectively overridden fields.
  LocalFirstEvent<T> copyWith({
    String? repositoryName,
    String? recordId,
    String? eventId,
    SyncOperation? syncOperation,
    SyncStatus? syncStatus,
    DateTime? syncCreatedAt,
    T? data,
  }) {
    return LocalFirstEvent<T>._internal(
      repositoryName: repositoryName ?? this.repositoryName,
      recordId: recordId ?? this.recordId,
      syncOperation: syncOperation ?? this.syncOperation,
      syncStatus: syncStatus ?? this.syncStatus,
      syncCreatedAt: (syncCreatedAt ?? this.syncCreatedAt).toUtc(),
      eventId: eventId ?? this.eventId,
      data: data ?? this.data,
    );
  }

  /// Factory for a locally generated insert.
  static LocalFirstEvent<T> createLocalInsert<T>({
    required String repositoryName,
    required String recordId,
    required T data,
    required DateTime? createdAt,
    required String? eventId,
  }) {
    final now = (createdAt ?? DateTime.now()).toUtc();
    return LocalFirstEvent<T>._internal(
      repositoryName: repositoryName,
      recordId: recordId,
      syncOperation: SyncOperation.insert,
      syncStatus: SyncStatus.pending,
      syncCreatedAt: now,
      eventId: eventId,
      data: data,
    );
  }

  /// Factory for a locally generated update.
  static LocalFirstEvent<T> createLocalUpdate<T>({
    required String repositoryName,
    required String recordId,
    required T data,
    required DateTime? createdAt,
    required String? eventId,
  }) {
    final now = (createdAt ?? DateTime.now()).toUtc();
    return LocalFirstEvent<T>._internal(
      repositoryName: repositoryName,
      recordId: recordId,
      syncOperation: SyncOperation.update,
      syncStatus: SyncStatus.pending,
      syncCreatedAt: now,
      eventId: eventId,
      data: data,
    );
  }

  /// Factory for a locally generated delete.
  static LocalFirstEvent<T> createLocalDelete<T>({
    required String repositoryName,
    required String recordId,
    required T data,
    required DateTime? createdAt,
    required String? eventId,
  }) {
    final now = (createdAt ?? DateTime.now()).toUtc();
    return LocalFirstEvent<T>._internal(
      repositoryName: repositoryName,
      recordId: recordId,
      syncOperation: SyncOperation.delete,
      syncStatus: SyncStatus.pending,
      syncCreatedAt: now,
      eventId: eventId,
      data: data,
    );
  }

  /// Factory for a remote event (already synced/authoritative).
  static LocalFirstEvent<T> createRemote<T>({
    required String repositoryName,
    required String recordId,
    required SyncOperation operation,
    required T data,
    required DateTime? createdAt,
    required String? eventId,
  }) {
    final ts = (createdAt ?? DateTime.now()).toUtc();
    return LocalFirstEvent<T>._internal(
      repositoryName: repositoryName,
      recordId: recordId,
      syncOperation: operation,
      syncStatus: SyncStatus.ok,
      syncCreatedAt: ts,
      eventId: eventId,
      data: data,
    );
  }

  Map<String, dynamic> toJson({Map<String, dynamic> Function(T data)? toJson}) {
    final payload = toJson != null ? toJson(data) : data;
    return {
      'event_id': eventId,
      'repository': repositoryName,
      'record_id': recordId,
      'payload': payload,
      'status': syncStatus.index,
      'operation': syncOperation.index,
      'created_at': syncCreatedAt.millisecondsSinceEpoch,
    };
  }

  static LocalFirstEvent<T> fromJson<T>(
    Map<String, dynamic> json, {
    required T Function(Map<String, dynamic>) fromJson,
  }) {
    return LocalFirstEvent<T>._internal(
      repositoryName: json['repository'] as String,
      recordId: json['record_id'] as String,
      syncOperation: SyncOperation.values[json['operation'] as int],
      syncStatus: SyncStatus.values[json['status'] as int],
      syncCreatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['created_at'] as int,
        isUtc: true,
      ),
      eventId: json['event_id'] as String?,
      data: fromJson(json['payload'] as Map<String, dynamic>),
    );
  }
}

/// Extension methods for lists of models with sync metadata.
extension LocalFirstEventsX<T extends LocalFirstEvent> on List<T> {
  /// Converts a list of objects to the sync JSON format.
  ///
  /// Groups objects by operation type (insert, update, delete) as expected
  /// by the push endpoint.
  Map<String, dynamic> toJson() {
    final inserts = <Map<String, dynamic>>[];
    final updates = <Map<String, dynamic>>[];
    final deletes = <Map<String, dynamic>>[];

    for (var obj in this) {
      final itemJson = obj.toJson();

      switch (obj.syncOperation) {
        case SyncOperation.insert:
          inserts.add(itemJson);
          break;
        case SyncOperation.update:
          updates.add(itemJson);
          break;
        case SyncOperation.delete:
          deletes.add(itemJson);
          break;
      }
    }

    return {'insert': inserts, 'update': updates, 'delete': deletes};
  }
}

/// Represents a response from the server during a pull operation.
///
/// Contains all changes from the server grouped by repository, along with
/// the server's timestamp for tracking sync progress.
class LocalFirstResponse {
  /// Map of repositories to their changed objects.
  final Map<LocalFirstRepository, List<LocalFirstEvent>> changes;

  /// Server timestamp when this response was generated.
  final DateTime timestamp;

  LocalFirstResponse({required this.changes, required this.timestamp});
}
