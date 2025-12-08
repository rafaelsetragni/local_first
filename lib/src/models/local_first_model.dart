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

/// Type alias for a list of [LocalFirstModel]s.
typedef LocalFirstModels<T extends Object> = List<LocalFirstModel<T>>;

/// Wraps an item with its synchronization metadata.
///
/// This class combines your data model with sync information like status,
/// operation type, and whether it needs synchronization.
///
/// All queries return [LocalFirstModel]s so you can inspect the sync state
/// of each item individually.
class LocalFirstModel<T extends Object> {
  /// The actual data item.
  final T item;

  /// The current synchronization status.
  final SyncStatus status;

  /// The type of operation (insert, update, delete).
  final SyncOperation operation;

  final LocalFirstRepository<T> _repository;

  /// Returns true if this object has pending changes that need sync.
  bool get needSync => status != SyncStatus.ok;

  /// Returns true if this object is marked as deleted.
  bool get isDeleted => operation == SyncOperation.delete;

  String get repositoryName => _repository.name;

  LocalFirstModel({
    required this.item,
    required this.status,
    required this.operation,
    required LocalFirstRepository<T> repository,
  }) : assert(T != Object, 'Type ot T must be specified'),
       _repository = repository;

  /// Converts the object and its metadata to JSON format.
  Map<String, dynamic> toJson() {
    return {
      ..._repository.toJson(item),
      '_sync_status': status.index,
      '_sync_operation': operation.index,
      '_sync_created_at': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Creates a copy of this object with optional field updates.
  LocalFirstModel<T> copyWith({
    T? item,
    SyncStatus? status,
    SyncOperation? operation,
  }) {
    return LocalFirstModel<T>(
      item: item ?? this.item,
      status: status ?? this.status,
      operation: operation ?? this.operation,
      repository: _repository,
    );
  }

  LocalFirstModel<T> fromJson(
    Map<String, dynamic> json, {
    SyncStatus syncStatus = SyncStatus.ok,
    SyncOperation operation = SyncOperation.insert,
  }) {
    return LocalFirstModel<T>(
      item: _repository.fromJson(json),
      status: syncStatus,
      operation: operation,
      repository: _repository,
    );
  }
}

/// Extension methods for lists of [LocalFirstModel]s.
extension LocalFirstModelsX<T extends Object> on List<LocalFirstModel<T>> {
  /// Converts a list of objects to the sync JSON format.
  ///
  /// Groups objects by operation type (insert, update, delete) as expected
  /// by the push endpoint.
  Map<String, dynamic> toJson() {
    final inserts = <Map<String, dynamic>>[];
    final updates = <Map<String, dynamic>>[];
    final deletes = <String>[];

    for (var obj in this) {
      final itemJson = obj._repository.toJson(obj.item);

      switch (obj.operation) {
        case SyncOperation.insert:
          inserts.add(itemJson);
          break;
        case SyncOperation.update:
          updates.add(itemJson);
          break;
        case SyncOperation.delete:
          deletes.add(obj._repository.getId(obj.item));
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
