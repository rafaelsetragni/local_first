part of '../../local_first.dart';

/// Wrapper that adds synchronization metadata to a domain model.
///
/// Use this wrapper so your models can remain immutable/const without
/// requiring a mixin.
class LocalFirstEvent {
  LocalFirstEvent({
    required this.repositoryName,
    required this.syncOperation,
    required this.syncStatus,
    required this.data,
    String? eventId,
    DateTime? syncCreatedAt,
    DateTime? syncCreatedAtServer,
    this.syncServerSequence,
  }) : eventId = eventId ?? UuidUtil.generateUuidV7(),
       syncCreatedAt = (syncCreatedAt ?? DateTime.now()).toUtc(),
       syncCreatedAtServer = syncCreatedAtServer?.toUtc();

  final Object data;
  final String eventId;
  final SyncStatus syncStatus;
  final SyncOperation syncOperation;
  final DateTime syncCreatedAt;
  final DateTime? syncCreatedAtServer;
  final int? syncServerSequence;
  final String repositoryName;

  /// Returns true if this object has pending changes that need sync.
  bool get needSync => syncStatus != SyncStatus.ok;

  /// Returns true if this object is marked as deleted.
  bool get isDeleted => syncOperation == SyncOperation.delete;

  bool isA<T>() => data is T;
  T dataAs<T extends Object>() => data as T;

  LocalFirstEvent copyWith({
    Object? data,
    String? eventId,
    SyncStatus? syncStatus,
    SyncOperation? syncOperation,
    DateTime? syncCreatedAt,
    DateTime? syncCreatedAtServer,
    int? syncServerSequence,
    String? repositoryName,
  }) {
    return LocalFirstEvent(
      data: data ?? this.data,
      eventId: eventId ?? this.eventId,
      syncStatus: syncStatus ?? this.syncStatus,
      syncOperation: syncOperation ?? this.syncOperation,
      syncCreatedAt: syncCreatedAt ?? this.syncCreatedAt,
      syncCreatedAtServer: syncCreatedAtServer ?? this.syncCreatedAtServer,
      syncServerSequence: syncServerSequence ?? this.syncServerSequence,
      repositoryName: repositoryName ?? this.repositoryName,
    );
  }
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
  JsonMap toJson({required LocalFirstClient client}) {
    final JsonMap<JsonMap<List<dynamic>>> changes = {};

    for (var event in this) {
      final repo = client.getRepositoryByName(event.repositoryName);

      final serializedData = JsonMap.from(repo.toJson(event.data));
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

      final JsonMap<List> repoChanges = changes.putIfAbsent(
        event.repositoryName,
        () => {},
      );

      switch (event.syncOperation) {
        case SyncOperation.insert:
          repoChanges.putIfAbsent('insert', () => <JsonMap>[]).add(itemJson);
          break;
        case SyncOperation.update:
          repoChanges.putIfAbsent('update', () => <JsonMap>[]).add(itemJson);
          break;
        case SyncOperation.delete:
          repoChanges.putIfAbsent('delete', () => <String>[]).add(idValue);
          break;
      }
    }

    return changes;
  }
}

/// Represents a response from the server during a pull operation.
///
/// Contains all changes from the server grouped by repository, along with
/// the server's timestamp for tracking sync progress.
class LocalFirstRemoteResponse {
  /// Map of repositories to their changed objects.
  final Map<LocalFirstRepository, List<LocalFirstEvent>> changes;

  /// Last server sequence captured when this response was generated.
  final int serverSequence;

  LocalFirstRemoteResponse({
    required this.changes,
    required this.serverSequence,
  });
}
