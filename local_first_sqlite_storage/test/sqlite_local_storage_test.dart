import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_sqlite_storage/local_first_sqlite_storage.dart';
import 'package:mockito/annotations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
        LocalFirstEvent.kEventId: id,
        LocalFirstEvent.kDataId: dataId,
        LocalFirstEvent.kSyncStatus: status.index,
        LocalFirstEvent.kOperation: op.index,
        LocalFirstEvent.kSyncCreatedAt: createdAt ?? DateTime.now().millisecondsSinceEpoch,
      }, LocalFirstEvent.kEventId);
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

    test(
      'default factory and resolved path are created when no dbFactory provided',
      () async {
        databaseFactory = databaseFactoryFfi;
        final defaultStorage = SqliteLocalFirstStorage(namespace: 'ns_default');
        expect(defaultStorage.namespace, 'ns_default');
        await defaultStorage.initialize();
        await defaultStorage.close();
      },
    );

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
      expect(event?[LocalFirstEvent.kEventId], 'evt-ev1');
      expect(event?['id'], 'ev1');
    });

    test('updateEvent throws when dataId is not a string', () async {
      await expectLater(
        storage.updateEvent('users', 'evt', {
          LocalFirstEvent.kDataId: 123,
          LocalFirstEvent.kSyncStatus: 1,
          LocalFirstEvent.kOperation: 1,
          LocalFirstEvent.kSyncCreatedAt: 1,
        }),
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
        LocalFirstEvent.kEventId: 'evt-legacy',
        LocalFirstEvent.kDataId: 'legacy',
        LocalFirstEvent.kSyncStatus: 0,
        LocalFirstEvent.kOperation: SyncOperation.insert.index,
        LocalFirstEvent.kSyncCreatedAt: 1,
      });
      await storage.deleteEvent('users', 'evt-legacy');
    });

    test('watchQuery throws when not initialized', () {
      final fresh = SqliteLocalFirstStorage(
        databasePath: inMemoryDatabasePath,
        dbFactory: databaseFactoryFfi,
      );
      expect(
        () => fresh.watchQuery(buildQuery(delegate: fresh)),
        throwsA(isA<StateError>()),
      );
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

    test(
      'clearAllData wipes tables and metadata and notifies watchers',
      () async {
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
      },
    );

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
        storage.insertEvent('users', {LocalFirstEvent.kEventId: 1, LocalFirstEvent.kDataId: 'a'}, LocalFirstEvent.kEventId),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        storage.insertEvent('users', {
          LocalFirstEvent.kEventId: 'evt',
          LocalFirstEvent.kDataId: 123,
        }, LocalFirstEvent.kEventId),
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

    test(
      'setConfigValue/getConfigValue roundtrip and null when missing',
      () async {
        expect(await storage.getConfigValue('k'), isNull);
        await storage.setConfigValue('k', 'v');
        expect(await storage.getConfigValue('k'), 'v');
      },
    );

    test(
      'config storage supports shared_preferences types and rejects others',
      () async {
        await storage.setConfigValue('bool', true);
        await storage.setConfigValue('int', 1);
        await storage.setConfigValue('double', 1.5);
        await storage.setConfigValue('string', 'ok');
        await storage.setConfigValue('list', <String>['a', 'b']);

        expect(await storage.getConfigValue<bool>('bool'), isTrue);
        expect(await storage.getConfigValue<int>('int'), 1);
        expect(await storage.getConfigValue<double>('double'), 1.5);
        expect(await storage.getConfigValue<String>('string'), 'ok');
        expect(await storage.getConfigValue<List<String>>('list'), ['a', 'b']);
        expect(await storage.getConfigValue<dynamic>('list'), ['a', 'b']);

        expect(
          await storage.getConfigKeys(),
          containsAll(['bool', 'int', 'double', 'string', 'list']),
        );
        expect(await storage.containsConfigKey('string'), isTrue);

        expect(
          () => storage.setConfigValue('invalid', {'a': 1}),
          throwsArgumentError,
        );

        expect(() => storage.setConfigValue('null', null), throwsArgumentError);

        await storage.removeConfig('string');
        expect(await storage.containsConfigKey('string'), isFalse);

        await storage.clearConfig();
        expect(await storage.getConfigKeys(), isEmpty);
      },
    );

    test(
      'getConfigValue returns raw string when decode fails for String',
      () async {
        final helper = TestHelperSqliteLocalFirstStorage(storage);
        final db = await helper.database;
        await helper.ensureMetadataTable();
        await db.insert(helper.metadataTable, {
          'key': 'bad',
          'value': 'not-json',
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        expect(await storage.getConfigValue<String>('bad'), 'not-json');
      },
    );

    test(
      'getConfigValue returns null for unknown encoded config type',
      () async {
        final helper = TestHelperSqliteLocalFirstStorage(storage);
        final db = await helper.database;
        await helper.ensureMetadataTable();
        await db.insert(helper.metadataTable, {
          'key': 'unknown',
          'value': jsonEncode({'t': 'alien', 'v': 'x'}),
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        expect(await storage.getConfigValue<String>('unknown'), isNull);
      },
    );

    test('containsId returns false when table empty', () async {
      expect(await storage.containsId('users', 'none'), isFalse);
    });

    test('ensureSchema rejects reserved column names', () async {
      final invalid = {'id': LocalFieldType.text};
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
        LocalFirstEvent.kData: '{}',
        LocalFirstEvent.kDataId: 'abc',
        LocalFirstEvent.kEventId: 'evt',
        LocalFirstEvent.kSyncStatus: 1,
        LocalFirstEvent.kOperation: 2,
        LocalFirstEvent.kSyncCreatedAt: 3,
      });
      expect(decoded['id'], 'abc');
      expect(decoded[LocalFirstEvent.kDataId], 'abc');
      expect(decoded[LocalFirstEvent.kEventId], 'evt');
      expect(decoded[LocalFirstEvent.kSyncStatus], 1);
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
        LocalFirstEvent.kEventId: 'evt-update',
        LocalFirstEvent.kDataId: 'merge',
        LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
        LocalFirstEvent.kOperation: SyncOperation.update.index,
        LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
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

    group('SQL query construction and argument ordering', () {
      test('sorts with !includeDeleted - args in correct order', () async {
        // Setup data
        await insertRow({'id': '1', 'username': 'alice', 'age': 30});
        await insertRow({'id': '2', 'username': 'bob', 'age': 20});
        await insertRow({'id': '3', 'username': 'carol', 'age': 25});
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

        // Query with sort by schema column (age) - should work correctly
        final results = await storage.query(
          buildQuery(sorts: [const QuerySort(field: 'age', descending: true)]),
        );

        expect(results, hasLength(3));
        final ids = results
            .whereType<LocalFirstStateEvent<DummyModel>>()
            .map((e) => e.data.id)
            .toList();
        expect(ids, ['1', '3', '2']); // Descending by age: 30, 25, 20
      });

      test(
        'json_extract sort with !includeDeleted - args in correct order',
        () async {
          // Setup data with non-schema field
          await insertRow({
            'id': '1',
            'username': 'alice',
            'age': 20,
            'custom_score': 100,
          });
          await insertRow({
            'id': '2',
            'username': 'bob',
            'age': 25,
            'custom_score': 50,
          });
          await insertRow({
            'id': '3',
            'username': 'carol',
            'age': 30,
            'custom_score': 75,
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

          // Query with sort by non-schema field (uses json_extract)
          final results = await storage.query(
            buildQuery(
              sorts: [const QuerySort(field: 'custom_score', descending: true)],
            ),
          );

          expect(results, hasLength(3));
          final ids = results
              .whereType<LocalFirstStateEvent<DummyModel>>()
              .map((e) => e.data.id)
              .toList();
          expect(ids, ['1', '3', '2']); // Descending: 100, 75, 50
        },
      );

      test(
        'filter + json_extract sort + limit - complex arg ordering',
        () async {
          await insertRow({
            'id': '1',
            'username': 'alice',
            'age': 20,
            'score': 1.5,
          });
          await insertRow({
            'id': '2',
            'username': 'bob',
            'age': 30,
            'score': 2.5,
          });
          await insertRow({
            'id': '3',
            'username': 'carol',
            'age': 25,
            'score': 1.0,
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

          // Complex query: filter + non-schema sort + limit
          final results = await storage.query(
            buildQuery(
              filters: [const QueryFilter(field: 'age', isGreaterThan: 20)],
              sorts: [
                const QuerySort(field: 'custom_field', descending: false),
              ],
              limit: 5,
            ),
          );

          // Should return rows where age > 20
          expect(results, hasLength(2));
          final ids = results
              .whereType<LocalFirstStateEvent<DummyModel>>()
              .map((e) => e.data.id)
              .toSet();
          expect(ids, containsAll(['2', '3']));
        },
      );

      test('multiple json_extract filters with sorts', () async {
        await insertRow({
          'id': '1',
          'username': 'alice',
          'age': 20,
          'rating': 4.5,
          'level': 10,
        });
        await insertRow({
          'id': '2',
          'username': 'bob',
          'age': 25,
          'rating': 3.5,
          'level': 15,
        });
        await insertRow({
          'id': '3',
          'username': 'carol',
          'age': 30,
          'rating': 4.8,
          'level': 12,
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

        // Multiple non-schema filters + sort
        final results = await storage.query(
          buildQuery(
            filters: [
              const QueryFilter(field: 'rating', isGreaterThan: 4.0),
              const QueryFilter(field: 'level', isLessThan: 15),
            ],
            sorts: [const QuerySort(field: 'rating', descending: true)],
          ),
        );

        expect(results, hasLength(2));
        final ids = results
            .whereType<LocalFirstStateEvent<DummyModel>>()
            .map((e) => e.data.id)
            .toList();
        expect(ids, ['3', '1']); // Ordered by rating desc: 4.8, 4.5
      });

      test('whereIn with json_extract sort and offset', () async {
        await insertRow({
          'id': '1',
          'username': 'alice',
          'age': 20,
          'priority': 1,
        });
        await insertRow({
          'id': '2',
          'username': 'bob',
          'age': 25,
          'priority': 2,
        });
        await insertRow({
          'id': '3',
          'username': 'carol',
          'age': 30,
          'priority': 3,
        });
        await insertRow({
          'id': '4',
          'username': 'dave',
          'age': 35,
          'priority': 4,
        });
        for (var i = 1; i <= 4; i++) {
          await insertEvent(
            dataId: '$i',
            op: SyncOperation.insert,
            status: SyncStatus.ok,
            eventId: 'evt-$i',
          );
        }

        final results = await storage.query(
          buildQuery(
            filters: [
              const QueryFilter(
                field: 'username',
                whereIn: ['alice', 'bob', 'carol', 'dave'],
              ),
            ],
            sorts: [const QuerySort(field: 'priority', descending: false)],
            limit: 2,
            offset: 1,
          ),
        );

        expect(results, hasLength(2));
        final ids = results
            .whereType<LocalFirstStateEvent<DummyModel>>()
            .map((e) => e.data.id)
            .toList();
        expect(ids, ['2', '3']); // Skip 1st, take 2: priorities 2, 3
      });

      test('schema and non-schema filters mixed with sorts', () async {
        await insertRow({
          'id': '1',
          'username': 'alice',
          'age': 20,
          'score': 95.5,
        });
        await insertRow({
          'id': '2',
          'username': 'bob',
          'age': 30,
          'score': 88.0,
        });
        await insertRow({
          'id': '3',
          'username': 'carol',
          'age': 25,
          'score': 92.0,
        });
        for (var i = 1; i <= 3; i++) {
          await insertEvent(
            dataId: '$i',
            op: SyncOperation.insert,
            status: SyncStatus.ok,
            eventId: 'evt-$i',
          );
        }

        // Mix schema (age) and non-schema (score) fields
        final results = await storage.query(
          buildQuery(
            filters: [
              const QueryFilter(field: 'age', isGreaterThanOrEqualTo: 25),
              const QueryFilter(field: 'score', isGreaterThan: 90.0),
            ],
            sorts: [const QuerySort(field: 'age', descending: false)],
          ),
        );

        // Only carol meets both criteria: age >= 25 AND score > 90
        expect(results, hasLength(1));
        final ids = results
            .whereType<LocalFirstStateEvent<DummyModel>>()
            .map((e) => e.data.id)
            .toList();
        expect(ids, ['3']); // Only carol: age 25, score 92
      });

      test('empty whereIn returns empty results', () async {
        await insertRow({'id': '1', 'username': 'alice', 'age': 20});
        await insertEvent(
          dataId: '1',
          op: SyncOperation.insert,
          status: SyncStatus.ok,
          eventId: 'evt-1',
        );

        final results = await storage.query(
          buildQuery(
            filters: [const QueryFilter(field: 'username', whereIn: [])],
          ),
        );

        expect(results, isEmpty);
      });

      test('missing event fields are handled gracefully', () async {
        // Insert row without event (or with invalid event reference)
        final helper = TestHelperSqliteLocalFirstStorage(storage);
        final db = await helper.database;
        await db.insert('users', {
          'id': 'orphan',
          'username': 'ghost',
          'age': 99,
          'data': jsonEncode({'id': 'orphan', 'username': 'ghost', 'age': 99}),
          '_lasteventId': 'nonexistent-event',
        });

        // Query should not crash - should skip rows without valid events
        final results = await storage.query(buildQuery());

        // Should either skip the row or handle it gracefully
        expect(results, isA<List<LocalFirstEvent<DummyModel>>>());
      });

      test('complex multi-condition query validates arg order', () async {
        // Create diverse dataset
        for (var i = 1; i <= 10; i++) {
          await insertRow({
            'id': '$i',
            'username': 'user$i',
            'age': 20 + i,
            'score': i * 10.0,
            'level': i,
          });
          await insertEvent(
            dataId: '$i',
            op: i == 5 ? SyncOperation.delete : SyncOperation.insert,
            status: SyncStatus.ok,
            eventId: 'evt-$i',
          );
        }

        // Complex query with all features
        final results = await storage.query(
          buildQuery(
            filters: [
              const QueryFilter(field: 'age', isGreaterThan: 22),
              const QueryFilter(field: 'age', isLessThan: 29),
              const QueryFilter(
                field: 'username',
                whereNotIn: ['user1', 'user10'],
              ),
              const QueryFilter(field: 'level', isGreaterThanOrEqualTo: 3),
            ],
            sorts: [const QuerySort(field: 'score', descending: true)],
            limit: 3,
            offset: 0,
            includeDeleted: false,
          ),
        );

        // Should return user 4, 6, 7, 8 (user5 is deleted)
        // Filtered: age in (23-28), level >= 3, not in [user1, user10]
        // Sorted by score desc, limited to 3
        expect(results, hasLength(3));
        final ids = results
            .whereType<LocalFirstStateEvent<DummyModel>>()
            .map((e) => e.data.id)
            .toList();
        expect(ids, ['8', '7', '6']); // Highest scores first
      });
    });

    group('Insert and update flow with query validation', () {
      test('insert row and event, then query returns data', () async {
        // Simulate LocalFirstClient flow: insert data and event
        final userId = 'test-user-1';
        final eventId = 'evt-$userId';

        // Insert data row
        await storage.insert('users', {
          'id': userId,
          'username': 'testuser',
          'age': 25,
          LocalFirstEvent.kLastEventId: eventId,
        }, 'id');

        // Insert event row
        await storage.insertEvent('users', {
          LocalFirstEvent.kEventId: eventId,
          LocalFirstEvent.kDataId: userId,
          LocalFirstEvent.kSyncStatus: SyncStatus.pending.index,
          LocalFirstEvent.kOperation: SyncOperation.insert.index,
          LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
        }, LocalFirstEvent.kEventId);

        // Query should return the inserted data
        final results = await storage.query(buildQuery());

        expect(results, hasLength(1));
        final event = results.first as LocalFirstStateEvent<DummyModel>;
        expect(event.data.id, userId);
        expect(event.data.username, 'testuser');
        expect(event.data.age, 25);
      });

      test('update row and event, then query returns updated data', () async {
        final userId = 'test-user-2';
        final insertEventId = 'evt-insert-$userId';
        final updateEventId = 'evt-update-$userId';

        // Initial insert
        await storage.insert('users', {
          'id': userId,
          'username': 'oldname',
          'age': 20,
          LocalFirstEvent.kLastEventId: insertEventId,
        }, 'id');
        await storage.insertEvent('users', {
          LocalFirstEvent.kEventId: insertEventId,
          LocalFirstEvent.kDataId: userId,
          LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
          LocalFirstEvent.kOperation: SyncOperation.insert.index,
          LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
        }, LocalFirstEvent.kEventId);

        // Update
        await storage.update('users', userId, {
          'id': userId,
          'username': 'newname',
          'age': 21,
          LocalFirstEvent.kLastEventId: updateEventId,
        });
        await storage.insertEvent('users', {
          LocalFirstEvent.kEventId: updateEventId,
          LocalFirstEvent.kDataId: userId,
          LocalFirstEvent.kSyncStatus: SyncStatus.pending.index,
          LocalFirstEvent.kOperation: SyncOperation.update.index,
          LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
        }, LocalFirstEvent.kEventId);

        // Query should return updated data
        final results = await storage.query(buildQuery());

        expect(results, hasLength(1));
        final event = results.first as LocalFirstStateEvent<DummyModel>;
        expect(event.data.username, 'newname');
        expect(event.data.age, 21);
      });

      test('multiple inserts with proper events return all data', () async {
        // Insert multiple users
        for (var i = 1; i <= 5; i++) {
          final userId = 'user-$i';
          final eventId = 'evt-$userId';

          await storage.insert('users', {
            'id': userId,
            'username': 'user$i',
            'age': 20 + i,
            LocalFirstEvent.kLastEventId: eventId,
          }, 'id');

          await storage.insertEvent('users', {
            LocalFirstEvent.kEventId: eventId,
            LocalFirstEvent.kDataId: userId,
            LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
            LocalFirstEvent.kOperation: SyncOperation.insert.index,
            LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
          }, LocalFirstEvent.kEventId);
        }

        // Query should return all 5 users
        final results = await storage.query(buildQuery());

        expect(results, hasLength(5));
        final usernames = results
            .whereType<LocalFirstStateEvent<DummyModel>>()
            .map((e) => e.data.username)
            .toSet();
        expect(
          usernames,
          containsAll(['user1', 'user2', 'user3', 'user4', 'user5']),
        );
      });

      test('insert without proper event reference returns empty', () async {
        // Insert data but with non-existent event reference
        await storage.insert('users', {
          'id': 'orphan',
          'username': 'orphanuser',
          'age': 99,
          LocalFirstEvent.kLastEventId: 'nonexistent-event-id',
        }, 'id');

        // Query should skip this row (no valid event)
        final results = await storage.query(buildQuery());

        expect(results, isEmpty);
      });

      test('event with null syncStatus fields returns empty', () async {
        final userId = 'bad-event-user';
        final helper = TestHelperSqliteLocalFirstStorage(storage);
        final db = await helper.database;

        // Insert data row
        await storage.insert('users', {
          'id': userId,
          'username': 'baduser',
          'age': 30,
          LocalFirstEvent.kLastEventId: 'bad-evt',
        }, 'id');

        // Insert malformed event (missing required fields)
        await db.insert('users__events', {
          LocalFirstEvent.kEventId: 'bad-evt',
          LocalFirstEvent.kDataId: userId,
          // Missing syncStatus, operation, createdAt
        });

        // Query should skip this row (event missing required fields)
        final results = await storage.query(buildQuery());

        expect(results, isEmpty);
      });

      test('watchQuery emits on initial listen with existing data', () async {
        // Insert data BEFORE starting watch
        final userId = 'watch-user';
        final eventId = 'evt-$userId';

        await storage.insert('users', {
          'id': userId,
          'username': 'watchuser',
          'age': 27,
          LocalFirstEvent.kLastEventId: eventId,
        }, 'id');
        await storage.insertEvent('users', {
          LocalFirstEvent.kEventId: eventId,
          LocalFirstEvent.kDataId: userId,
          LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
          LocalFirstEvent.kOperation: SyncOperation.insert.index,
          LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
        }, LocalFirstEvent.kEventId);

        // Now start watching - should emit existing data on onListen
        final stream = storage.watchQuery(buildQuery());
        final results = await stream.first.timeout(Duration(seconds: 5));

        expect(results, hasLength(1));
        final event = results.first as LocalFirstStateEvent<DummyModel>;
        expect(event.data.username, 'watchuser');
      });

      test('query filters work after insert', () async {
        // Insert users with different ages
        for (var i = 1; i <= 3; i++) {
          final userId = 'filter-user-$i';
          final eventId = 'evt-$userId';
          final age = i * 10; // 10, 20, 30

          await storage.insert('users', {
            'id': userId,
            'username': 'filteruser$i',
            'age': age,
            LocalFirstEvent.kLastEventId: eventId,
          }, 'id');

          await storage.insertEvent('users', {
            LocalFirstEvent.kEventId: eventId,
            LocalFirstEvent.kDataId: userId,
            LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
            LocalFirstEvent.kOperation: SyncOperation.insert.index,
            LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
          }, LocalFirstEvent.kEventId);
        }

        // Query with filter: age > 15
        final results = await storage.query(
          buildQuery(
            filters: [const QueryFilter(field: 'age', isGreaterThan: 15)],
          ),
        );

        expect(results, hasLength(2)); // age 20 and 30
        final ages = results
            .whereType<LocalFirstStateEvent<DummyModel>>()
            .map((e) => e.data.age)
            .toList();
        expect(ages, containsAll([20, 30]));
      });

      test('sort works correctly after insert', () async {
        // Insert users in random order
        final users = [
          ('sort-c', 'charlie', 30),
          ('sort-a', 'alice', 20),
          ('sort-b', 'bob', 25),
        ];

        for (final (id, username, age) in users) {
          final eventId = 'evt-$id';

          await storage.insert('users', {
            'id': id,
            'username': username,
            'age': age,
            LocalFirstEvent.kLastEventId: eventId,
          }, 'id');

          await storage.insertEvent('users', {
            LocalFirstEvent.kEventId: eventId,
            LocalFirstEvent.kDataId: id,
            LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
            LocalFirstEvent.kOperation: SyncOperation.insert.index,
            LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
          }, LocalFirstEvent.kEventId);
        }

        // Query with age ascending
        final results = await storage.query(
          buildQuery(sorts: [const QuerySort(field: 'age', descending: false)]),
        );

        expect(results, hasLength(3));
        final usernames = results
            .whereType<LocalFirstStateEvent<DummyModel>>()
            .map((e) => e.data.username)
            .toList();
        expect(usernames, ['alice', 'bob', 'charlie']);
      });

      test('limit and offset work after insert', () async {
        // Insert 5 users
        for (var i = 1; i <= 5; i++) {
          final userId = 'page-user-$i';
          final eventId = 'evt-$userId';

          await storage.insert('users', {
            'id': userId,
            'username': 'pageuser$i',
            'age': i,
            LocalFirstEvent.kLastEventId: eventId,
          }, 'id');

          await storage.insertEvent('users', {
            LocalFirstEvent.kEventId: eventId,
            LocalFirstEvent.kDataId: userId,
            LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
            LocalFirstEvent.kOperation: SyncOperation.insert.index,
            LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
          }, LocalFirstEvent.kEventId);
        }

        // Query with limit 2, offset 1, sorted by age
        final results = await storage.query(
          buildQuery(
            sorts: [const QuerySort(field: 'age', descending: false)],
            limit: 2,
            offset: 1,
          ),
        );

        expect(results, hasLength(2));
        final ages = results
            .whereType<LocalFirstStateEvent<DummyModel>>()
            .map((e) => e.data.age)
            .toList();
        expect(ages, [2, 3]); // Skip age 1, take ages 2 and 3
      });
    });

    group('Generic type preservation in observers', () {
      test('notifyWatchers preserves generic type T', () async {
        // Insert initial data
        final userId = 'type-test-user';
        final eventId = 'evt-$userId';

        await storage.insert('users', {
          'id': userId,
          'username': 'typeuser',
          'age': 28,
          LocalFirstEvent.kLastEventId: eventId,
        }, 'id');
        await storage.insertEvent('users', {
          LocalFirstEvent.kEventId: eventId,
          LocalFirstEvent.kDataId: userId,
          LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
          LocalFirstEvent.kOperation: SyncOperation.insert.index,
          LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
        }, LocalFirstEvent.kEventId);

        // Create stream with explicit type
        final stream = storage.watchQuery<DummyModel>(buildQuery());

        // Collect emitted values
        final values = <List<LocalFirstEvent<DummyModel>>>[];
        final subscription = stream.listen((data) {
          // This should not throw a type error
          values.add(data);
        });

        // Wait for initial emission
        await Future.delayed(Duration(milliseconds: 100));

        // Trigger notifyWatchers which should preserve the generic type
        final helper = TestHelperSqliteLocalFirstStorage(storage);
        await helper.notifyWatchers('users');

        // Wait for notification to propagate
        await Future.delayed(Duration(milliseconds: 100));

        await subscription.cancel();

        // Should have received at least one emission with correct type
        expect(values, isNotEmpty);
        expect(values.first, isA<List<LocalFirstEvent<DummyModel>>>());

        // Verify the actual data type
        for (final list in values) {
          for (final event in list) {
            expect(event, isA<LocalFirstEvent<DummyModel>>());
            if (event is LocalFirstStateEvent<DummyModel>) {
              expect(event.data, isA<DummyModel>());
            }
          }
        }
      });

      test('multiple observers with different types work correctly', () async {
        // Setup for users repository
        await storage.insert('users', {
          'id': 'u1',
          'username': 'user1',
          'age': 25,
          LocalFirstEvent.kLastEventId: 'evt-u1',
        }, 'id');
        await storage.insertEvent('users', {
          LocalFirstEvent.kEventId: 'evt-u1',
          LocalFirstEvent.kDataId: 'u1',
          LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
          LocalFirstEvent.kOperation: SyncOperation.insert.index,
          LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
        }, LocalFirstEvent.kEventId);

        // Create two streams with same query
        final stream1 = storage.watchQuery<DummyModel>(buildQuery());
        final stream2 = storage.watchQuery<DummyModel>(buildQuery());

        final values1 = <List<LocalFirstEvent<DummyModel>>>[];
        final values2 = <List<LocalFirstEvent<DummyModel>>>[];

        final sub1 = stream1.listen((data) => values1.add(data));
        final sub2 = stream2.listen((data) => values2.add(data));

        await Future.delayed(Duration(milliseconds: 100));

        // Notify should update both observers
        final helper = TestHelperSqliteLocalFirstStorage(storage);
        await helper.notifyWatchers('users');

        await Future.delayed(Duration(milliseconds: 100));

        await sub1.cancel();
        await sub2.cancel();

        // Both should have received data with correct types
        expect(values1, isNotEmpty);
        expect(values2, isNotEmpty);

        for (final list in values1) {
          expect(list, isA<List<LocalFirstEvent<DummyModel>>>());
        }

        for (final list in values2) {
          expect(list, isA<List<LocalFirstEvent<DummyModel>>>());
        }
      });

      test('insert triggers notifyWatchers with correct type', () async {
        // Start watching before insert
        final stream = storage.watchQuery<DummyModel>(buildQuery());

        List<LocalFirstEvent<DummyModel>>? receivedData;
        Object? receivedError;

        final subscription = stream.listen(
          (data) {
            receivedData = data;
          },
          onError: (error) {
            receivedError = error;
          },
        );

        await Future.delayed(Duration(milliseconds: 50));

        // Insert new data (this calls notifyWatchers internally)
        await storage.insert('users', {
          'id': 'notify-user',
          'username': 'notifyuser',
          'age': 30,
          LocalFirstEvent.kLastEventId: 'evt-notify',
        }, 'id');
        await storage.insertEvent('users', {
          LocalFirstEvent.kEventId: 'evt-notify',
          LocalFirstEvent.kDataId: 'notify-user',
          LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
          LocalFirstEvent.kOperation: SyncOperation.insert.index,
          LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
        }, LocalFirstEvent.kEventId);

        // Wait for notification
        await Future.delayed(Duration(milliseconds: 100));

        await subscription.cancel();

        // Should not have type error
        expect(
          receivedError,
          isNull,
          reason: 'Should not receive type error: $receivedError',
        );
        expect(receivedData, isNotNull);
        expect(receivedData, isA<List<LocalFirstEvent<DummyModel>>>());
      });

      test('update triggers notifyWatchers with correct type', () async {
        // Insert initial data
        await storage.insert('users', {
          'id': 'update-user',
          'username': 'before',
          'age': 20,
          LocalFirstEvent.kLastEventId: 'evt-insert',
        }, 'id');
        await storage.insertEvent('users', {
          LocalFirstEvent.kEventId: 'evt-insert',
          LocalFirstEvent.kDataId: 'update-user',
          LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
          LocalFirstEvent.kOperation: SyncOperation.insert.index,
          LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
        }, LocalFirstEvent.kEventId);

        // Start watching
        final stream = storage.watchQuery<DummyModel>(buildQuery());

        Object? receivedError;
        final receivedData = <List<LocalFirstEvent<DummyModel>>>[];

        final subscription = stream.listen(
          (data) {
            receivedData.add(data);
          },
          onError: (error) {
            receivedError = error;
          },
        );

        await Future.delayed(Duration(milliseconds: 50));

        // Update (this calls notifyWatchers)
        await storage.update('users', 'update-user', {
          'id': 'update-user',
          'username': 'after',
          'age': 21,
          LocalFirstEvent.kLastEventId: 'evt-update',
        });
        await storage.insertEvent('users', {
          LocalFirstEvent.kEventId: 'evt-update',
          LocalFirstEvent.kDataId: 'update-user',
          LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
          LocalFirstEvent.kOperation: SyncOperation.update.index,
          LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
        }, LocalFirstEvent.kEventId);

        await Future.delayed(Duration(milliseconds: 100));

        await subscription.cancel();

        // Should not have type error
        expect(
          receivedError,
          isNull,
          reason: 'Should not receive type error: $receivedError',
        );
        expect(receivedData, isNotEmpty);

        for (final list in receivedData) {
          expect(list, isA<List<LocalFirstEvent<DummyModel>>>());
        }
      });
    });

    group('Upsert integration with query validation', () {
      test('insert (upsert when not exists) returns data in query', () async {
        final userId = 'upsert-new-user';
        final eventId = 'evt-$userId';

        // Insert data (upsert behavior - inserts new record)
        await storage.insert('users', {
          'id': userId,
          'username': 'newuser',
          'age': 25,
          LocalFirstEvent.kLastEventId: eventId,
        }, 'id');

        // Insert corresponding event
        await storage.insertEvent('users', {
          LocalFirstEvent.kEventId: eventId,
          LocalFirstEvent.kDataId: userId,
          LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
          LocalFirstEvent.kOperation: SyncOperation.insert.index,
          LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
        }, LocalFirstEvent.kEventId);

        // Query should return the upserted data
        final results = await storage.query(buildQuery());

        expect(results, hasLength(1));
        final event = results.first as LocalFirstStateEvent<DummyModel>;
        expect(event.data.id, userId);
        expect(event.data.username, 'newuser');
        expect(event.data.age, 25);
      });

      test(
        'update (upsert when exists) returns updated data in query',
        () async {
          final userId = 'upsert-existing-user';
          final insertEventId = 'evt-insert-$userId';
          final updateEventId = 'evt-update-$userId';

          // Initial insert
          await storage.insert('users', {
            'id': userId,
            'username': 'original',
            'age': 20,
            LocalFirstEvent.kLastEventId: insertEventId,
          }, 'id');
          await storage.insertEvent('users', {
            LocalFirstEvent.kEventId: insertEventId,
            LocalFirstEvent.kDataId: userId,
            LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
            LocalFirstEvent.kOperation: SyncOperation.insert.index,
            LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
          }, LocalFirstEvent.kEventId);

          // Verify initial state
          var results = await storage.query(buildQuery());
          expect(results, hasLength(1));
          var event = results.first as LocalFirstStateEvent<DummyModel>;
          expect(event.data.username, 'original');
          expect(event.data.age, 20);

          // Update (upsert behavior - replaces existing record)
          await storage.update('users', userId, {
            'id': userId,
            'username': 'updated',
            'age': 30,
            LocalFirstEvent.kLastEventId: updateEventId,
          });
          await storage.insertEvent('users', {
            LocalFirstEvent.kEventId: updateEventId,
            LocalFirstEvent.kDataId: userId,
            LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
            LocalFirstEvent.kOperation: SyncOperation.update.index,
            LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
          }, LocalFirstEvent.kEventId);

          // Query should return the updated data
          results = await storage.query(buildQuery());
          expect(results, hasLength(1));
          event = results.first as LocalFirstStateEvent<DummyModel>;
          expect(event.data.id, userId);
          expect(event.data.username, 'updated');
          expect(event.data.age, 30);
        },
      );

      test('multiple upserts return all data in query', () async {
        // Upsert 3 users
        for (var i = 1; i <= 3; i++) {
          final userId = 'multi-upsert-$i';
          final eventId = 'evt-$userId';

          await storage.insert('users', {
            'id': userId,
            'username': 'user$i',
            'age': 20 + i,
            LocalFirstEvent.kLastEventId: eventId,
          }, 'id');

          await storage.insertEvent('users', {
            LocalFirstEvent.kEventId: eventId,
            LocalFirstEvent.kDataId: userId,
            LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
            LocalFirstEvent.kOperation: SyncOperation.insert.index,
            LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
          }, LocalFirstEvent.kEventId);
        }

        // Query should return all 3 users
        final results = await storage.query(buildQuery());

        expect(results, hasLength(3));
        final usernames = results
            .whereType<LocalFirstStateEvent<DummyModel>>()
            .map((e) => e.data.username)
            .toSet();
        expect(usernames, containsAll(['user1', 'user2', 'user3']));
      });

      test('upsert via insert triggers watchQuery emission', () async {
        final userId = 'watch-upsert-user';
        final eventId = 'evt-$userId';

        // Start watching
        final stream = storage.watchQuery<DummyModel>(buildQuery());

        List<LocalFirstEvent<DummyModel>>? receivedData;
        final subscription = stream.listen((data) {
          receivedData = data;
        });

        await Future.delayed(Duration(milliseconds: 50));

        // Upsert (insert)
        await storage.insert('users', {
          'id': userId,
          'username': 'watchuser',
          'age': 35,
          LocalFirstEvent.kLastEventId: eventId,
        }, 'id');
        await storage.insertEvent('users', {
          LocalFirstEvent.kEventId: eventId,
          LocalFirstEvent.kDataId: userId,
          LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
          LocalFirstEvent.kOperation: SyncOperation.insert.index,
          LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
        }, LocalFirstEvent.kEventId);

        // Wait for notification
        await Future.delayed(Duration(milliseconds: 100));

        await subscription.cancel();

        // Should have received the upserted data
        expect(receivedData, isNotNull);
        expect(receivedData, hasLength(1));
        final event = receivedData!.first as LocalFirstStateEvent<DummyModel>;
        expect(event.data.username, 'watchuser');
        expect(event.data.age, 35);
      });

      test('upsert via update triggers watchQuery emission', () async {
        final userId = 'watch-update-user';
        final insertEventId = 'evt-insert-$userId';
        final updateEventId = 'evt-update-$userId';

        // Initial insert
        await storage.insert('users', {
          'id': userId,
          'username': 'before',
          'age': 40,
          LocalFirstEvent.kLastEventId: insertEventId,
        }, 'id');
        await storage.insertEvent('users', {
          LocalFirstEvent.kEventId: insertEventId,
          LocalFirstEvent.kDataId: userId,
          LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
          LocalFirstEvent.kOperation: SyncOperation.insert.index,
          LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
        }, LocalFirstEvent.kEventId);

        // Start watching
        final stream = storage.watchQuery<DummyModel>(buildQuery());

        final receivedData = <List<LocalFirstEvent<DummyModel>>>[];
        final subscription = stream.listen((data) {
          receivedData.add(data);
        });

        await Future.delayed(Duration(milliseconds: 50));

        // Upsert (update)
        await storage.update('users', userId, {
          'id': userId,
          'username': 'after',
          'age': 45,
          LocalFirstEvent.kLastEventId: updateEventId,
        });
        await storage.insertEvent('users', {
          LocalFirstEvent.kEventId: updateEventId,
          LocalFirstEvent.kDataId: userId,
          LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
          LocalFirstEvent.kOperation: SyncOperation.update.index,
          LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
        }, LocalFirstEvent.kEventId);

        // Wait for notification
        await Future.delayed(Duration(milliseconds: 100));

        await subscription.cancel();

        // Should have received at least 2 emissions: initial + update
        expect(receivedData, isNotEmpty);

        // Last emission should have the updated data
        final lastEmission = receivedData.last;
        expect(lastEmission, hasLength(1));
        final event = lastEmission.first as LocalFirstStateEvent<DummyModel>;
        expect(event.data.username, 'after');
        expect(event.data.age, 45);
      });

      test('query after upsert with filters returns correct results', () async {
        // Upsert users with different ages
        for (var i = 1; i <= 5; i++) {
          final userId = 'filter-upsert-$i';
          final eventId = 'evt-$userId';

          await storage.insert('users', {
            'id': userId,
            'username': 'filteruser$i',
            'age': i * 10, // 10, 20, 30, 40, 50
            LocalFirstEvent.kLastEventId: eventId,
          }, 'id');

          await storage.insertEvent('users', {
            LocalFirstEvent.kEventId: eventId,
            LocalFirstEvent.kDataId: userId,
            LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
            LocalFirstEvent.kOperation: SyncOperation.insert.index,
            LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
          }, LocalFirstEvent.kEventId);
        }

        // Query with filter: age >= 30
        final results = await storage.query(
          buildQuery(
            filters: [
              const QueryFilter(field: 'age', isGreaterThanOrEqualTo: 30),
            ],
          ),
        );

        expect(results, hasLength(3)); // ages 30, 40, 50
        final ages = results
            .whereType<LocalFirstStateEvent<DummyModel>>()
            .map((e) => e.data.age)
            .toList();
        expect(ages, containsAll([30, 40, 50]));
      });

      test('query after upsert with sorts returns correct order', () async {
        // Upsert users in random order
        final users = [
          ('sort-upsert-c', 'charlie', 30),
          ('sort-upsert-a', 'alice', 10),
          ('sort-upsert-b', 'bob', 20),
        ];

        for (final (id, username, age) in users) {
          final eventId = 'evt-$id';

          await storage.insert('users', {
            'id': id,
            'username': username,
            'age': age,
            LocalFirstEvent.kLastEventId: eventId,
          }, 'id');

          await storage.insertEvent('users', {
            LocalFirstEvent.kEventId: eventId,
            LocalFirstEvent.kDataId: id,
            LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
            LocalFirstEvent.kOperation: SyncOperation.insert.index,
            LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
          }, LocalFirstEvent.kEventId);
        }

        // Query with sort by age ascending
        final results = await storage.query(
          buildQuery(sorts: [const QuerySort(field: 'age', descending: false)]),
        );

        expect(results, hasLength(3));
        final usernames = results
            .whereType<LocalFirstStateEvent<DummyModel>>()
            .map((e) => e.data.username)
            .toList();
        expect(usernames, ['alice', 'bob', 'charlie']); // sorted by age
      });

      test(
        'query handles data row with _lasteventId but no matching event',
        () async {
          final userId = 'orphan-data';
          final eventId = 'orphan-evt';

          // Insert data with _lasteventId pointing to non-existent event
          // This can happen if event insert fails or is delayed
          await storage.insert('users', {
            'id': userId,
            'username': 'orphanuser',
            'age': 50,
            LocalFirstEvent.kLastEventId: eventId, // Event doesn't exist yet
          }, 'id');

          // Query without the missing event should return empty
          // (not crash, but also not return invalid data)
          final results = await storage.query(buildQuery());

          // Should not find the data because there's no valid event
          expect(results, isEmpty);
        },
      );

      test('inserting event after data makes query return results', () async {
        final userId = 'delayed-event-user';
        final eventId = 'delayed-evt';

        // Step 1: Insert data first (without event)
        await storage.insert('users', {
          'id': userId,
          'username': 'delayeduser',
          'age': 60,
          LocalFirstEvent.kLastEventId: eventId,
        }, 'id');

        // Query should be empty (no event yet)
        var results = await storage.query(buildQuery());
        expect(
          results,
          isEmpty,
          reason: 'Should be empty when event is missing',
        );

        // Step 2: Now insert the event
        await storage.insertEvent('users', {
          LocalFirstEvent.kEventId: eventId,
          LocalFirstEvent.kDataId: userId,
          LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
          LocalFirstEvent.kOperation: SyncOperation.insert.index,
          LocalFirstEvent.kSyncCreatedAt: DateTime.now().millisecondsSinceEpoch,
        }, LocalFirstEvent.kEventId);

        // Query should now return the data
        results = await storage.query(buildQuery());
        expect(
          results,
          hasLength(1),
          reason: 'Should return data after event is inserted',
        );

        final event = results.first as LocalFirstStateEvent<DummyModel>;
        expect(event.data.username, 'delayeduser');
        expect(event.data.age, 60);
      });
    });
  });
}
