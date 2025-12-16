import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_hive_storage/local_first_hive_storage.dart';
import 'package:mocktail/mocktail.dart';

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

    test('lazyCollections uses LazyBox for configured tables', () async {
      final lazyStorage = HiveLocalFirstStorage(
        customPath: tempDir.path,
        namespace: 'lazyNs',
        lazyCollections: {'lazy_users'},
      );
      await lazyStorage.initialize();

      await lazyStorage.insert('lazy_users', {'id': '1', 'name': 'Lazy'}, 'id');
      await lazyStorage.insert('eager_users', {
        'id': '2',
        'name': 'Eager',
      }, 'id');

      final lazyAll = await lazyStorage.getAll('lazy_users');
      final eagerAll = await lazyStorage.getAll('eager_users');

      expect(lazyAll.single['name'], 'Lazy');
      expect(eagerAll.single['name'], 'Eager');

      final lazyById = await lazyStorage.getById('lazy_users', '1');
      expect(lazyById?['name'], 'Lazy');

      await lazyStorage.close();
    });

    test('ensureSchema is a no-op (Hive is schemaless)', () async {
      await storage.ensureSchema('users', const {
        'anyField': LocalFieldType.text,
      }, idFieldName: 'id');

      // Still able to insert and read without schema enforcement.
      await storage.insert('users', {
        'id': 'schema-less',
        'name': 'Hive',
      }, 'id');
      final fetched = await storage.getById('users', 'schema-less');
      expect(fetched?['name'], 'Hive');
      // Unknown field is preserved in stored data.
      await storage.update('users', 'schema-less', {
        'id': 'schema-less',
        'name': 'Hive',
        'extra': 123,
      });
      final updated = await storage.getById('users', 'schema-less');
      expect(updated?['extra'], 123);
    });

    test('query handles lazy boxes with filters', () async {
      final lazyStorage = HiveLocalFirstStorage(
        customPath: tempDir.path,
        namespace: 'lazyQuery',
        lazyCollections: {'lazy_q'},
      );
      await lazyStorage.initialize();

      await lazyStorage.insert('lazy_q', {'id': '1', 'age': 20}, 'id');
      await lazyStorage.insert('lazy_q', {'id': '2', 'age': 35}, 'id');

      final repo = LocalFirstRepository<_TestModel>.create(
        name: 'lazy_q',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: _TestModel.fromJson,
        onConflict: (l, r) => l,
      );

      final q = LocalFirstQuery<_TestModel>(
        repositoryName: 'lazy_q',
        delegate: lazyStorage,
        fromJson: _TestModel.fromJson,
        repository: repo,
      );

      final results = await q.where('age', isGreaterThan: 25).getAll();
      expect(results.length, 1);
      expect(results.first.id, '2');

      await lazyStorage.close();
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
      await storage.insert('users', {'id': '4', 'age': null}, 'id');

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

      // Null entries are skipped inside Hive query mapping.
      final all = await storage.getAll('users');
      expect(all.length, 4);
      final mapped = await q.where('age', isGreaterThan: 0).getAll();
      expect(mapped.length, 3); // ids 1,2,3 (skipping null age)
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
      tempDir = await Directory.systemTemp.createTemp(
        'hive_local_first_test_throw',
      );
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

  group('HiveLocalFirstStorage emitCurrent errors', () {
    test('watchQuery emits error when query throws', () async {
      final fakeHive = _MockHive();
      final mockMeta = _MockBox<dynamic>();
      final mockBox = _MockBox<Map>();

      when(() => fakeHive.init(any())).thenReturn(null);
      when(
        () => fakeHive.openBox<dynamic>(
          any(),
          encryptionCipher: any(named: 'encryptionCipher'),
          keyComparator: any(named: 'keyComparator'),
          crashRecovery: any(named: 'crashRecovery'),
        ),
      ).thenAnswer((_) async => mockMeta);
      when(
        () => fakeHive.openBox<Map>(
          any(),
          encryptionCipher: any(named: 'encryptionCipher'),
          keyComparator: any(named: 'keyComparator'),
          crashRecovery: any(named: 'crashRecovery'),
        ),
      ).thenAnswer((_) async => mockBox);
      when(() => mockMeta.close()).thenAnswer((_) async {});
      when(() => mockMeta.clear()).thenAnswer((_) async => 0);
      when(() => mockMeta.values).thenReturn(const []);
      when(() => mockBox.watch()).thenAnswer((_) => const Stream.empty());
      when(() => mockBox.clear()).thenAnswer((_) async => 0);
      when(() => mockBox.close()).thenAnswer((_) async {});
      when(() => mockBox.put(any(), any())).thenAnswer((_) async {});
      when(() => mockBox.values).thenReturn(const <Map<dynamic, dynamic>>[]);

      final storage = _ThrowingQueryHiveStorage(
        customPath: Directory.systemTemp.path,
        namespace: 'ns_emit_error',
        hive: fakeHive,
        initFlutter: () async {},
      );
      await storage.initialize();

      final q = LocalFirstQuery<_TestModel>(
        repositoryName: 'users',
        delegate: storage,
        fromJson: _TestModel.fromJson,
        repository: _DummyRepo(),
      );

      await expectLater(storage.watchQuery(q), emitsError(isA<Exception>()));
    });
  });

  group('HiveLocalFirstStorage guard clauses', () {
    late HiveLocalFirstStorage uninitialized;

    setUp(() {
      uninitialized = HiveLocalFirstStorage(namespace: 'ns_guard');
    });

    test('setMeta throws when not initialized', () async {
      expect(() => uninitialized.setMeta('k', 'v'), throwsA(isA<StateError>()));
    });

    test('getAll/getById/delete throw when not initialized', () async {
      expect(() => uninitialized.getAll('users'), throwsA(isA<StateError>()));
      expect(
        () => uninitialized.getById('users', '1'),
        throwsA(isA<StateError>()),
      );
      expect(
        () => uninitialized.delete('users', '1'),
        throwsA(isA<StateError>()),
      );
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
      await expectLater(uninitialized.query(q), throwsA(isA<StateError>()));
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

      final hasMetaBox = Directory(
        dir.path,
      ).listSync().any((f) => f.path.contains('offline_metadata'));
      expect(hasMetaBox, isTrue);

      await storage.close();
      await dir.delete(recursive: true);
    });

    test('clearAllData continues if deleteBoxFromDisk fails', () async {
      final fakeHive = _MockHive();
      final mockMeta = _MockBox<dynamic>();
      final mockBox = _MockBox<Map>();

      when(() => fakeHive.init(any())).thenReturn(null);
      when(
        () => fakeHive.openBox<dynamic>(
          any(),
          encryptionCipher: any(named: 'encryptionCipher'),
          keyComparator: any(named: 'keyComparator'),
          crashRecovery: any(named: 'crashRecovery'),
        ),
      ).thenAnswer((_) async => mockMeta);
      when(
        () => fakeHive.openBox<Map>(
          any(),
          encryptionCipher: any(named: 'encryptionCipher'),
          keyComparator: any(named: 'keyComparator'),
          crashRecovery: any(named: 'crashRecovery'),
        ),
      ).thenAnswer((_) async => mockBox);
      when(() => mockMeta.close()).thenAnswer((_) async {});
      when(() => mockMeta.clear()).thenAnswer((_) async => 0);
      when(() => mockMeta.values).thenReturn(const []);
      when(() => mockBox.clear()).thenAnswer((_) async => 0);
      when(() => mockBox.close()).thenAnswer((_) async {});
      when(() => mockBox.put(any(), any())).thenAnswer((_) async {});
      when(() => mockBox.values).thenReturn(const <Map<dynamic, dynamic>>[]);
      when(
        () => fakeHive.deleteBoxFromDisk(any(), path: any(named: 'path')),
      ).thenThrow(Exception('delete failed'));

      final storage = HiveLocalFirstStorage(
        customPath: Directory.systemTemp.path,
        namespace: 'ns_fail_delete',
        hive: fakeHive,
      );
      await storage.initialize();
      await storage.insert('users', {'id': '1'}, 'id');

      // Should not throw even if deleteBoxFromDisk fails.
      await storage.clearAllData();

      verify(
        () => fakeHive.deleteBoxFromDisk(any(), path: any(named: 'path')),
      ).called(greaterThan(0));
    });

    test('initialize uses initFlutter when customPath is null', () async {
      final fakeHive = _MockHive();
      final mockMeta = _MockBox<dynamic>();
      var initFlutterCalled = false;

      when(
        () => fakeHive.openBox<dynamic>(
          any(),
          encryptionCipher: any(named: 'encryptionCipher'),
          keyComparator: any(named: 'keyComparator'),
          crashRecovery: any(named: 'crashRecovery'),
        ),
      ).thenAnswer((_) async => mockMeta);
      when(() => mockMeta.close()).thenAnswer((_) async {});
      when(() => mockMeta.clear()).thenAnswer((_) async => 0);
      when(() => mockMeta.values).thenReturn(const []);

      final storage = HiveLocalFirstStorage(
        namespace: 'ns_default',
        hive: fakeHive,
        initFlutter: () async {
          initFlutterCalled = true;
        },
      );

      await storage.initialize();
      expect(initFlutterCalled, isTrue);
      verifyNever(() => fakeHive.init(any()));
    });

    test('query skips null raw items', () async {
      final fakeHive = _MockHive();
      final mockMeta = _MockBox<dynamic>();
      final mockBox = _MockBox<Map>();

      when(() => fakeHive.init(any())).thenReturn(null);
      when(
        () => fakeHive.openBox<dynamic>(
          any(),
          encryptionCipher: any(named: 'encryptionCipher'),
          keyComparator: any(named: 'keyComparator'),
          crashRecovery: any(named: 'crashRecovery'),
        ),
      ).thenAnswer((_) async => mockMeta);
      when(
        () => fakeHive.openBox<Map>(
          any(),
          encryptionCipher: any(named: 'encryptionCipher'),
          keyComparator: any(named: 'keyComparator'),
          crashRecovery: any(named: 'crashRecovery'),
        ),
      ).thenAnswer((_) async => mockBox);
      when(() => mockMeta.close()).thenAnswer((_) async {});
      when(() => mockMeta.clear()).thenAnswer((_) async => 0);
      when(() => mockMeta.values).thenReturn(const []);
      when(() => mockBox.keys).thenReturn([1, 2]);
      when(() => mockBox.get(1)).thenReturn(null);
      when(() => mockBox.get(2)).thenReturn({'id': '2', 'age': 10});

      final storage = HiveLocalFirstStorage(
        customPath: Directory.systemTemp.path,
        namespace: 'ns_skip_null',
        hive: fakeHive,
      );
      await storage.initialize();

      final q = LocalFirstQuery<_TestModel>(
        repositoryName: 'users',
        delegate: storage,
        fromJson: _TestModel.fromJson,
        repository: _DummyRepo(),
      );

      final results = await storage.query(q);
      expect(results.length, 1);
      expect(results.first['id'], '2');
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

class _MockHive extends Mock implements HiveInterface {}

class _MockBox<E> extends Mock implements Box<E> {}

class _ThrowingQueryHiveStorage extends HiveLocalFirstStorage {
  _ThrowingQueryHiveStorage({
    super.customPath,
    super.namespace,
    super.hive,
    super.initFlutter,
  });

  @override
  Future<List<Map<String, dynamic>>> query(LocalFirstQuery query) {
    throw Exception('query failed');
  }
}
