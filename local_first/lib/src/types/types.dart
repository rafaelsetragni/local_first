part of '../../local_first.dart';

typedef JsonMap<T> = Map<String, T>;

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

/// Type alias for a list of events with sync metadata.
typedef LocalFirstEvents = List<LocalFirstEvent>;

extension DateTimeJson on DateTime {
  String toJson() => toIso8601String();
}
