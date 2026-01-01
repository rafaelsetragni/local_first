part of '../../local_first.dart';

/// Test-only adapter exposing internal helpers of [LocalFirstRepository].
@visibleForTesting
class LocalFirstRepositoryTestAdapter<T extends Object> {
  final LocalFirstRepository<T> repo;

  LocalFirstRepositoryTestAdapter(this.repo);

  Future<void> pushLocalEventToRemote(LocalFirstEvent event) =>
      repo._pushLocalEventToRemote(event);

  Future<void> mergeRemoteItems(List<LocalFirstEvent> events) =>
      repo._mergeRemoteItems(events);

  LocalFirstEvent prepareForInsert(T model) => repo._prepareForInsert(model);

  LocalFirstEvent prepareForUpdate(
    LocalFirstEvent existing,
    T model, {
    required String eventId,
  }) =>
      repo._prepareForUpdate(existing, model, eventId: eventId);

  LocalFirstEvent buildRemoteEvent(
    Map<String, dynamic> json, {
    required SyncOperation operation,
  }) =>
      repo._buildRemoteEvent(json, operation: operation);

  Future<void> updateEventStatus(LocalFirstEvent event) =>
      repo._updateEventStatus(event);

  LocalFirstEvent eventFromJson(Map<String, dynamic> json) =>
      repo._eventFromJson(json);

  Map<String, dynamic> toStorageJson(LocalFirstEvent event) =>
      repo._toStorageJson(event);
}
