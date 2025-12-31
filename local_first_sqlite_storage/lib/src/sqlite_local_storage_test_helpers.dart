part of 'sqlite_local_storage.dart';

extension SqliteLocalFirstStorageTestHelpers on SqliteLocalFirstStorage {
  int observerCount(String repositoryName) {
    return _observers[repositoryName]?.length ?? 0;
  }

  void addClosedObserverFor(LocalFirstQuery query) {
    final controller = StreamController<List<JsonMap>>.broadcast();
    controller.close();
    final observer = _SqliteQueryObserver(query, controller);
    _observers
        .putIfAbsent(query.repositoryName, () => <_SqliteQueryObserver>{})
        .add(observer);
  }
}
