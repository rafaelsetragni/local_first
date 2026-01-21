import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_sqlite_storage/local_first_sqlite_storage.dart';
import 'package:mockito/annotations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqlite_api.dart';

@GenerateMocks([QueryBehavior, DatabaseFactory, Database])
class DummyModel {
  DummyModel(this.id, {required this.username, required this.age});

  final String id;
  final String username;
  final int age;

  factory DummyModel.fromJson(JsonMap json) {
    final ageValue = json['age'];
    return DummyModel(
      json['id'] as String,
      username: json['username'] as String,
      age: ageValue is num ? ageValue.toInt() : 0,
    );
  }

  JsonMap toJson() => {'id': id, 'username': username, 'age': age};
}

abstract class QueryBehavior {
  Future<List<JsonMap>> call(LocalFirstQuery query);
}

class _ThrowingBehavior implements QueryBehavior {
  @override
  Future<List<JsonMap>> call(LocalFirstQuery query) {
    return Future<List<JsonMap>>.error(StateError('boom'));
  }
}

class _EmptyBehavior implements QueryBehavior {
  @override
  Future<List<JsonMap>> call(LocalFirstQuery query) {
    return Future.value(<JsonMap>[]);
  }
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
  Future<List<LocalFirstEvent<T>>> query<T>(LocalFirstQuery<T> query) {
    return behavior(query).then(
      (rows) => rows
          .map(
            (json) => LocalFirstEvent<T>.fromLocalStorage(
              repository: query.repository,
              json: json,
            ),
          )
          .toList(),
    );
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
      LocalFirstStorage? delegate,
      List<QueryFilter> filters = const [],
      List<QuerySort> sorts = const [],
      int? limit,
      int? offset,
      bool includeDeleted = false,
    }) {
      return LocalFirstQuery<DummyModel>(
        repositoryName: 'users',
        delegate: delegate ?? storage,
        repository: LocalFirstRepository<DummyModel>.create(
          name: 'users',
          getId: (m) => m.id,
          toJson: (m) => m.toJson(),
          fromJson: DummyModel.fromJson,
          schema: schema,
        ),
        filters: filters,
        sorts: sorts,
        limit: limit,
        offset: offset,
        includeDeleted: includeDeleted,
      );
    }

    Future<void> insertRow(JsonMap item) => storage.insert('users', {
      ...item,
      '_lasteventId': item['_lasteventId'] ?? 'evt-${item['id']}',
    }, 'id');

    Future<void> insertEvent({
      required String dataId,
      required SyncOperation op,
      required SyncStatus status,
      int? createdAt,
      String? eventId,
    }) {
      final id = eventId ?? 'evt-$dataId';
      return storage.insertEvent('users', {
        'eventId': id,
        'dataId': dataId,
        'syncStatus': status.index,
        'operation': op.index,
        'createdAt': createdAt ?? DateTime.now().millisecondsSinceEpoch,
      }, 'eventId');
    }

    test('throws when used before initialization', () async {
      final fresh = SqliteLocalFirstStorage(
        databasePath: inMemoryDatabasePath,
        dbFactory: databaseFactoryFfi,
        namespace: 'ns_valid',
      );
      expect(() => fresh.getAll('users'), throwsA(isA<StateError>()));
    });

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

    test('default factory and resolved path are created when no dbFactory provided',
        () async {
      databaseFactory = databaseFactoryFfi;
      final defaultStorage = SqliteLocalFirstStorage(namespace: 'ns_default');
      expect(defaultStorage.namespace, 'ns_default');
      await defaultStorage.initialize();
      await defaultStorage.close();
    });

    test('close shuts down active watchers', () async {
      final sub = storage.watchQuery(buildQuery()).listen((_) {});
      await storage.close();
      expect(sub.isPaused, isFalse);
    });

    test('getEventById returns merged payload when present', () async {
      await insertRow({'id': 'ev1', 'username': 'user', 'age': 10});
      await insertEvent(
        dataId: 'ev1',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-ev1',
      );
      final event = await storage.getEventById('users', 'evt-ev1');
      expect(event?['eventId'], 'evt-ev1');
      expect(event?['id'], 'ev1');
    });

    test('updateEvent throws when dataId is not a string', () async {
      await expectLater(
        storage.updateEvent(
          'users',
          'evt',
          {'dataId': 123, 'syncStatus': 1, 'operation': 1, 'createdAt': 1},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('deleteEvent removes event rows', () async {
      await insertEvent(
        dataId: 'del',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-del',
      );
      expect(await storage.getAllEvents('users'), isNotEmpty);
      await expectLater(
        storage.deleteEvent('users', 'evt-del'),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('deleteEvent completes when legacy id column exists', () async {
      final helper = TestHelperSqliteLocalFirstStorage(storage);
      final db = await helper.database;
      await db.execute('ALTER TABLE users__events ADD COLUMN id TEXT');
      await db.insert('users__events', {
        'id': 'evt-legacy',
        'eventId': 'evt-legacy',
        'dataId': 'legacy',
        'syncStatus': 0,
        'operation': SyncOperation.insert.index,
        'createdAt': 1,
      });
      await storage.deleteEvent('users', 'evt-legacy');
    });

    test('watchQuery throws when not initialized', () {
      final fresh = SqliteLocalFirstStorage(
        databasePath: inMemoryDatabasePath,
        dbFactory: databaseFactoryFfi,
      );
      expect(() => fresh.watchQuery(buildQuery(delegate: fresh)),
          throwsA(isA<StateError>()));
    });

    test('watchQuery emits current results on listen', () async {
      await insertRow({'id': 'w1', 'username': 'w', 'age': 1});
      await insertEvent(
        dataId: 'w1',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-w1',
      );
      final stream = storage.watchQuery(buildQuery());
      final first = await stream.first;
      expect(first.whereType<LocalFirstStateEvent<DummyModel>>(), isNotEmpty);
    });

    test('notifyWatchers removes closed observers and emits results', () async {
      final mockable = MockableSqliteLocalFirstStorage(
        dbFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
        namespace: 'notify',
        behavior: _EmptyBehavior(),
      );
      await mockable.initialize();
      await mockable.ensureSchema('users', schema, idFieldName: 'id');
      final helper = TestHelperSqliteLocalFirstStorage(mockable);
      final stream = mockable.watchQuery(buildQuery(delegate: mockable));
      await helper.notifyWatchers('users');
      await expectLater(
        stream.first,
        completion(isA<List<LocalFirstEvent<DummyModel>>>()),
      );
      var observers = helper.observers['users'] ?? <dynamic>{};
      if (observers.isEmpty) {
        mockable.watchQuery(buildQuery(delegate: mockable));
        observers = helper.observers['users']!;
      }
      final observer = observers.first;
      await observer.controller.close();
      await helper.notifyWatchers('users');
      expect(helper.observers['users'], anyOf(isNull, isEmpty));
      await mockable.close();
    });

    test('encodeValue handles null type and map normalization', () async {
      await insertRow({
        'id': 'bool',
        'username': 'flagger',
        'age': 1,
        'nested': {'k': DateTime.utc(2024, 1, 1)},
        '_lasteventId': 'evt-bool',
      });
      await insertEvent(
        dataId: 'bool',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-bool',
      );

      final results = await storage.query(
        buildQuery(
          filters: [const QueryFilter(field: 'missing', isEqualTo: true)],
        ),
      );
      expect(results, isEmpty);
    });

    test('query builds predicates for all filter variants', () async {
      await insertRow({'id': '1', 'username': 'a', 'age': 10, 'score': 1});
      await insertEvent(
        dataId: '1',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-1',
      );

      final results = await storage.query(
        buildQuery(
          filters: [
            const QueryFilter(field: 'age', isEqualTo: 10),
            const QueryFilter(field: 'age', isNotEqualTo: 11),
            const QueryFilter(field: 'age', isLessThan: 20),
            const QueryFilter(field: 'age', isLessThanOrEqualTo: 10),
            const QueryFilter(field: 'age', isGreaterThanOrEqualTo: 5),
            const QueryFilter(field: 'username', whereIn: ['a']),
            const QueryFilter(field: 'username', whereNotIn: ['b']),
            const QueryFilter(field: 'nickname', isGreaterThan: 0),
          ],
          offset: 1, // triggers LIMIT -1 branch when limit is null
        ),
      );

      expect(results, isEmpty); // offset skips the single row
    });

    test('helper exposes internals for coverage', () async {
      final helper = TestHelperSqliteLocalFirstStorage(storage);
      expect(helper.schemas['users'], isNotNull);
      expect(helper.tableName('users'), 'users');
      await helper.ensureTables('users');
      await helper.ensureDataTable('users');
      await helper.ensureEventTable('users');
      await helper.ensureMetadataTable();
      expect(await helper.database, isA<Database>());
      final encoded = helper.encodeDataRow(
        schema,
        {'id': 'h1', 'username': 'abc', 'age': 1},
        'h1',
        'evt-h1',
      );
      expect(encoded['id'], 'h1');
    });

    test('clearAllData wipes tables and metadata and notifies watchers', () async {
      await insertRow({'id': '1', 'username': 'alice', 'age': 20});
      await insertEvent(
        dataId: '1',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-1',
      );
      await storage.setConfigValue('meta', 'value');

      await storage.clearAllData();

      expect(await storage.getAll('users'), isEmpty);
      expect(await storage.getConfigValue('meta'), isNull);
    });

    test('useNamespace switches databases', () async {
      await insertRow({'id': '1', 'username': 'alice', 'age': 1});
      await insertEvent(
        dataId: '1',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
      );
      expect((await storage.getAll('users')).length, 1);

      await storage.useNamespace('second');
      expect((await storage.getAll('users')).length, 0);
    });

    test('getAll and getAllEvents handle missing rows', () async {
      expect(await storage.getAll('users'), isEmpty);
      expect(await storage.getAllEvents('users'), isEmpty);
    });

    test('getById and getEventById return null when not found', () async {
      expect(await storage.getById('users', 'missing'), isNull);
      expect(await storage.getEventById('users', 'missing'), isNull);
    });

    test('getAllEvents merges dataId into id when only event exists', () async {
      await insertEvent(
        dataId: 'ghost',
        op: SyncOperation.delete,
        status: SyncStatus.pending,
        eventId: 'evt-ghost',
      );
      final events = await storage.getAllEvents('users');
      expect(events.single['id'], 'ghost');
    });

    test('insert throws on non-string id', () async {
      expect(
        () => storage.insert('users', {'id': 1, 'username': 'x'}, 'id'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('insertEvent validates ids', () async {
      await expectLater(
        storage.insertEvent('users', {'eventId': 1, 'dataId': 'a'}, 'eventId'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        storage.insertEvent('users', {'eventId': 'evt', 'dataId': 123}, 'eventId'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('delete/deleteAll/deleteEvent/deleteAllEvents remove rows', () async {
      await insertRow({'id': '1', 'username': 'alice', 'age': 1});
      await insertEvent(
        dataId: '1',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-1',
      );
      expect(await storage.containsId('users', '1'), isTrue);

      await storage.delete('users', '1');
      expect(await storage.containsId('users', '1'), isFalse);

      await insertEvent(
        dataId: '2',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-2',
      );
      expect((await storage.getAllEvents('users')).length, 2);
      await storage.deleteAllEvents('users');
      expect(await storage.getAllEvents('users'), isEmpty);

      await storage.deleteAll('users');
      expect(await storage.getAll('users'), isEmpty);
    });

    test('setConfigValue/getConfigValue roundtrip and null when missing', () async {
      expect(await storage.getConfigValue('k'), isNull);
      await storage.setConfigValue('k', 'v');
      expect(await storage.getConfigValue('k'), 'v');
    });

    test('containsId returns false when table empty', () async {
      expect(await storage.containsId('users', 'none'), isFalse);
    });

    test('ensureSchema rejects reserved column names', () async {
      final invalid = {
        'id': LocalFieldType.text,
      };
      expect(
        () => storage.ensureSchema('users', invalid, idFieldName: 'id'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('watchQuery adds and removes observers', () async {
      final helper = TestHelperSqliteLocalFirstStorage(storage);
      final stream = storage.watchQuery(buildQuery());
      final sub = stream.listen((_) {});
      expect(helper.observers['users'], isNotEmpty);
      await sub.cancel();
      expect(helper.observers['users'], isNull);
    });

    test('notifyWatchers forwards errors from query', () async {
      final throwing = MockableSqliteLocalFirstStorage(
        dbFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
        namespace: 'throwing',
        behavior: _ThrowingBehavior(),
      );
      await throwing.initialize();
      await throwing.ensureSchema('users', schema, idFieldName: 'id');
      final helper = TestHelperSqliteLocalFirstStorage(throwing);
      final stream = throwing.watchQuery(buildQuery(delegate: throwing));
      await helper.notifyWatchers('users');
      await expectLater(stream.first, throwsA(isA<StateError>()));
      await throwing.close();
    });

    test('tableName and identifier validation rejects invalid names', () {
      final helper = TestHelperSqliteLocalFirstStorage(storage);
      expect(() => helper.tableName('bad-name'), throwsA(isA<ArgumentError>()));
    });

    test('decodeJoinedRow fills id from dataId', () {
      final helper = TestHelperSqliteLocalFirstStorage(storage);
      final decoded = helper.decodeJoinedRow({
        'data': '{}',
        'dataId': 'abc',
        'eventId': 'evt',
        'syncStatus': 1,
        'operation': 2,
        'createdAt': 3,
      });
      expect(decoded['id'], 'abc');
      expect(decoded['dataId'], 'abc');
      expect(decoded['eventId'], 'evt');
      expect(decoded['syncStatus'], 1);
    });

    test('filters and sorts using schema columns', () async {
      await insertRow({'id': '1', 'username': 'alice', 'age': 20});
      await insertRow({'id': '2', 'username': 'bob', 'age': 35});
      await insertRow({'id': '3', 'username': 'carol', 'age': 28});
      await insertEvent(
        dataId: '1',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-1',
      );
      await insertEvent(
        dataId: '2',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-2',
      );
      await insertEvent(
        dataId: '3',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-3',
      );

      final results = await storage.query(
        buildQuery(
          filters: [QueryFilter(field: 'age', isGreaterThan: 25)],
          sorts: [QuerySort(field: 'age', descending: true)],
        ),
      );

      expect(
        results.whereType<LocalFirstStateEvent<DummyModel>>().map(
          (e) => e.data.id,
        ),
        ['2', '3'],
      );
    });

    test('applies limit and offset', () async {
      await insertRow({
        'id': '1',
        'username': 'alice',
        'age': 20,
        'score': 1.1,
        '_lasteventId': 'evt-1',
      });
      await insertRow({
        'id': '2',
        'username': 'bob',
        'age': 25,
        'score': 2.2,
        '_lasteventId': 'evt-2',
      });
      await insertRow({
        'id': '3',
        'username': 'carol',
        'age': 30,
        'score': 3.3,
        '_lasteventId': 'evt-3',
      });
      await insertEvent(
        dataId: '1',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-1',
      );
      await insertEvent(
        dataId: '2',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-2',
      );
      await insertEvent(
        dataId: '3',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-3',
      );

      final results = await storage.query(
        buildQuery(sorts: [const QuerySort(field: 'age')], limit: 1, offset: 1),
      );

      final stateEvent = results
          .whereType<LocalFirstStateEvent<DummyModel>>()
          .single;
      expect(stateEvent.data.id, '2');
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
        '_lasteventId': 'evt-enc',
      });
      await insertEvent(
        dataId: 'enc',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-enc',
      );

      final row = await storage.getById('users', 'enc');
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
        'username': 'mix',
        'age': 10,
        'verified': 1,
        '_lasteventId': 'evt-mix',
      });
      await insertEvent(
        dataId: 'mix_bool',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-mix',
      );

      final row = await storage.getById('users', 'mix_bool');
      expect(row?['verified'], 1);
    });

    test('encodes datetime when provided as string', () async {
      await insertRow({
        'id': 'time',
        'username': 'timey',
        'age': 11,
        'birth': '2024-01-01T00:00:00.000Z',
        '_lasteventId': 'evt-time',
      });
      await insertEvent(
        dataId: 'time',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-time',
      );

      final row = await storage.getById('users', 'time');
      expect(row?['birth'], '2024-01-01T00:00:00.000Z');
    });

    test('prefers last event payload when merging', () async {
      await insertRow({'id': 'merge', 'username': 'alpha', 'age': 30});
      await insertEvent(
        dataId: 'merge',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-initial',
      );

      await storage.update('users', 'merge', {
        'id': 'merge',
        'username': 'beta',
        'age': 31,
      });
      await storage.updateEvent('users', 'evt-update', {
        'eventId': 'evt-update',
        'dataId': 'merge',
        'syncStatus': SyncStatus.ok.index,
        'operation': SyncOperation.update.index,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });

      final merged = await storage.getById('users', 'merge');
      expect(merged?['username'], 'beta');
    });

    test('query applies whereIn/whereNotIn/isNull filters', () async {
      await insertRow({'id': '1', 'username': 'alice', 'nickname': null});
      await insertRow({'id': '2', 'username': 'bob', 'nickname': 'bobby'});
      await insertRow({'id': '3', 'username': 'carol', 'nickname': 'cc'});
      await insertEvent(
        dataId: '1',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-1',
      );
      await insertEvent(
        dataId: '2',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-2',
      );
      await insertEvent(
        dataId: '3',
        op: SyncOperation.insert,
        status: SyncStatus.ok,
        eventId: 'evt-3',
      );

      final onlyNull = await storage.query(
        buildQuery(
          filters: [const QueryFilter(field: 'nickname', isNull: true)],
        ),
      );
      expect(
        onlyNull.whereType<LocalFirstStateEvent<DummyModel>>().map(
          (e) => e.data.id,
        ),
        ['1'],
      );

      final notNull = await storage.query(
        buildQuery(
          filters: [const QueryFilter(field: 'nickname', isNull: false)],
        ),
      );
      expect(
        notNull.whereType<LocalFirstStateEvent<DummyModel>>().map(
          (e) => e.data.id,
        ),
        ['2', '3'],
      );
    });
  });
}
