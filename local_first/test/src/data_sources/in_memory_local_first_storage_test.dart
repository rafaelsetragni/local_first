import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

class _User {
  _User(this.id, this.username, {this.age = 0});

  final String id;
  final String username;
  final int age;

  JsonMap toJson() => {'id': id, 'username': username, 'age': age};

  factory _User.fromJson(JsonMap json) => _User(
        json['id'] as String,
        json['username'] as String,
        age: (json['age'] as num?)?.toInt() ?? 0,
      );
}

JsonMap _event({
  required String eventId,
  required String dataId,
  required SyncOperation operation,
  SyncStatus status = SyncStatus.pending,
  int? createdAt,
}) {
  return {
    LocalFirstEvent.kEventId: eventId,
    LocalFirstEvent.kDataId: dataId,
    LocalFirstEvent.kSyncStatus: status.index,
    LocalFirstEvent.kOperation: operation.index,
    LocalFirstEvent.kSyncCreatedAt:
        createdAt ?? DateTime.now().toUtc().millisecondsSinceEpoch,
  };
}

void main() {
  group('InMemoryLocalFirstStorage', () {
    late InMemoryLocalFirstStorage storage;
    late LocalFirstRepository<_User> repo;
    late LocalFirstQuery<_User> baseQuery;

    setUp(() async {
      storage = InMemoryLocalFirstStorage();
      await storage.initialize();

      repo = LocalFirstRepository<_User>.create(
        name: 'users',
        getId: (u) => u.id,
        toJson: (u) => u.toJson(),
        fromJson: _User.fromJson,
      );
      baseQuery = LocalFirstQuery<_User>(
        repositoryName: repo.name,
        delegate: storage,
        repository: repo,
      );
    });

    tearDown(() async {
      await storage.close();
    });

    Future<void> writeState({
      required String id,
      required String eventId,
      int age = 0,
    }) async {
      await storage.insert(
        repo.name,
        {
          'id': id,
          'username': 'user-$id',
          'age': age,
          LocalFirstEvent.kLastEventId: eventId,
        },
        'id',
      );
    }

    Future<void> writeEvent(JsonMap event) {
      return storage.insertEvent(
        repo.name,
        event,
        LocalFirstEvent.kEventId,
      );
    }

    test('persists state and attaches event metadata', () async {
      await writeState(id: '1', eventId: 'evt-1', age: 20);
      await writeEvent(
        _event(
          eventId: 'evt-1',
          dataId: '1',
          operation: SyncOperation.insert,
        ),
      );

      final all = await storage.getAll(repo.name);
      expect(all, hasLength(1));
      expect(all.single['username'], 'user-1');
      expect(all.single[LocalFirstEvent.kSyncStatus], SyncStatus.pending.index);

      final fetched = await storage.getById(repo.name, '1');
      expect(fetched?[LocalFirstEvent.kEventId], 'evt-1');
      expect(await storage.containsId(repo.name, '1'), isTrue);

      await storage.delete(repo.name, '1');
      expect(await storage.containsId(repo.name, '1'), isFalse);
    });

    test('exposes events merged with data when available', () async {
      await writeState(id: 'merge', eventId: 'evt-merge');
      await writeEvent(
        _event(
          eventId: 'evt-merge',
          dataId: 'merge',
          operation: SyncOperation.insert,
          status: SyncStatus.ok,
        ),
      );

      await writeEvent(
        _event(
          eventId: 'evt-delete',
          dataId: 'ghost',
          operation: SyncOperation.delete,
        ),
      );

      final events = await storage.getAllEvents(repo.name);
      final merged = events
          .firstWhere((row) => row[LocalFirstEvent.kEventId] == 'evt-merge');
      expect(merged['username'], 'user-merge');
      expect(merged[LocalFirstEvent.kSyncStatus], SyncStatus.ok.index);

      final deleteEvent = events
          .firstWhere((row) => row[LocalFirstEvent.kEventId] == 'evt-delete');
      expect(deleteEvent['id'], 'ghost');
      expect(deleteEvent[LocalFirstEvent.kData], isNull);
    });

    test('query filters, sorts, paginates, and handles deletes', () async {
      await writeState(id: '1', eventId: 'evt-1', age: 10);
      await writeState(id: '2', eventId: 'evt-2', age: 25);
      await writeState(id: '3', eventId: 'evt-3', age: 35);

      await writeEvent(_event(
        eventId: 'evt-1',
        dataId: '1',
        operation: SyncOperation.insert,
      ));
      await writeEvent(_event(
        eventId: 'evt-2',
        dataId: '2',
        operation: SyncOperation.insert,
      ));
      await writeEvent(_event(
        eventId: 'evt-3',
        dataId: '3',
        operation: SyncOperation.insert,
      ));

      final sorted = await storage.query(
        baseQuery
            .where('age', isGreaterThan: 15)
            .orderBy('age')
            .startAfter(0)
            .limitTo(1),
      );

      final stateEvent =
          sorted.whereType<LocalFirstStateEvent<_User>>().single;
      expect(stateEvent.data.id, '2');

      await storage.insertEvent(
        repo.name,
        _event(
          eventId: 'evt-del',
          dataId: '2',
          operation: SyncOperation.delete,
          status: SyncStatus.ok,
        ),
        LocalFirstEvent.kEventId,
      );
      await storage.delete(repo.name, '2');

      final withoutDeleted = await storage.query(baseQuery);
      expect(withoutDeleted.map((e) => e.dataId), isNot(contains('2')));

      final withDeleted = await storage.query(baseQuery.withDeleted());
      expect(
        withDeleted.where((e) => e.isDeleted).map((e) => e.dataId),
        contains('2'),
      );
    });

    test('watchQuery is reactive to state and event changes', () async {
      final emissions = <List<LocalFirstEvent<_User>>>[];
      final sub = storage.watchQuery(baseQuery).listen(emissions.add);

      await writeState(id: '1', eventId: 'evt-1', age: 20);
      await writeEvent(
        _event(
          eventId: 'evt-1',
          dataId: '1',
          operation: SyncOperation.insert,
        ),
      );
      await pumpEventQueue();
      expect(emissions.last.single.dataId, '1');

      await storage.updateEvent(
        repo.name,
        'evt-1',
        _event(
          eventId: 'evt-1',
          dataId: '1',
          operation: SyncOperation.update,
          status: SyncStatus.ok,
        ),
      );
      await pumpEventQueue();
      final updated = emissions.last.whereType<LocalFirstStateEvent<_User>>();
      expect(updated.single.syncStatus, SyncStatus.ok);

      await storage.insertEvent(
        repo.name,
        _event(
          eventId: 'evt-del',
          dataId: '1',
          operation: SyncOperation.delete,
          status: SyncStatus.ok,
        ),
        LocalFirstEvent.kEventId,
      );
      await storage.delete(repo.name, '1');
      await pumpEventQueue();
      expect(emissions.last, isEmpty);

      await sub.cancel();
    });

    test('metadata and clear operations wipe state', () async {
      await storage.setString('k', 'v');
      await writeState(id: 'persist', eventId: 'evt-x');
      await writeEvent(
        _event(
          eventId: 'evt-x',
          dataId: 'persist',
          operation: SyncOperation.insert,
        ),
      );

      expect(await storage.getString('k'), 'v');
      expect(await storage.getAll(repo.name), isNotEmpty);

      await storage.clearAllData();

      expect(await storage.getString('k'), isNull);
      expect(await storage.getAll(repo.name), isEmpty);
      expect(await storage.getAllEvents(repo.name), isEmpty);
    });
  });
}
