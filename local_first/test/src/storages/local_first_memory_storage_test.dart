import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

void main() {
  group('LocalFirstMemoryStorage', () {
    late LocalFirstMemoryStorage storage;

    setUp(() {
      storage = LocalFirstMemoryStorage();
    });

    test('insert stores item', () async {
      await storage.insert('repo', {'id': '1', 'name': 'a'}, 'id');
      final all = await storage.getAll('repo');
      expect(all.map((e) => e['id']), contains('1'));
    });

    test('getById returns inserted item', () async {
      await storage.insert('repo', {'id': '1', 'name': 'a'}, 'id');
      final item = await storage.getById('repo', '1');
      expect(item?['name'], 'a');
    });

    test('update changes stored item', () async {
      await storage.insert('repo', {'id': '1', 'name': 'a'}, 'id');
      await storage.update('repo', '1', {'id': '1', 'name': 'aa'});
      final updated = await storage.getById('repo', '1');
      expect(updated?['name'], 'aa');
    });

    test('delete removes item', () async {
      await storage.insert('repo', {'id': '1', 'name': 'a'}, 'id');
      await storage.insert('repo', {'id': '2', 'name': 'b'}, 'id');
      await storage.delete('repo', '2');
      final afterDelete = await storage.getAll('repo');
      expect(afterDelete.map((e) => e['id']), ['1']);
    });

    test('data and event stores are isolated', () async {
      await storage.insert('repo', {'id': '1', 'name': 'a'}, 'id');
      await storage.pullRemoteEvent({
        'repository': 'repo',
        'event_id': 'e1',
        'record_id': '99',
        'payload': {'id': '99'},
        'created_at': 0,
      });

      final data = await storage.getAll('repo');
      expect(data.length, 1);
      final events = await storage.getEvents(repositoryName: 'repo');
      expect(events.length, 1);

      // ensure data insert did not create an event, and event insert did not create data
      expect(data.single['id'], '1');
      expect(events.single['record_id'], '99');
    });

    test('clearAllData clears tables and events', () async {
      await storage.insert('repo', {'id': '1'}, 'id');
      await storage.pullRemoteEvent({
        'repository': 'repo',
        'event_id': 'e1',
        'record_id': '1',
        'payload': {'id': '1'},
        'created_at': 0,
      });

      await storage.clearAllData();
      expect(await storage.getAll('repo'), isEmpty);
      expect(await storage.getEvents(), isEmpty);
    });

    test('event log upsert and retrieval', () async {
      final event = {
        'repository': 'repo',
        'event_id': 'e1',
        'record_id': '1',
        'payload': {'id': '1'},
        'created_at': 10,
      };
      await storage.pullRemoteEvent(event);
      await storage.pullRemoteEvent({...event, 'created_at': 20});

      final fetched = await storage.getEventById('e1');
      expect(fetched?['created_at'], 20);

      final byRepo = await storage.getEvents(repositoryName: 'repo');
      expect(byRepo.length, 1);
    });

    test('deleteEvent/clearEvents/pruneEvents', () async {
      await storage.pullRemoteEvent({
        'repository': 'repo',
        'event_id': 'old',
        'record_id': '1',
        'payload': {'id': '1'},
        'created_at': DateTime.utc(2020, 1, 1).millisecondsSinceEpoch,
      });
      await storage.pullRemoteEvent({
        'repository': 'repo',
        'event_id': 'new',
        'record_id': '2',
        'payload': {'id': '2'},
        'created_at': DateTime.utc(2030, 1, 1).millisecondsSinceEpoch,
      });

      await storage.pruneEvents(DateTime.utc(2025, 1, 1));
      final remaining = await storage.getEvents();
      expect(remaining.map((e) => e['event_id']), ['new']);

      await storage.deleteEvent('new');
      expect((await storage.getEvents()).isEmpty, isTrue);

      await storage.pullRemoteEvent({
        'repository': 'repo',
        'event_id': 'x',
        'record_id': '3',
        'payload': {'id': '3'},
        'created_at': 1,
      });
      await storage.clearEvents();
      expect((await storage.getEvents()).isEmpty, isTrue);
    });

    test('query applies filters, sort, limit, offset', () async {
      await storage.insert('repo', {'id': '1', 'score': 10}, 'id');
      await storage.insert('repo', {'id': '2', 'score': 30}, 'id');
      await storage.insert('repo', {'id': '3', 'score': 20}, 'id');

      final query = LocalFirstQuery<Map<String, dynamic>>(
        repositoryName: 'repo',
        delegate: storage,
        fromEvent: (_) => throw UnimplementedError(),
      )
          .where('score', isGreaterThan: 10)
          .orderBy('score', descending: true)
          .limitTo(1)
          .startAfter(0);

      final result = await storage.query(query);
      expect(result.length, 1);
      expect(result.first['id'], '2');
    });

    test('watchQuery emits snapshot', () async {
      await storage.insert('repo', {'id': '1'}, 'id');
      final query = LocalFirstQuery<Map<String, dynamic>>(
        repositoryName: 'repo',
        delegate: storage,
        fromEvent: (_) => throw UnimplementedError(),
      );

      final snapshot = await storage.watchQuery(query).first;
      expect(snapshot.first['id'], '1');
    });
  });
}
