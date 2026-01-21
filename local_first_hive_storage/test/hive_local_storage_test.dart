import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_hive_storage/local_first_hive_storage.dart';
import 'package:mocktail/mocktail.dart';

class _TestModel {
  _TestModel(this.id, {required this.username});

  final String id;
  final String username;

  factory _TestModel.fromJson(JsonMap json) =>
      _TestModel(json['id'] as String, username: json['username'] as String);

  JsonMap toJson() => {'id': id, 'username': username};
}

class _MockBox extends Mock implements Box<Map<dynamic, dynamic>> {}

class _MockDynamicBox extends Mock implements Box<dynamic> {}

class _MockHive extends Mock implements HiveInterface {}

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
      LocalFirstRepository<_TestModel>? repository,
    }) {
      return LocalFirstQuery<_TestModel>(
        repositoryName: 'users',
        delegate: storage,
        repository: repository ?? buildRepo(),
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
      await storage.setConfigValue('key', 'value');
      expect(await storage.getConfigValue('key'), 'value');
    });

    test('config key/value supports shared_preferences types', () async {
      expect(await storage.containsConfigKey('missing'), isFalse);

      expect(await storage.setConfigValue('bool', true), isTrue);
      expect(await storage.setConfigValue('int', 1), isTrue);
      expect(await storage.setConfigValue('double', 1.5), isTrue);
      expect(await storage.setConfigValue('string', 'ok'), isTrue);
      expect(await storage.setConfigValue('list', <String>['a', 'b']), isTrue);

      expect(await storage.getConfigValue<bool>('bool'), isTrue);
      expect(await storage.getConfigValue<int>('int'), 1);
      expect(await storage.getConfigValue<double>('double'), 1.5);
      expect(await storage.getConfigValue<String>('string'), 'ok');
      expect(await storage.getConfigValue<List<String>>('list'), ['a', 'b']);
      expect(await storage.getConfigValue<dynamic>('list'), ['a', 'b']);

      expect(
        await storage.getConfigKeys(),
        containsAll(<String>['bool', 'int', 'double', 'string', 'list']),
      );

      expect(
        () => storage.setConfigValue('invalid', {'a': 1}),
        throwsArgumentError,
      );

      expect(await storage.removeConfig('string'), isTrue);
      expect(await storage.containsConfigKey('string'), isFalse);

      await storage.clearConfig();
      expect(await storage.getConfigKeys(), isEmpty);
    });

    test('clearAllData wipes boxes and metadata', () async {
      await storage.insert('users', {'id': '1', 'username': 'Alice'}, 'id');
      await storage.setConfigValue('key', 'value');

      await storage.clearAllData();
      expect(await storage.getAll('users'), isEmpty);
      expect(await storage.getConfigValue('key'), isNull);
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
      expect(() => fresh.setConfigValue('k', 'v'), throwsA(isA<StateError>()));
      expect(() => fresh.getConfigValue('k'), throwsA(isA<StateError>()));
      expect(
        () => fresh.containsConfigKey('k'),
        throwsA(isA<StateError>()),
      );
      expect(() => fresh.getConfigKeys(), throwsA(isA<StateError>()));
      expect(() => fresh.removeConfig('k'), throwsA(isA<StateError>()));
      expect(() => fresh.clearConfig(), throwsA(isA<StateError>()));
      expect(() => fresh.clearAllData(), throwsA(isA<StateError>()));
      expect(() => fresh.query(buildQuery()), throwsA(isA<StateError>()));
      expect(() => fresh.watchQuery(buildQuery()), throwsA(isA<StateError>()));
    });

    test('close swallows box close errors', () async {
      final throwingBox = _MockBox();
      when(() => throwingBox.name).thenReturn('throw');
      when(throwingBox.close).thenThrow(Exception('boom'));

      storage.addBoxToCacheForTest('users', throwingBox);
      await storage.close(); // should not throw
    });

    test('getAll/getAllEvents/getEventById skip null entries', () async {
      final nullState = _MockBox();
      when(() => nullState.name).thenReturn('users');
      when(() => nullState.keys).thenReturn(['s-null']);
      when(() => nullState.get(any())).thenReturn(null);
      final nullEvents = _MockBox();
      when(() => nullEvents.name).thenReturn('users__events');
      when(() => nullEvents.keys).thenReturn(['e-null']);
      when(() => nullEvents.get(any())).thenReturn(null);

      storage.addBoxToCacheForTest('users', nullState);
      storage.addBoxToCacheForTest('users', nullEvents, isEvent: true);

      expect(await storage.getAll('users'), isEmpty);
      expect(await storage.getAllEvents('users'), isEmpty);
      expect(await storage.getEventById('users', 'any'), isNull);
    });

    test('getAllEvents should skip null event metadata', () async {
      final dataBox = _MockBox();
      when(() => dataBox.name).thenReturn('users');
      when(() => dataBox.keys).thenReturn(<String>[]);
      when(() => dataBox.get(any())).thenReturn(null);

      final eventBox = _MockBox();
      when(() => eventBox.name).thenReturn('users__events');
      when(() => eventBox.keys).thenReturn(['e-null']);
      when(() => eventBox.get(any())).thenReturn(null);

      storage.addBoxToCacheForTest('users', dataBox);
      storage.addBoxToCacheForTest('users', eventBox, isEvent: true);

      expect(await storage.getAllEvents('users'), isEmpty);
    });

    test('clearAllData tolerates deleteBoxFromDisk errors', () async {
      final mockHive = _MockHive();
      final metadataBox = _MockDynamicBox();
      when(() => mockHive.init(any())).thenReturn(null);
      when(() => mockHive.openBox<dynamic>(any()))
          .thenAnswer((_) async => metadataBox);
      when(() => metadataBox.clear()).thenAnswer((_) async => 0);
      when(() => metadataBox.close()).thenAnswer((_) async {});
      when(() => mockHive.deleteBoxFromDisk(any())).thenThrow(Exception('fail'));

      final customStorage = HiveLocalFirstStorage(
        customPath: tempDir.path,
        hive: mockHive,
        initFlutter: ([String? _]) async {},
      );
      await customStorage.initialize();

      final box = _MockBox();
      when(() => box.name).thenReturn('state_box');
      when(box.clear).thenAnswer((_) async => 0);
      when(box.close).thenAnswer((_) async {});
      customStorage.addBoxToCacheForTest('users', box);

      await customStorage.clearAllData(); // should not throw despite delete errors
    });

    test('query skips null/malformed entries and ignores bad delete events',
        () async {
      final stateBox = _MockBox();
      when(() => stateBox.name).thenReturn('users');
      when(() => stateBox.keys).thenReturn(['s-null']);
      when(() => stateBox.get(any())).thenReturn(null);

      final eventBox = _MockBox();
      when(() => eventBox.name).thenReturn('users__events');
      when(() => eventBox.keys).thenReturn(['e-null', 'e-bad']);
      // First event returns null, second is malformed delete without dataId.
      when(() => eventBox.get('e-null')).thenReturn(null);
      when(() => eventBox.get('e-bad')).thenReturn({
        'eventId': 'e-bad',
        'operation': SyncOperation.delete.index,
        'syncStatus': SyncStatus.pending.index,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        // Missing dataId to trigger FormatException inside fromLocalStorage.
      });

      storage.addBoxToCacheForTest('users', stateBox);
      storage.addBoxToCacheForTest('users', eventBox, isEvent: true);

      final repo = buildRepo();
      final query = buildQuery(includeDeleted: true, repository: repo);
      final events = await storage.query(query);

      expect(events, isEmpty); // malformed and null entries ignored
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
