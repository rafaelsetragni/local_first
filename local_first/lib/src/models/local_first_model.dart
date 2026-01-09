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

/// Type alias for a list of models with sync metadata.
typedef LocalFirstEvents<T> = List<LocalFirstEvent<T>>;

@Deprecated('Use LocalFirstEvent instead; this mixin no longer carries state.')
mixin LocalFirstModel {}

/// Immutable wrapper carrying sync metadata alongside the state object.
class LocalFirstEvent<T> {
  LocalFirstEvent({
    required this.state,
    String? eventId,
    this.syncStatus = SyncStatus.ok,
    this.syncOperation = SyncOperation.insert,
    DateTime? syncCreatedAt,
    this.repositoryName = '',
  }) : syncCreatedAt = (syncCreatedAt ?? DateTime.now().toUtc()),
       eventId = eventId ?? LocalFirstIdGenerator.uuidV7();

  /// Domain object being synced.
  final T state;

  /// Unique identifier for this sync event.
  final String eventId;

  /// Current synchronization state for this state object.
  final SyncStatus syncStatus;

  /// Last operation performed locally.
  final SyncOperation syncOperation;

  /// Timestamp when the item was first created locally.
  final DateTime syncCreatedAt;

  /// Repository that owns this event.
  final String repositoryName;

  /// Returns true if this object has pending changes that need sync.
  bool get needSync => syncStatus != SyncStatus.ok;

  /// Returns true if this object is marked as deleted.
  bool get isDeleted => syncOperation == SyncOperation.delete;

  /// Creates a new instance with selective overrides.
  LocalFirstEvent<T> copyWith({
    T? state,
    String? eventId,
    SyncStatus? syncStatus,
    SyncOperation? syncOperation,
    DateTime? syncCreatedAt,
    String? repositoryName,
  }) {
    return LocalFirstEvent<T>(
      state: state ?? this.state,
      eventId: eventId ?? this.eventId,
      syncStatus: syncStatus ?? this.syncStatus,
      syncOperation: syncOperation ?? this.syncOperation,
      syncCreatedAt: (syncCreatedAt ?? this.syncCreatedAt).toUtc(),
      repositoryName: repositoryName ?? this.repositoryName,
    );
  }
}

/// Extension methods for lists of models with sync metadata.
extension LocalFirstModelsX<T> on List<LocalFirstEvent<T>> {
  /// Converts a list of objects to the sync JSON format.
  ///
  /// Groups objects by operation type (insert, update, delete) as expected
  /// by the push endpoint.
  Map<String, dynamic> toJson(Map<String, dynamic> Function(T state) toJson) {
    final inserts = <Map<String, dynamic>>[];
    final updates = <Map<String, dynamic>>[];
    final deletes = <Map<String, dynamic>>[];

    for (var obj in this) {
      final itemJson = {...toJson(obj.state), 'event_id': obj.eventId};

      switch (obj.syncOperation) {
        case SyncOperation.insert:
          inserts.add(itemJson);
          break;
        case SyncOperation.update:
          updates.add(itemJson);
          break;
        case SyncOperation.delete:
          deletes.add({
            'id': itemJson['id']?.toString() ?? '',
            'event_id': obj.eventId,
          });
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
