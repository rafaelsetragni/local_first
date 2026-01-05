part of 'sqlite_local_storage.dart';

extension SqliteLocalFirstStorageTestHelpers on SqliteLocalFirstStorage {
  int observerCount(String repositoryName) {
    return _observers[repositoryName]?.length ?? 0;
  }

  void addClosedObserverFor(LocalFirstQuery query) {
    final stream = ValueStream<List<JsonMap<dynamic>>>();
    stream.close();
    final observer = _SqliteQueryObserver(query, stream);
    _observers
        .putIfAbsent(query.repositoryName, () => <_SqliteQueryObserver>{})
        .add(observer);
  }
}
