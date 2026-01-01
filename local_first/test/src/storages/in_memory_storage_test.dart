import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

class _DummyRepo with LocalFirstRepository<Object> {
  _DummyRepo() {
    initLocalFirstRepository(
      name: 'items',
      getId: (obj) => (obj as Map)['id'] as String,
      toJson: (obj) => obj as JsonMap,
      fromJson: (json) => json,
      onConflict: (l, r) => r,
    );
  }
}

void main() {
  group('InMemoryLocalFirstStorage', () {
    late InMemoryLocalFirstStorage storage;

    setUp(() async {
      storage = InMemoryLocalFirstStorage();
      await storage.open(namespace: 'ns');
      await storage.initialize();
    });

    test('open/close toggles state and namespace', () async {
      expect(storage.isOpened, isTrue);
      expect(storage.isClosed, isFalse);
      expect(storage.currentNamespace, 'ns');

      await storage.close();
      expect(storage.isOpened, isFalse);
      expect(storage.isClosed, isTrue);
    });

    test('CRUD operations reflect in getAll/getById/deleteAll', () async {
      await storage.insert('items', {'id': '1', 'value': 10}, 'id');
      await storage.insert('items', {'id': '2', 'value': 20}, 'id');

      final all = await storage.getAll('items');
      expect(all.length, 2);
      expect(await storage.getById('items', '1'), containsPair('value', 10));

      await storage.update('items', '1', {'id': '1', 'value': 15});
      expect(await storage.getById('items', '1'), containsPair('value', 15));

      await storage.delete('items', '2');
      expect(await storage.getById('items', '2'), isNull);

      await storage.deleteAll('items');
      expect(await storage.getAll('items'), isEmpty);
    });

    test('clearAllData wipes tables, meta, and registered events', () async {
      await storage.insert('items', {'id': '1'}, 'id');
      await storage.setMeta('k', 'v');
      await storage.registerEvent('evt', DateTime.utc(2023));

      await storage.clearAllData();

      expect(await storage.getAll('items'), isEmpty);
      expect(await storage.getMeta('k'), isNull);
      expect(await storage.isEventRegistered('evt'), isFalse);
    });

    test('watch emits initial and subsequent updates', () async {
      final updates = <List<JsonMap>>[];
      final sub = storage.watch('items').listen(updates.add);

      await storage.insert('items', {'id': '1'}, 'id');
      await storage.insert('items', {'id': '2'}, 'id');
      await storage.update('items', '1', {'id': '1', 'value': 1});
      await storage.delete('items', '2');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(updates.firstOrNull, isNotEmpty);
      expect(updates.any((e) => e.any((r) => r['id'] == '1')), isTrue);
      expect(updates.any((e) => e.any((r) => r['id'] == '2')), isTrue);
      expect(updates.last.every((r) => r['id'] != '2'), isTrue);
    });

    test('queryTable applies filters, sorting, limit and offset', () async {
      await storage.insert('items', {'id': 'a', 'score': 5}, 'id');
      await storage.insert('items', {'id': 'b', 'score': 10}, 'id');
      await storage.insert('items', {'id': 'c', 'score': 15}, 'id');

      final result = await storage.queryTable(
        'items',
        filters: [QueryFilter(field: 'score', isGreaterThan: 5)],
        sorts: const [QuerySort(field: 'score', descending: true)],
        limit: 1,
        offset: 1,
      );

      final data = result['data'] as List;
      expect(data.length, 1);
      expect((data.single as Map)['id'], 'b');
    });

    test('query uses LocalFirstQuery helpers', () async {
      await storage.insert('items', {'id': '1', 'score': 1}, 'id');
      await storage.insert('items', {'id': '2', 'score': 2}, 'id');

      final repo = _DummyRepo();
      final query = LocalFirstQuery<Object>(
        repositoryName: 'items',
        delegate: storage,
        repository: repo,
      ).where('score', isGreaterThan: 1);

      final results = await storage.query(query);
      expect(results.length, 1);
      expect(results.single['id'], '2');
    });

    test('watchQuery emits filtered updates', () async {
      await storage.insert('items', {'id': '1', 'score': 1}, 'id');
      final repo = _DummyRepo();
      final query = LocalFirstQuery<Object>(
        repositoryName: 'items',
        delegate: storage,
        repository: repo,
      ).where('score', isGreaterThanOrEqualTo: 1);

      final collected = <List<JsonMap>>[];
      final sub = storage.watchQuery(query).listen(collected.add);

      await storage.insert('items', {'id': '2', 'score': 3}, 'id');
      await storage.insert('items', {'id': '3', 'score': 0}, 'id');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();

      expect(collected.first.length, 2);
      expect(collected.last.map((r) => r['id']), containsAll(['1', '2']));
      expect(collected.last.map((r) => r['id']), isNot(contains('3')));
    });

    test('event registration persists and prunes correctly', () async {
      final oldDate = DateTime.utc(2020);
      final newDate = DateTime.utc(2030);
      await storage.registerEvent('old', oldDate);
      await storage.registerEvent('new', newDate);

      expect(await storage.isEventRegistered('old'), isTrue);
      expect(await storage.isEventRegistered('new'), isTrue);

      await storage.pruneRegisteredEvents(DateTime.utc(2025));

      expect(await storage.isEventRegistered('old'), isFalse);
      expect(await storage.isEventRegistered('new'), isTrue);
    });
  });
}
