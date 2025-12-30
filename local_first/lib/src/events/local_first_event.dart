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

/// Type alias for a list of events with sync metadata.
typedef LocalFirstEvents = List<LocalFirstEvent>;

/// Wrapper that adds synchronization metadata to a domain model.
///
/// Use this wrapper so your models can remain immutable/const without
/// requiring a mixin.
class LocalFirstEvent {
  LocalFirstEvent({
    required this.data,
    String? eventId,
    this.syncStatus = SyncStatus.ok,
    this.syncOperation = SyncOperation.insert,
    DateTime? syncCreatedAt,
    DateTime? syncCreatedAtServer,
    this.serverSequence,
    this.repositoryName = '',
  }) : eventId = eventId ?? UuidUtil.generateUuidV7(),
       syncCreatedAt = syncCreatedAt?.toUtc(),
       syncCreatedAtServer = syncCreatedAtServer?.toUtc();

  final Object data;
  final String eventId;

  bool isA<T>() => data is T;
  T dataAs<T extends Object>() => data as T;

  final SyncStatus syncStatus;
  final SyncOperation syncOperation;
  final DateTime? syncCreatedAt;
  final DateTime? syncCreatedAtServer;
  final int? serverSequence;
  final String repositoryName;

  int? get syncServerSequence => serverSequence;

  /// Returns true if this object has pending changes that need sync.
  bool get needSync => syncStatus != SyncStatus.ok;

  /// Returns true if this object is marked as deleted.
  bool get isDeleted => syncOperation == SyncOperation.delete;

  LocalFirstEvent copyWith({
    Object? data,
    String? eventId,
    SyncStatus? syncStatus,
    SyncOperation? syncOperation,
    DateTime? syncCreatedAt,
    DateTime? syncCreatedAtServer,
    int? serverSequence,
    String? repositoryName,
  }) {
    return LocalFirstEvent(
      data: data ?? this.data,
      eventId: eventId ?? this.eventId,
      syncStatus: syncStatus ?? this.syncStatus,
      syncOperation: syncOperation ?? this.syncOperation,
      syncCreatedAt: syncCreatedAt ?? this.syncCreatedAt,
      syncCreatedAtServer: syncCreatedAtServer ?? this.syncCreatedAtServer,
      serverSequence: serverSequence ?? this.serverSequence,
      repositoryName: repositoryName ?? this.repositoryName,
    );
  }
}

/// Extension methods for lists of events with sync metadata.
extension LocalFirstEventsX on List<LocalFirstEvent> {
  /// Converts a list of events to the sync JSON format.
  ///
  /// Groups objects by operation type (insert, update, delete) as expected
  /// by the push endpoint. Use [idFieldName] when your model id key differs
  /// from 'id'.
  Map<String, dynamic> toJson<T extends Object>({
    required Map<String, dynamic> Function(T item) serializer,
    String idFieldName = 'id',
  }) {
    final inserts = <Map<String, dynamic>>[];
    final updates = <Map<String, dynamic>>[];
    final deletes = <String>[];

    for (var event in this) {
      final itemJson = Map<String, dynamic>.from(serializer(event.dataAs<T>()));
      itemJson['event_id'] = event.eventId;
      if (event.syncCreatedAt != null) {
        itemJson['created_at_client'] = event.syncCreatedAt!.toIso8601String();
      }
      if (event.syncCreatedAtServer != null) {
        itemJson['created_at_server'] = event.syncCreatedAtServer!
            .toIso8601String();
      }

      switch (event.syncOperation) {
        case SyncOperation.insert:
          inserts.add(itemJson);
          break;
        case SyncOperation.update:
          updates.add(itemJson);
          break;
        case SyncOperation.delete:
          deletes.add(itemJson[idFieldName]?.toString() ?? '');
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
