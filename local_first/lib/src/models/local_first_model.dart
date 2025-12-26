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
typedef LocalFirstEvents<T> = List<LocalFirstEvent<T>>;

/// Wrapper that adds synchronization metadata to a domain model.
///
/// Use this wrapper so your models can remain immutable/const without
/// requiring a mixin.
class LocalFirstEvent<T> {
  LocalFirstEvent({
    required this.data,
    SyncStatus syncStatus = SyncStatus.ok,
    SyncOperation syncOperation = SyncOperation.insert,
    DateTime? syncCreatedAt,
    String repositoryName = '',
  }) : _syncStatus = syncStatus,
       _syncOperation = syncOperation,
       _syncCreatedAt = syncCreatedAt?.toUtc(),
       _repositoryName = repositoryName;

  final T data;

  SyncStatus _syncStatus;
  SyncOperation _syncOperation;
  DateTime? _syncCreatedAt;
  String _repositoryName;

  SyncStatus get syncStatus => _syncStatus;
  SyncOperation get syncOperation => _syncOperation;
  DateTime? get syncCreatedAt => _syncCreatedAt;
  String get repositoryName => _repositoryName;

  /// Returns true if this object has pending changes that need sync.
  bool get needSync => syncStatus != SyncStatus.ok;

  /// Returns true if this object is marked as deleted.
  bool get isDeleted => syncOperation == SyncOperation.delete;

  // Internal setters used by the package.
  void _setSyncStatus(SyncStatus status) => _syncStatus = status;

  void _setSyncOperation(SyncOperation operation) => _syncOperation = operation;

  void _setSyncCreatedAt(DateTime? createdAt) =>
      _syncCreatedAt = createdAt?.toUtc();

  void _setRepositoryName(String name) => _repositoryName = name;

  /// Test-only hooks to modify sync metadata without exposing public setters.
  @visibleForTesting
  void debugSetSyncStatus(SyncStatus status) => _setSyncStatus(status);

  @visibleForTesting
  void debugSetSyncOperation(SyncOperation operation) =>
      _setSyncOperation(operation);

  @visibleForTesting
  void debugSetSyncCreatedAt(DateTime? createdAt) =>
      _setSyncCreatedAt(createdAt);

  @visibleForTesting
  void debugSetRepositoryName(String name) => _setRepositoryName(name);
}

/// Extension methods for lists of events with sync metadata.
extension LocalFirstEventsX<T> on List<LocalFirstEvent<T>> {
  /// Converts a list of events to the sync JSON format.
  ///
  /// Groups objects by operation type (insert, update, delete) as expected
  /// by the push endpoint. Use [idFieldName] when your model id key differs
  /// from 'id'.
  Map<String, dynamic> toJson({
    required Map<String, dynamic> Function(T item) serializer,
    String idFieldName = 'id',
  }) {
    final inserts = <Map<String, dynamic>>[];
    final updates = <Map<String, dynamic>>[];
    final deletes = <String>[];

    for (var event in this) {
      final itemJson = serializer(event.data);

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
