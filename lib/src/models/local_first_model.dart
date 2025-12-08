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
typedef LocalFirstModels<T extends LocalFirstModel> = List<T>;

/// Mixin that adds synchronization metadata to your models.
///
/// Apply this mixin to your domain classes so repositories can manage
/// sync state without wrapping your objects.
mixin LocalFirstModel {
  SyncStatus syncStatus = SyncStatus.ok;
  SyncOperation syncOperation = SyncOperation.insert;
  DateTime? syncCreatedAt;
  String repositoryName = '';

  /// Override to serialize your domain fields (metadata is added separately).
  Map<String, dynamic> toJson();

  /// Returns true if this object has pending changes that need sync.
  bool get needSync => syncStatus != SyncStatus.ok;

  /// Returns true if this object is marked as deleted.
  bool get isDeleted => syncOperation == SyncOperation.delete;
}

/// Extension methods for lists of models with sync metadata.
extension LocalFirstModelsX<T extends LocalFirstModel> on List<T> {
  /// Converts a list of objects to the sync JSON format.
  ///
  /// Groups objects by operation type (insert, update, delete) as expected
  /// by the push endpoint.
  Map<String, dynamic> toJson() {
    final inserts = <Map<String, dynamic>>[];
    final updates = <Map<String, dynamic>>[];
    final deletes = <String>[];

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
          deletes.add(itemJson['id']?.toString() ?? '');
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
  final Map<LocalFirstRepository, List<LocalFirstModel>> changes;

  /// Server timestamp when this response was generated.
  final DateTime timestamp;

  LocalFirstResponse({required this.changes, required this.timestamp});
}
