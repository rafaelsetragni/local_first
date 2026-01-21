import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_hive_storage/local_first_hive_storage.dart';

class _TestModel {
  _TestModel(this.id, {required this.username});

  final String id;
  final String username;

  factory _TestModel.fromJson(JsonMap json) =>
      _TestModel(json['id'] as String, username: json['username'] as String);

  JsonMap toJson() => {'id': id, 'username': username};
}

void main() {
  group('HiveLocalFirstStorage', () {
    late Directory tempDir;
    late HiveLocalFirstStorage storage;

    LocalFirstRepository<_TestModel> buildRepo() {
      return LocalFirstRepository<_TestModel>.create(
        name: 'users',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: _TestModel.fromJson,
      );
    }

    LocalFirstQuery<_TestModel> buildQuery({
      bool includeDeleted = false,
      List<QueryFilter> filters = const [],
      List<QuerySort> sorts = const [],
      int? limit,
      int? offset,
    }) {
      return LocalFirstQuery<_TestModel>(
        repositoryName: 'users',
        delegate: storage,
        repository: buildRepo(),
        includeDeleted: includeDeleted,
        filters: filters,
        sorts: sorts,
        limit: limit,
        offset: offset,
      );
    }

    Future<void> seedEvent({
      required String table,
      required LocalFirstEvent<_TestModel> event,
    }) async {
      if (event is LocalFirstStateEvent<_TestModel>) {
        await storage.insert(
          table,
          {
            ...event.data.toJson(),
            '_lasteventId': event.eventId,
          },
          'id',
        );
      }
      await storage.insertEvent(table, event.toLocalStorageJson(), 'eventId');
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_local_first_test');
      await Directory('${tempDir.path}/ns1').create(recursive: true);
      storage = HiveLocalFirstStorage(
        customPath: tempDir.path,
        namespace: 'ns1',
      );
      await storage.initialize();
    });

    tearDown(() async {
      await storage.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('insert, getById, getAll, update, delete, deleteAll', () async {
      await storage.insert('users', {'id': '1', 'username': 'Alice'}, 'id');
      await storage.insert('users', {'id': '2', 'username': 'Bob'}, 'id');

      final byId = await storage.getById('users', '1');
      expect(byId, isNotNull);
      expect(byId?['username'], 'Alice');

      final all = await storage.getAll('users');
      expect(all.length, 2);

      await storage.update(
        'users',
        '1',
        {'id': '1', 'username': 'Charlie'},
      );
      final updated = await storage.getById('users', '1');
      expect(updated?['username'], 'Charlie');

      await storage.delete('users', '1');
      final afterDelete = await storage.getById('users', '1');
      expect(afterDelete, isNull);

      await storage.deleteAll('users');
      final afterDeleteAll = await storage.getAll('users');
      expect(afterDeleteAll, isEmpty);
    });

  test('set/get last sync and metadata', () async {
      await storage.setString('key', 'value');
      expect(await storage.getString('key'), 'value');
    });

    test('clearAllData wipes boxes and metadata', () async {
      await storage.insert('users', {'id': '1', 'username': 'Alice'}, 'id');
      await storage.setString('key', 'value');

      await storage.clearAllData();
      expect(await storage.getAll('users'), isEmpty);
      expect(await storage.getString('key'), isNull);
    });

    test('namespace isolation with useNamespace', () async {
      await storage.insert('users', {'id': '1', 'username': 'Alice'}, 'id');
      expect((await storage.getAll('users')).length, 1);

      await storage.useNamespace('ns2');
      expect(storage.namespace, 'ns2');
      expect(await storage.getAll('users'), isEmpty);

      await storage.insert('users', {'id': '2', 'username': 'Bob'}, 'id');
      expect((await storage.getAll('users')).length, 1);

      await storage.useNamespace('ns1');
      final original = await storage.getAll('users');
      expect(original.length, 1);
      expect(original.first['id'], '1');
    });

    test('insert/update should persist lastEventId metadata', () async {
      await storage.insert(
        'users',
        {
          'id': 'meta',
          'username': 'Meta',
          LocalFirstEvent.kLastEventId: 'evt-meta',
        },
        'id',
      );
      var fetched = await storage.getById('users', 'meta');
      expect(fetched?[LocalFirstEvent.kLastEventId], 'evt-meta');

      await storage.update(
        'users',
        'meta',
        {
          'id': 'meta',
          'username': 'Meta2',
          '_lasteventId': 'evt-updated',
        },
      );
      fetched = await storage.getById('users', 'meta');
      expect(fetched?[LocalFirstEvent.kLastEventId], 'evt-updated');
    });

    test('updateEvent should backfill dataId when missing', () async {
      await storage.updateEvent(
        'users',
        'evt-up',
        {
          'syncStatus': SyncStatus.pending.index,
          'operation': SyncOperation.insert.index,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        },
      );

      final fetched = await storage.getEventById('users', 'evt-up');
      expect(fetched?[LocalFirstEvent.kDataId], 'evt-up');
    });

    test('lazyCollections uses LazyBox for configured tables', () async {
      final lazyStorage = HiveLocalFirstStorage(
        customPath: tempDir.path,
        namespace: 'lazyNs',
        lazyCollections: {'lazy_users'},
      );
      await lazyStorage.initialize();

      await lazyStorage.insert(
        'lazy_users',
        {'id': '1', 'username': 'Lazy'},
        'id',
      );
      await lazyStorage.insert(
        'eager_users',
        {'id': '2', 'username': 'Eager'},
        'id',
      );

      final lazyAll = await lazyStorage.getAll('lazy_users');
      final eagerAll = await lazyStorage.getAll('eager_users');

      expect(lazyAll.length, 1);
      expect(eagerAll.length, 1);
    });

    test(
      'query returns state events and filters deleted when includeDeleted=false',
      () async {
        await seedEvent(
          table: 'users',
          event: LocalFirstEvent.createNewInsertEvent<_TestModel>(
            repository: buildRepo(),
            data: _TestModel('1', username: 'alice'),
            needSync: false,
          ),
        );
        await seedEvent(
          table: 'users',
          event: LocalFirstEvent.createNewDeleteEvent<_TestModel>(
            repository: buildRepo(),
            dataId: '1',
            needSync: false,
          ),
        );

        final events = await storage.query(buildQuery());
        expect(events.where((e) => e.needSync), isEmpty);
        expect(events.where((e) => e.isDeleted), isEmpty);
      },
    );

    test('query should sort and paginate results', () async {
      await storage.insert(
        'users',
        {
          'id': '1',
          'username': 'B',
          LocalFirstEvent.kLastEventId: 'evt-a',
        },
        'id',
      );
      await storage.insert(
        'users',
        {
          'id': '2',
          'username': 'A',
          LocalFirstEvent.kLastEventId: 'evt-b',
        },
        'id',
      );
      await storage.insertEvent(
        'users',
        {
          'eventId': 'evt-a',
          'dataId': '1',
          'syncStatus': SyncStatus.pending.index,
          'operation': SyncOperation.insert.index,
          'createdAt': 1,
        },
        'eventId',
      );
      await storage.insertEvent(
        'users',
        {
          'eventId': 'evt-b',
          'dataId': '2',
          'syncStatus': SyncStatus.pending.index,
          'operation': SyncOperation.insert.index,
          'createdAt': 2,
        },
        'eventId',
      );

      final sorted = await storage.query(
        buildQuery(
          sorts: [const QuerySort(field: 'username')],
          limit: 1,
          offset: 1,
        ),
      );

      expect(sorted.single.dataId, '1');
    });

    test('query honors includeDeleted', () async {
      final repo = buildRepo();
      await seedEvent(
        table: 'users',
        event: LocalFirstEvent.createNewInsertEvent<_TestModel>(
          repository: repo,
          data: _TestModel('1', username: 'alice'),
          needSync: true,
        ),
      );
      await seedEvent(
        table: 'users',
        event: LocalFirstEvent.createNewDeleteEvent<_TestModel>(
          repository: repo,
          dataId: '1',
          needSync: true,
        ),
      );

      final events = await storage.query(buildQuery(includeDeleted: true));
      expect(events.where((e) => e.isDeleted), isNotEmpty);
    });

    test('query skips entries that fail filters', () async {
      final repo = buildRepo();
      await seedEvent(
        table: 'users',
        event: LocalFirstEvent.createNewInsertEvent<_TestModel>(
          repository: repo,
          data: _TestModel('1', username: 'alice'),
          needSync: false,
        ),
      );

      final events = await storage.query(
        buildQuery(
          filters: const [QueryFilter(field: 'username', isEqualTo: 'bob')],
        ),
      );
      expect(events, isEmpty);
    });

    test('getAllEvents and getEventById merge data with metadata', () async {
      final repo = buildRepo();
      final insert = LocalFirstEvent.createNewInsertEvent<_TestModel>(
        repository: repo,
        data: _TestModel('42', username: 'alice'),
        needSync: false,
      );
      await seedEvent(table: 'users', event: insert);

      final events = await storage.getAllEvents('users');
      expect(events, isNotEmpty);
      expect(events.first['username'], 'alice');
      expect(events.first[LocalFirstEvent.kLastEventId], insert.eventId);

      final fetched = await storage.getEventById('users', insert.eventId);
      expect(fetched?[LocalFirstEvent.kDataId], '42');
      expect(fetched?['username'], 'alice');
    });

    test('watchQuery emits on data and event changes', () async {
      final repo = buildRepo();
      final query = buildQuery();
      await seedEvent(
        table: 'users',
        event: LocalFirstEvent.createNewInsertEvent<_TestModel>(
          repository: repo,
          data: _TestModel('1', username: 'alice'),
          needSync: false,
        ),
      );

      final stream = storage.watchQuery(query);
      final emitted = await stream.first;
      expect(
        emitted.whereType<LocalFirstStateEvent<_TestModel>>(),
        isNotEmpty,
      );
      await storage.close();
    });

    test('deleteEvent removes event', () async {
      await storage.insertEvent(
        'users',
        {
          'eventId': 'evt-del',
          'dataId': 'del',
          'syncStatus': SyncStatus.pending.index,
          'operation': SyncOperation.insert.index,
          'createdAt': 1,
        },
        'eventId',
      );
      await storage.deleteEvent('users', 'evt-del');

      final events = await storage.getAllEvents('users');
      expect(events.where((e) => e['eventId'] == 'evt-del'), isEmpty);
    });

    test('deleteAllEvents clears event boxes', () async {
      await storage.insertEvent(
        'users',
        {
          'eventId': 'evt-1',
          'dataId': '1',
          'syncStatus': SyncStatus.pending.index,
          'operation': SyncOperation.insert.index,
          'createdAt': 1,
        },
        'eventId',
      );
      await storage.insertEvent(
        'users',
        {
          'eventId': 'evt-2',
          'dataId': '2',
          'syncStatus': SyncStatus.pending.index,
          'operation': SyncOperation.delete.index,
          'createdAt': 2,
        },
        'eventId',
      );

      await storage.deleteAllEvents('users');

      final events = await storage.getAllEvents('users');
      expect(events, isEmpty);
    });

    test('containsId checks presence in box', () async {
      await storage.insert('users', {'id': '1', 'username': 'Alice'}, 'id');
      expect(await storage.containsId('users', '1'), isTrue);
      expect(await storage.containsId('users', 'missing'), isFalse);
    });

    test('should throw when used before initialization', () async {
      final fresh = HiveLocalFirstStorage(customPath: tempDir.path);
      expect(() => fresh.getAll('users'), throwsA(isA<StateError>()));
      expect(() => fresh.setString('k', 'v'), throwsA(isA<StateError>()));
      expect(() => fresh.getString('k'), throwsA(isA<StateError>()));
      expect(() => fresh.clearAllData(), throwsA(isA<StateError>()));
      expect(() => fresh.query(buildQuery()), throwsA(isA<StateError>()));
      expect(() => fresh.watchQuery(buildQuery()), throwsA(isA<StateError>()));
    });

    test('ensureSchema is a no-op', () async {
      await storage.ensureSchema(
        'users',
        {
          'id': LocalFieldType.text,
        },
        idFieldName: 'id',
      );
      await storage.insert('users', {'id': '1', 'username': 'Alice'}, 'id');
      final fetched = await storage.getById('users', '1');
      expect(fetched?['username'], 'Alice');
    });

    test('watchQuery cancels subscriptions on cancel', () async {
      final repo = buildRepo();
      await seedEvent(
        table: 'users',
        event: LocalFirstEvent.createNewInsertEvent<_TestModel>(
          repository: repo,
          data: _TestModel('1', username: 'alice'),
          needSync: false,
        ),
      );

      final stream = storage.watchQuery(buildQuery());
      final sub = stream.listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();
      expect(sub.isPaused, isFalse);
    });

    test('watchQuery surfaces errors from emitCurrent', () async {
      final stream = storage.watchQuery(buildQuery());
      await storage.close(); // Force query to throw inside emitCurrent

      await expectLater(stream.first, throwsA(isA<StateError>()));
    });

    test('initialize should invoke initFlutter when customPath is null',
        () async {
      var initCalled = false;
      final storageNoPath = HiveLocalFirstStorage(
        namespace: 'ns-init',
        initFlutter: ([String? _]) async {
          initCalled = true;
        },
        hive: Hive,
      );
      await storageNoPath.initialize();
      expect(initCalled, isTrue);
      expect(storageNoPath.namespace, 'ns-init');
      await storageNoPath.clearAllData();
      await storageNoPath.close();
    });
  });
}
