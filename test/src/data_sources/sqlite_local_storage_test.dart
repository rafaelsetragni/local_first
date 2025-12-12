import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _DummyModel with LocalFirstModel {
  _DummyModel(this.id, {required this.username, required this.age});

  final String id;
  final String username;
  final int age;

  factory _DummyModel.fromJson(Map<String, dynamic> json) {
    return _DummyModel(
      json['id'] as String,
      username: json['username'] as String,
      age: json['age'] as int,
    );
  }

  @override
  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'age': age};
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

  group('SqliteLocalFirstStorage', () {
    late SqliteLocalFirstStorage storage;

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

    LocalFirstQuery<_DummyModel> _query({
      List<QueryFilter> filters = const [],
      List<QuerySort> sorts = const [],
      int? limit,
      int? offset,
    }) {
      return LocalFirstQuery<_DummyModel>(
        repositoryName: 'users',
        delegate: storage,
        fromJson: _DummyModel.fromJson,
        repository: LocalFirstRepository<_DummyModel>.create(
          name: 'users',
          getId: (m) => m.id,
          toJson: (m) => m.toJson(),
          fromJson: _DummyModel.fromJson,
          onConflict: (l, r) => l,
          schema: schema,
        ),
        filters: filters,
        sorts: sorts,
        limit: limit,
        offset: offset,
      );
    }

    Future<void> _insert(Map<String, dynamic> item) {
      final now = DateTime.now().millisecondsSinceEpoch;
      return storage.insert('users', {
        ...item,
        '_sync_status': SyncStatus.ok.index,
        '_sync_operation': SyncOperation.insert.index,
        '_sync_created_at': now,
      }, 'id');
    }

    test('filters and sorts using schema columns', () async {
      await _insert({'id': '1', 'username': 'alice', 'age': 20});
      await _insert({'id': '2', 'username': 'bob', 'age': 35});
      await _insert({'id': '3', 'username': 'carol', 'age': 28});

      final results = await storage.query(
        _query(
          filters: [QueryFilter(field: 'age', isGreaterThan: 25)],
          sorts: [QuerySort(field: 'age', descending: true)],
        ),
      );

      expect(results.map((e) => e['id']), ['2', '3']);
    });

    test('applies limit and offset', () async {
      await _insert({'id': '1', 'username': 'alice', 'age': 20, 'score': 1.1});
      await _insert({'id': '2', 'username': 'bob', 'age': 25, 'score': 2.2});
      await _insert({'id': '3', 'username': 'carol', 'age': 30, 'score': 3.3});

      final results = await storage.query(
        _query(sorts: [const QuerySort(field: 'age')], limit: 1, offset: 1),
      );

      expect(results.single['id'], '2');
    });

    test('encodes boolean, datetime, real, blob, and fallback types', () async {
      final birth = DateTime.utc(2000, 1, 1);
      final avatarBytes = [1, 2, 3];

      await _insert({
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
      await _insert({'id': '10', 'username': 'zelda', 'age': 40});

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
      await _insert({'id': '1', 'username': 'a', 'age': 20});
      await storage.setMeta('key', 'value');

      await storage.deleteAll('users');
      expect(await storage.getAll('users'), isEmpty);

      await _insert({'id': '2', 'username': 'b', 'age': 21});
      await storage.clearAllData();
      expect(await storage.getAll('users'), isEmpty);
      expect(await storage.getMeta('key'), isNull);
    });

    test('setMeta and getMeta store values', () async {
      await storage.setMeta('foo', 'bar');
      expect(await storage.getMeta('foo'), 'bar');
    });

    test('watchQuery emits on changes', () async {
      final stream = storage.watchQuery(_query());

      final expectation = expectLater(
        stream,
        emitsInOrder([
          isEmpty,
          predicate<List<Map<String, dynamic>>>(
            (items) => items.any((m) => m['id'] == 'w1'),
          ),
        ]),
      );

      await _insert({'id': 'w1', 'username': 'watch', 'age': 22});
      await expectation;
    });
  });
}
