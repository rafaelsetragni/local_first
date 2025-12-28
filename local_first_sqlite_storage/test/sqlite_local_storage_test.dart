import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_sqlite_storage/local_first_sqlite_storage.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sqlite_local_storage_test.mocks.dart';

@GenerateMocks([QueryBehavior, DatabaseFactory, Database])
class DummyModel {
  DummyModel(this.id, {required this.username, required this.age});

  final String id;
  final String username;
  final int age;

  factory DummyModel.fromJson(Map<String, dynamic> json) {
    return DummyModel(
      json['id'] as String,
      username: json['username'] as String,
      age: json['age'] as int,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'age': age};
}

abstract class QueryBehavior {
  Future<List<Map<String, dynamic>>> call(LocalFirstQuery query);
}

class MockableSqliteLocalFirstStorage extends SqliteLocalFirstStorage {
  MockableSqliteLocalFirstStorage({
    required super.dbFactory,
    required super.databasePath,
    required this.behavior,
  });

  final QueryBehavior behavior;

  @override
  Future<List<Map<String, dynamic>>> query(
    LocalFirstQuery query,
  ) {
    return behavior(query);
  }
}

void main() {
  sqfliteFfiInit();

  const schema = {
    'username': LocalFieldType.text,
    'age': LocalFieldType.integer,
    'score': LocalFieldType.real,
    'verified': LocalFieldType.boolean,
    'birth': LocalFieldType.datetime,
    'avatar': LocalFieldType.blob,
    'nickname': LocalFieldType.text,
    'nullable': LocalFieldType.text,
  };

  group('SqliteLocalFirstStorage (ffi)', () {
    late SqliteLocalFirstStorage storage;

    LocalFirstQuery<DummyModel> buildQuery({
      List<QueryFilter> filters = const [],
      List<QuerySort> sorts = const [],
      int? limit,
      int? offset,
    }) {
      return LocalFirstQuery<DummyModel>(
        repositoryName: 'users',
        delegate: storage,
        repository: LocalFirstRepository.create<DummyModel>(
          name: 'users',
          getId: (m) => m.id,
          toJson: (m) => m.toJson(),
          fromJson: DummyModel.fromJson,
          onConflict: (l, r) => l,
          schema: schema,
        ),
        filters: filters,
        sorts: sorts,
        limit: limit,
        offset: offset,
      );
    }

    Future<void> insertRow(Map<String, dynamic> item) {
      final now = DateTime.now().millisecondsSinceEpoch;
      return storage.insert('users', {
        ...item,
        '_sync_status': SyncStatus.ok.index,
        '_sync_operation': SyncOperation.insert.index,
        '_sync_created_at': now,
      }, 'id');
    }

    setUp(() async {
      storage = SqliteLocalFirstStorage(
        databasePath: inMemoryDatabasePath,
        dbFactory: databaseFactoryFfi,
      );
      await storage.open(namespace: 'test_ns');
      await storage.initialize();
      await storage.ensureSchema('users', schema, idFieldName: 'id');
    });

    tearDown(() async {
      await storage.close();
    });

    test('filters and sorts using schema columns', () async {
      await insertRow({'id': '1', 'username': 'alice', 'age': 20});
      await insertRow({'id': '2', 'username': 'bob', 'age': 35});
      await insertRow({'id': '3', 'username': 'carol', 'age': 28});

      final results = await storage.query(
        buildQuery(
          filters: [QueryFilter(field: 'age', isGreaterThan: 25)],
          sorts: [QuerySort(field: 'age', descending: true)],
        ),
      );

      expect(results.map((e) => e['id']), ['2', '3']);
    });

    test('applies limit and offset', () async {
      await insertRow({
        'id': '1',
        'username': 'alice',
        'age': 20,
        'score': 1.1,
      });
      await insertRow({'id': '2', 'username': 'bob', 'age': 25, 'score': 2.2});
      await insertRow({
        'id': '3',
        'username': 'carol',
        'age': 30,
        'score': 3.3,
      });

      final results = await storage.query(
        buildQuery(sorts: [const QuerySort(field: 'age')], limit: 1, offset: 1),
      );

      expect(results.single['id'], '2');
    });

    test('encodes boolean, datetime, real, blob, and fallback types', () async {
      final birth = DateTime.utc(2000, 1, 1);
      final avatarBytes = [1, 2, 3];

      await insertRow({
        'id': 'enc',
        'username': 'types',
        'age': 18,
        'verified': true,
        'birth': birth,
        'score': 9.5,
        'avatar': avatarBytes,
        'nullable': null,
        'nickname': 'nick',
      });

      final row = await storage.getById('users', 'enc');
      // JSON payload is preserved, but columns are encoded for indexing.
      expect(row?['verified'], isTrue);
      expect(row?['birth'], isA<String>()); // stored as ISO string in JSON
      expect(row?['score'], 9.5);
      expect(row?['avatar'], avatarBytes);
      expect(row?['nullable'], isNull);
      expect(row?['nickname'], 'nick');
    });

    test('encodes boolean when provided as numeric', () async {
      await insertRow({
        'id': 'mix_bool',
        'username': 'mixed',
        'age': 30,
        'verified': 0, // numeric bool
        'score': 1.0,
      });

      final row = await storage.getById('users', 'mix_bool');
      expect(row?['verified'], 0);
    });

    test('encodes datetime when provided as string', () async {
      await insertRow({
        'id': 'mix_dt',
        'username': 'mixed',
        'age': 31,
        'birth': '2024-01-01T00:00:00.000Z', // string datetime
      });

      final row = await storage.getById('users', 'mix_dt');
      expect(row?['birth'], '2024-01-01T00:00:00.000Z');
    });

    test('insert, getById, update, and delete round trip', () async {
      await insertRow({'id': '10', 'username': 'zelda', 'age': 40});

      final fetched = await storage.getById('users', '10');
      expect(fetched?['username'], 'zelda');

      await storage.update('users', '10', {
        'id': '10',
        'username': 'zelda',
        'age': 41,
        '_sync_status': SyncStatus.ok.index,
        '_sync_operation': SyncOperation.update.index,
        '_sync_created_at': DateTime.now().millisecondsSinceEpoch,
      });

      final updated = await storage.getById('users', '10');
      expect(updated?['age'], 41);

      await storage.delete('users', '10');
      final afterDelete = await storage.getById('users', '10');
      expect(afterDelete, isNull);
    });

    test('deleteAll and clearAllData remove rows and metadata', () async {
      await insertRow({'id': '1', 'username': 'a', 'age': 20});
      await storage.setMeta('key', 'value');

      await storage.deleteAll('users');
      expect(await storage.getAll('users'), isEmpty);

      await insertRow({'id': '2', 'username': 'b', 'age': 21});
      await storage.clearAllData();
      expect(await storage.getAll('users'), isEmpty);
      expect(await storage.getMeta('key'), isNull);
    });

    test('setMeta and getMeta store values', () async {
      await storage.setMeta('foo', 'bar');
      expect(await storage.getMeta('foo'), 'bar');
    });

    test('watchQuery emits on changes', () async {
      final stream = storage.watchQuery(buildQuery());

      final expectation = expectLater(
        stream,
        emitsInOrder([
          isEmpty,
          predicate<List<Map<String, dynamic>>>(
            (items) => items.any((m) => m['id'] == 'w1'),
          ),
        ]),
      );

      await insertRow({'id': 'w1', 'username': 'watch', 'age': 22});
      await expectation;
    });

    test('watchQuery throws when storage not initialized', () {
      final uninit = SqliteLocalFirstStorage(
        databasePath: inMemoryDatabasePath,
        dbFactory: databaseFactoryFfi,
      );

      expect(() => uninit.watchQuery(buildQuery()), throwsA(isA<StateError>()));
    });

    test('close closes watchQuery observers', () async {
      final stream = storage.watchQuery(buildQuery());
      final done = Completer<void>();
      var isClosed = false;
      final sub = stream.listen(
        (_) {},
        onDone: () {
          isClosed = true;
          done.complete();
        },
        onError: (_) {},
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await storage.close();
      await done.future;
      expect(isClosed, isTrue);
      await sub.cancel();
    });

    test('watchQuery surfaces query errors via addError', () async {
      final behavior = MockQueryBehavior();
      final failingQuery = buildQuery();
      when(behavior.call(failingQuery)).thenThrow(StateError('boom'));

      final throwing = MockableSqliteLocalFirstStorage(
        dbFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
        behavior: behavior,
      );

      await throwing.open(namespace: 'error_ns');
      await throwing.initialize();
      await throwing.ensureSchema('users', schema, idFieldName: 'id');

      final stream = throwing.watchQuery(failingQuery);
      await expectLater(stream, emitsError(isA<StateError>()));

      await throwing.close();
    });

    test('_notifyWatchers catches query errors', () async {
      final behavior = MockQueryBehavior();
      final failingQuery = buildQuery();
      when(behavior.call(failingQuery)).thenAnswer(
        (_) => Future<List<Map<String, dynamic>>>.error(StateError('boom')),
      );

      final toggle = MockableSqliteLocalFirstStorage(
        dbFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
        behavior: behavior,
      );
      await toggle.open(namespace: 'toggle_ns');
      await toggle.initialize();
      await toggle.ensureSchema('users', schema, idFieldName: 'id');

      final controllerStream = toggle.watchQuery(failingQuery);
      // Consume initial emission/error.
      await controllerStream.first.catchError(
        (_) => <Map<String, dynamic>>[],
        test: (_) => true,
      );

      final expectation = expectLater(
        controllerStream,
        emitsError(isA<StateError>()),
      );

      await toggle.insert('users', {
        'id': 'err',
        'username': 'err',
        'age': 1,
        '_sync_status': SyncStatus.ok.index,
        '_sync_operation': SyncOperation.insert.index,
        '_sync_created_at': DateTime.now().millisecondsSinceEpoch,
      }, 'id');

      await expectation;
      await toggle.close();
    });

    test(
      '_notifyWatchers reruns query when observers exist for repository',
      () async {
        final behavior = MockQueryBehavior();
        when(
          behavior.call(any),
        ).thenAnswer((_) async => <Map<String, dynamic>>[]);

        final observing = MockableSqliteLocalFirstStorage(
          dbFactory: databaseFactoryFfi,
          databasePath: inMemoryDatabasePath,
          behavior: behavior,
        );

        await observing.open(namespace: 'observer_ns');
        await observing.initialize();
        await observing.ensureSchema('users', schema, idFieldName: 'id');

        final query = buildQuery();
        final stream = observing.watchQuery(query);
        final emissions = stream.take(2).toList();
        await observing.insert('users', {
          'id': 'obs',
          'username': 'obs',
          'age': 1,
          '_sync_status': SyncStatus.ok.index,
          '_sync_operation': SyncOperation.insert.index,
          '_sync_created_at': DateTime.now().millisecondsSinceEpoch,
        }, 'id');

        await emissions;
        verify(behavior.call(query)).called(2);
        await observing.close();
      },
    );

    test('_notifyWatchers removes closed observers', () async {
      final query = buildQuery();
      storage.addClosedObserverFor(query);
      expect(storage.observerCount('users'), 1);

      await storage.insert('users', {
        'id': 'closed',
        'username': 'closed',
        'age': 1,
        '_sync_status': SyncStatus.ok.index,
        '_sync_operation': SyncOperation.insert.index,
        '_sync_created_at': DateTime.now().millisecondsSinceEpoch,
      }, 'id');

      expect(storage.observerCount('users'), 0);
    });

    test('query returns empty when whereIn is empty', () async {
      await insertRow({'id': '1', 'username': 'alice', 'age': 20});

      final results = await storage.query(
        buildQuery(
          filters: [QueryFilter(field: 'username', whereIn: const [])],
        ),
      );

      expect(results, isEmpty);
    });

    test('query honors isNull true/false', () async {
      await insertRow({
        'id': '1',
        'username': 'alice',
        'age': 20,
        'nickname': null,
      });
      await insertRow({
        'id': '2',
        'username': 'bob',
        'age': 21,
        'nickname': 'b',
      });

      final onlyNull = await storage.query(
        buildQuery(
          filters: [const QueryFilter(field: 'nickname', isNull: true)],
        ),
      );
      expect(onlyNull.map((e) => e['id']), ['1']);

      final notNull = await storage.query(
        buildQuery(
          filters: [const QueryFilter(field: 'nickname', isNull: false)],
        ),
      );
      expect(notNull.map((e) => e['id']), ['2']);
    });

    test('query handles whereNotIn', () async {
      await insertRow({'id': '1', 'username': 'alice', 'age': 20});
      await insertRow({'id': '2', 'username': 'bob', 'age': 21});
      await insertRow({'id': '3', 'username': 'carol', 'age': 22});

      final results = await storage.query(
        buildQuery(
          filters: [
            QueryFilter(field: 'username', whereNotIn: ['alice', 'carol']),
          ],
        ),
      );

      expect(results.map((e) => e['id']), ['2']);
    });

    test('query supports comparison operators', () async {
      await insertRow({'id': '1', 'username': 'a', 'age': 10});
      await insertRow({'id': '2', 'username': 'b', 'age': 15});
      await insertRow({'id': '3', 'username': 'c', 'age': 20});

      final notEqual = await storage.query(
        buildQuery(filters: [QueryFilter(field: 'age', isNotEqualTo: 15)]),
      );
      expect(notEqual.map((e) => e['id']), containsAll(['1', '3']));
      expect(notEqual.map((e) => e['id']), isNot(contains('2')));

      final lessThan = await storage.query(
        buildQuery(filters: [QueryFilter(field: 'age', isLessThan: 15)]),
      );
      expect(lessThan.map((e) => e['id']), ['1']);

      final lessThanOrEqual = await storage.query(
        buildQuery(
          filters: [QueryFilter(field: 'age', isLessThanOrEqualTo: 15)],
        ),
      );
      expect(lessThanOrEqual.map((e) => e['id']), containsAll(['1', '2']));

      final greaterThanOrEqual = await storage.query(
        buildQuery(
          filters: [QueryFilter(field: 'age', isGreaterThanOrEqualTo: 15)],
        ),
      );
      expect(greaterThanOrEqual.map((e) => e['id']), containsAll(['2', '3']));
    });

    test('query supports whereIn', () async {
      await insertRow({'id': '1', 'username': 'alice', 'age': 20});
      await insertRow({'id': '2', 'username': 'bob', 'age': 21});
      await insertRow({'id': '3', 'username': 'carol', 'age': 22});

      final results = await storage.query(
        buildQuery(
          filters: [
            QueryFilter(field: 'username', whereIn: ['alice', 'carol']),
          ],
        ),
      );

      expect(results.map((e) => e['id']), containsAll(['1', '3']));
    });

    test('query applies offset when limit is null', () async {
      await insertRow({'id': '1', 'username': 'alice', 'age': 20});
      await insertRow({'id': '2', 'username': 'bob', 'age': 21});
      await insertRow({'id': '3', 'username': 'carol', 'age': 22});

      final results = await storage.query(
        buildQuery(sorts: [const QuerySort(field: 'age')], offset: 1),
      );

      expect(results.map((e) => e['id']), ['2', '3']);
    });

    test('insert normalizes nested map values via JSON encoding', () async {
      final joined = DateTime.utc(2024, 1, 1);
      await insertRow({
        'id': 'map1',
        'username': 'mapper',
        'age': 30,
        'meta': {
          'joined': joined,
          'prefs': {'theme': 'dark'},
        },
      });

      final stored = await storage.getById('users', 'map1');
      expect(stored?['meta'], {
        'joined': joined.toIso8601String(),
        'prefs': {'theme': 'dark'},
      });
    });

    test('ensureSchema throws for invalid field identifier', () async {
      expect(
        () => storage.ensureSchema('users', {
          'a-b': LocalFieldType.text,
        }, idFieldName: 'id'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('ensureSchema throws for reserved field names', () async {
      expect(
        () => storage.ensureSchema('users', {
          'id': LocalFieldType.text,
        }, idFieldName: 'id'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('query falls back to JSON path for non-schema field', () async {
      await insertRow({'id': '1', 'username': 'alice', 'age': 20, 'city': 'X'});
      await insertRow({'id': '2', 'username': 'bob', 'age': 21, 'city': 'Y'});

      final results = await storage.query(
        buildQuery(
          filters: [QueryFilter(field: 'city', isEqualTo: 'Y')],
        ),
      );

      expect(results.single['id'], '2');
    });
  });

  group('SqliteLocalFirstStorage error handling (mockito)', () {
    late MockDatabaseFactory mockDbFactory;
    late MockDatabase mockDb;
    late SqliteLocalFirstStorage storage;

    LocalFirstQuery<DummyModel> buildQuery({
      List<QueryFilter> filters = const [],
    }) {
      return LocalFirstQuery<DummyModel>(
        repositoryName: 'users',
        delegate: storage,
        repository: LocalFirstRepository.create<DummyModel>(
          name: 'users',
          getId: (m) => m.id,
          toJson: (m) => m.toJson(),
          fromJson: DummyModel.fromJson,
          onConflict: (l, r) => l,
          schema: schema,
        ),
        filters: filters,
      );
    }

    setUp(() async {
      mockDbFactory = MockDatabaseFactory();
      mockDb = MockDatabase();

      when(
        mockDbFactory.openDatabase('path', options: anyNamed('options')),
      ).thenAnswer((invocation) async {
        final options =
            invocation.namedArguments[#options] as OpenDatabaseOptions?;
        final ver = options?.version ?? 1;
        if (options?.onCreate != null) {
          await options!.onCreate!(mockDb, ver);
        }
        return mockDb;
      });

      when(mockDb.execute(any)).thenAnswer((_) async {});

      // Stubs for `query` are needed for `ensureSchema` to work with a mock DB.
      when(
        mockDb.query(
          any,
          where: anyNamed('where'),
          whereArgs: anyNamed('whereArgs'),
        ),
      ).thenAnswer((_) async => []);
      when(mockDb.query(any)).thenAnswer((_) async => []);

      when(
        mockDb.insert(
          any,
          any,
          conflictAlgorithm: anyNamed('conflictAlgorithm'),
        ),
      ).thenAnswer((_) async => 1);
      when(
        mockDb.delete(
          any,
          where: anyNamed('where'),
          whereArgs: anyNamed('whereArgs'),
        ),
      ).thenAnswer((_) async => 1);

      storage = SqliteLocalFirstStorage(
        dbFactory: mockDbFactory,
        databasePath: 'path',
      );

      await storage.open(namespace: 'err_ns');
      await storage.initialize();
      await storage.ensureSchema('users', schema, idFieldName: 'id');
    });

    test('watchQuery emits error when query throws', () async {
      when(mockDb.rawQuery(any, any)).thenThrow(StateError('boom'));

      final stream = storage.watchQuery(buildQuery());
      await expectLater(stream, emitsError(isA<StateError>()));
    });

    test('initialize uses injected databaseFactory with options', () async {
      final captured =
          verify(
                mockDbFactory.openDatabase(
                  'path',
                  options: captureAnyNamed('options'),
                ),
              ).captured.single
              as OpenDatabaseOptions;

      expect(captured.version, 1);
      expect(captured.onCreate, isNotNull);
    });

    test('initialize uses default databaseFactory when not provided', () async {
      DatabaseFactory? previousFactory;
      try {
        previousFactory = databaseFactory;
      } catch (_) {
        previousFactory = null;
      }

      databaseFactory = databaseFactoryFfi;

      final store = SqliteLocalFirstStorage(
        databasePath: inMemoryDatabasePath,
      );

      await store.open(namespace: 'default_factory');
      await store.initialize();
      await store.setMeta('df_key', 'df_value');
      expect(await store.getMeta('df_key'), 'df_value');
      await store.close();

      if (previousFactory != null) {
        databaseFactory = previousFactory;
      }
    });

    test('_notifyWatchers emits error to stream when query throws', () async {
      var callCount = 0;
      when(mockDb.rawQuery(any, any)).thenAnswer((_) {
        callCount += 1;
        if (callCount == 1) {
          return Future.value(<Map<String, Object?>>[]);
        }
        throw StateError('boom');
      });

      final stream = storage.watchQuery(buildQuery());
      final firstEmission = Completer<void>();
      final errorCapture = Completer<Object?>();
      final sub = stream.listen(
        (_) => firstEmission.complete(),
        onError: (error, _) => errorCapture.complete(error),
      );
      await firstEmission.future;

      await storage.insert('users', {
        'id': 'err',
        'username': 'err',
        'age': 1,
        '_sync_status': SyncStatus.ok.index,
        '_sync_operation': SyncOperation.insert.index,
        '_sync_created_at': DateTime.now().millisecondsSinceEpoch,
      }, 'id');

      expect(await errorCapture.future, isA<StateError>());
      await sub.cancel();
    });

    test(
      '_notifyWatchers surfaces query exception from delegate query',
      () async {
        final behavior = MockQueryBehavior();
        final failingQuery = buildQuery();
        when(behavior.call(failingQuery)).thenThrow(StateError('boom'));

        final throwing = MockableSqliteLocalFirstStorage(
          dbFactory: databaseFactoryFfi,
          databasePath: inMemoryDatabasePath,
          behavior: behavior,
        );
        await throwing.open(namespace: 'err_notify');
        await throwing.initialize();
        await throwing.ensureSchema('users', schema, idFieldName: 'id');

        final stream = throwing.watchQuery(failingQuery);
        await stream.first.catchError(
          (_) => <Map<String, dynamic>>[],
          test: (_) => true,
        );

        final expectation = expectLater(stream, emitsError(isA<StateError>()));

        await throwing.insert('users', {
          'id': 'err2',
          'username': 'err2',
          'age': 1,
          '_sync_status': SyncStatus.ok.index,
          '_sync_operation': SyncOperation.insert.index,
          '_sync_created_at': DateTime.now().millisecondsSinceEpoch,
        }, 'id');

        await expectation;
        await throwing.close();
      },
    );

    test('insert encodes numeric boolean for boolean field', () async {
      final captured = <Map<String, Object?>>[];
      when(
        mockDb.insert(
          any,
          any,
          conflictAlgorithm: anyNamed('conflictAlgorithm'),
        ),
      ).thenAnswer((invocation) async {
        captured.add(
          Map<String, Object?>.from(invocation.positionalArguments[1] as Map),
        );
        return 1;
      });

      Future<void> insertWithValue(String id, Object value) async {
        await storage.insert('users', {
          'id': id,
          'username': 'user$id',
          'age': 1,
          'verified': value, // numeric boolean
          '_sync_status': SyncStatus.ok.index,
          '_sync_operation': SyncOperation.insert.index,
          '_sync_created_at': DateTime.now().millisecondsSinceEpoch,
        }, 'id');
      }

      await insertWithValue('bool_num_0', 0);
      await insertWithValue('bool_num_1', 1);
      await insertWithValue('bool_num_-1', -1);

      expect(captured, hasLength(3));
      expect(captured[0]['verified'], 0);
      expect(captured[1]['verified'], 1);
      expect(captured[2]['verified'], -1);
    });

    test('insert throws when id is not a string', () async {
      expect(
        () => storage.insert('users', {
          'id': 123, // invalid type
          'username': 'bad',
          'age': 1,
          '_sync_status': SyncStatus.ok.index,
          '_sync_operation': SyncOperation.insert.index,
          '_sync_created_at': DateTime.now().millisecondsSinceEpoch,
        }, 'id'),
        throwsArgumentError,
      );
    });

    test('methods throw when not initialized', () {
      final uninit = SqliteLocalFirstStorage(
        databasePath: inMemoryDatabasePath,
        dbFactory: databaseFactoryFfi,
      );

      expect(() => uninit.getAll('users'), throwsStateError);
      expect(() => uninit.getById('users', 'id'), throwsStateError);
      expect(() => uninit.insert('users', {}, 'id'), throwsStateError);
      expect(() => uninit.update('users', 'id', {}), throwsStateError);
      expect(() => uninit.delete('users', 'id'), throwsStateError);
      expect(() => uninit.deleteAll('users'), throwsStateError);
      expect(() => uninit.setMeta('k', 'v'), throwsStateError);
      expect(() => uninit.getMeta('k'), throwsStateError);
      expect(() => uninit.clearAllData(), throwsStateError);
    });
  });
}
