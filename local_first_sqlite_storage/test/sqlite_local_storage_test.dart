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
    return DummyModel(
      json['id'] as String,
      username: json['username'] as String,
      age: json['age'] as int,
    );
  }

  JsonMap toJson() => {'id': id, 'username': username, 'age': age};
}

abstract class QueryBehavior {
  Future<List<JsonMap>> call(LocalFirstQuery query);
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
      List<QueryFilter> filters = const [],
      List<QuerySort> sorts = const [],
      int? limit,
      int? offset,
      bool includeDeleted = false,
    }) {
      return LocalFirstQuery<DummyModel>(
        repositoryName: 'users',
        delegate: storage,
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
