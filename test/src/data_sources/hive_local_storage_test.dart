import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

void main() {
  group('HiveLocalFirstStorage', () {
    late Directory tempDir;
    late HiveLocalFirstStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_local_first_test');
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
      await storage.insert('users', {'id': '1', 'name': 'Alice'}, 'id');
      await storage.insert('users', {'id': '2', 'name': 'Bob'}, 'id');

      final byId = await storage.getById('users', '1');
      expect(byId, isNotNull);
      expect(byId?['name'], 'Alice');

      final all = await storage.getAll('users');
      expect(all.length, 2);

      await storage.update('users', '1', {'id': '1', 'name': 'Charlie'});
      final updated = await storage.getById('users', '1');
      expect(updated?['name'], 'Charlie');

      await storage.delete('users', '1');
      final afterDelete = await storage.getById('users', '1');
      expect(afterDelete, isNull);

      await storage.deleteAll('users');
      final afterDeleteAll = await storage.getAll('users');
      expect(afterDeleteAll, isEmpty);
    });

    test('set/get last sync and metadata', () async {
      await storage.setMeta('key', 'value');
      expect(await storage.getMeta('key'), 'value');
    });

    test('clearAllData wipes boxes and metadata', () async {
      await storage.insert('users', {'id': '1', 'name': 'Alice'}, 'id');
      await storage.setMeta('key', 'value');

      await storage.clearAllData();
      expect(await storage.getAll('users'), isEmpty);
      expect(await storage.getMeta('key'), isNull);
    });

    test('namespace isolation with useNamespace', () async {
      await storage.insert('users', {'id': '1', 'name': 'Alice'}, 'id');
      expect((await storage.getAll('users')).length, 1);

      await storage.useNamespace('ns2');
      expect(await storage.getAll('users'), isEmpty);

      await storage.insert('users', {'id': '2', 'name': 'Bob'}, 'id');
      expect((await storage.getAll('users')).length, 1);

      await storage.useNamespace('ns1');
      final original = await storage.getAll('users');
      expect(original.length, 1);
      expect(original.first['id'], '1');
    });

    test('namespace getter reflects current namespace', () async {
      expect(storage.namespace, 'ns1');
      await storage.useNamespace('ns2');
      expect(storage.namespace, 'ns2');
    });

    test('query applies filters, sorting, limit, offset', () async {
      await storage.insert('users', {'id': '1', 'age': 20}, 'id');
      await storage.insert('users', {'id': '2', 'age': 30}, 'id');
      await storage.insert('users', {'id': '3', 'age': 40}, 'id');

      final q = LocalFirstQuery<_TestModel>(
        repositoryName: 'users',
        delegate: storage,
        fromJson: _TestModel.fromJson,
        repository: _DummyRepo(),
      );

      final results = await q
          .where('age', isGreaterThan: 20)
          .orderBy('age', descending: true)
          .limitTo(1)
          .startAfter(0)
          .getAll();

      expect(results.length, 1);
      expect(results.first.id, '3');
    });

    test('watchQuery emits initial results', () async {
      await storage.insert('users', {'id': '1'}, 'id');
      final q = LocalFirstQuery<_TestModel>(
        repositoryName: 'users',
        delegate: storage,
        fromJson: _TestModel.fromJson,
        repository: _DummyRepo(),
      );

      final stream = q.watch();
      final first = await stream.first;
      expect(first.length, 1);
      expect(first.first.id, '1');
    });

    test('watchQuery throws if not initialized', () async {
      final uninitialized = HiveLocalFirstStorage(
        customPath: tempDir.path,
        namespace: 'ns_uninitialized',
      );
      final q = LocalFirstQuery<_TestModel>(
        repositoryName: 'users',
        delegate: uninitialized,
        fromJson: _TestModel.fromJson,
        repository: _DummyRepo(),
      );

      expect(
        () => uninitialized.watchQuery(q).first,
        throwsA(isA<StateError>()),
      );
    });

    test('watchQuery streams changes after initial emission', () async {
      final q = LocalFirstQuery<_TestModel>(
        repositoryName: 'users',
        delegate: storage,
        fromJson: _TestModel.fromJson,
        repository: _DummyRepo(),
      );

      final iterator = StreamIterator(
        storage
            .watchQuery(q)
            .map((items) => items.map((e) => e['id'].toString()).toList()),
      );

      // Initial emission should be an empty list.
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, isEmpty);

      await storage.insert('users', {'id': '1', 'age': 10}, 'id');
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, ['1']);

      await storage.insert('users', {'id': '2', 'age': 20}, 'id');
      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current, containsAll(['1', '2']));

      await iterator.cancel();
    });
  });

  group('HiveLocalFirstStorage watchQuery error handling', () {
    late Directory tempDir;
    late HiveLocalFirstStorage throwingStorage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hive_local_first_test_throw');
      throwingStorage = HiveLocalFirstStorage(
        customPath: tempDir.path,
        namespace: 'ns_throw',
      );
      await throwingStorage.initialize();
      // Force an error by closing to make watchQuery emit StateError on listen.
      await throwingStorage.close();
    });

    tearDown(() async {
      await throwingStorage.close();
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {
          // ignore cleanup errors
        }
      }
    });

    test('watchQuery propagates errors from emitCurrent', () async {
      final q = LocalFirstQuery<_TestModel>(
        repositoryName: 'users',
        delegate: throwingStorage,
        fromJson: _TestModel.fromJson,
        repository: _DummyRepo(),
      );

      expect(() => throwingStorage.watchQuery(q), throwsA(isA<StateError>()));
    });
  });

  group('HiveLocalFirstStorage guard clauses', () {
    late HiveLocalFirstStorage uninitialized;

    setUp(() {
      uninitialized = HiveLocalFirstStorage(namespace: 'ns_guard');
    });

    test('setMeta throws when not initialized', () async {
      expect(
        () => uninitialized.setMeta('k', 'v'),
        throwsA(isA<StateError>()),
      );
    });

    test('getAll/getById/delete throw when not initialized', () async {
      expect(() => uninitialized.getAll('users'), throwsA(isA<StateError>()));
      expect(() => uninitialized.getById('users', '1'), throwsA(isA<StateError>()));
      expect(() => uninitialized.delete('users', '1'), throwsA(isA<StateError>()));
    });

    test('clearAllData/getMeta/query throw when not initialized', () async {
      expect(() => uninitialized.clearAllData(), throwsA(isA<StateError>()));
      expect(() => uninitialized.getMeta('k'), throwsA(isA<StateError>()));
      final q = LocalFirstQuery<_TestModel>(
        repositoryName: 'users',
        delegate: uninitialized,
        fromJson: _TestModel.fromJson,
        repository: _DummyRepo(),
      );
      expect(() => uninitialized.query(q), throwsA(isA<StateError>()));
    });
  });

  group('HiveLocalFirstStorage initialization paths', () {
    test('stores metadata under customPath', () async {
      final dir = await Directory.systemTemp.createTemp('hive_custom_path');
      final storage = HiveLocalFirstStorage(
        customPath: dir.path,
        namespace: 'ns_init',
      );

      await storage.initialize();
      await storage.setMeta('k', 'v');

      final hasMetaBox = Directory(dir.path)
          .listSync()
          .any((f) => f.path.contains('offline_metadata'));
      expect(hasMetaBox, isTrue);

      await storage.close();
      await dir.delete(recursive: true);
    });

    test('initializes with default path when customPath is null', () async {
      final storage = HiveLocalFirstStorage(namespace: 'ns_default_path');
      await storage.initialize();
      await storage.setMeta('k', 'v'); // should not throw
      await storage.close();
    });
  });
}

class _TestModel with LocalFirstModel {
  _TestModel({required this.id, this.age});

  final String id;
  final int? age;

  @override
  Map<String, dynamic> toJson() => {'id': id, if (age != null) 'age': age};

  factory _TestModel.fromJson(Map<String, dynamic> json) =>
      _TestModel(id: json['id'] as String, age: json['age'] as int?);
}

class _DummyRepo extends LocalFirstRepository<_TestModel> {
  _DummyRepo()
    : super(
        name: 'users',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: _TestModel.fromJson,
        onConflict: (l, r) => l,
      );
}
