import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sqlite_local_storage_test.mocks.dart';

@GenerateMocks([QueryBehavior, DatabaseFactory, Database])
class DummyModel with LocalFirstModel {
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

  @override
  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'age': age};
}

abstract class QueryBehavior {
  Future<List<Map<String, dynamic>>> call(
    LocalFirstQuery<LocalFirstModel> query,
  );
}

class MockableSqliteLocalFirstStorage extends SqliteLocalFirstStorage {
  MockableSqliteLocalFirstStorage({
    required super.dbFactory,
    required super.databasePath,
    required super.namespace,
    required this.behavior,
  });

  final QueryBehavior behavior;

  @override
  Future<List<Map<String, dynamic>>> query(
    LocalFirstQuery<LocalFirstModel> query,
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
        fromJson: DummyModel.fromJson,
        repository: LocalFirstRepository<DummyModel>.create(
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
        namespace: 'test_ns',
      );
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

    test('watchQuery surfaces query errors via addError', () async {
      final behavior = MockQueryBehavior();
      final failingQuery = buildQuery();
      when(behavior.call(failingQuery)).thenThrow(StateError('boom'));

      final throwing = MockableSqliteLocalFirstStorage(
        dbFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
        namespace: 'error_ns',
        behavior: behavior,
      );

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
        namespace: 'toggle_ns',
        behavior: behavior,
      );
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
        fromJson: DummyModel.fromJson,
        repository: LocalFirstRepository<DummyModel>.create(
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
      when(mockDb.execute(any, anyNamed('arguments'))).thenAnswer((_) async {});
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
        namespace: 'err_ns',
      );

      await storage.initialize();
      await storage.ensureSchema('users', schema, idFieldName: 'id');
    });

    test('watchQuery emits error when query throws', () async {
      when(mockDb.rawQuery(any, any)).thenThrow(StateError('boom'));

      final stream = storage.watchQuery(buildQuery());
      await expectLater(stream, emitsError(isA<StateError>()));
    });

    test('_notifyWatchers emits error to stream when query throws', () async {
      when(mockDb.rawQuery(any, any)).thenThrow(StateError('boom'));

      final stream = storage.watchQuery(buildQuery());
      // Consume initial emission/error.
      await stream.first.catchError(
        (_) => <Map<String, dynamic>>[],
        test: (_) => true,
      );

      final expectation = expectLater(stream, emitsError(isA<StateError>()));

      await storage.insert('users', {
        'id': 'err',
        'username': 'err',
        'age': 1,
        '_sync_status': SyncStatus.ok.index,
        '_sync_operation': SyncOperation.insert.index,
        '_sync_created_at': DateTime.now().millisecondsSinceEpoch,
      }, 'id');

      await expectation;
    });
  });
}
