import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
        await storage.insert(table, {
          ...event.toJson(),
          '_last_event_id': event.eventId,
        }, 'id');
      }
      await storage.insertEvent(table, event.toLocalStorageJson(), '_event_id');
    }

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
            needSync: true,
          ),
        );
        await seedEvent(
          table: 'users',
          event: LocalFirstEvent.createNewDeleteEvent<_TestModel>(
            repository: buildRepo(),
            dataId: '1',
            needSync: true,
          ),
        );

        final events = await storage.query(buildQuery());
        expect(events.where((e) => e.needSync), isEmpty);
        expect(events.where((e) => e.isDeleted), isEmpty);
      },
    );

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

    test('watchQuery emits on data and event changes', () async {
      final repo = buildRepo();
      final query = buildQuery();
      final stream = storage.watchQuery(query);
      final emitted = <List<LocalFirstEvent<_TestModel>>>[];
      final sub = stream.listen(emitted.add);

      await seedEvent(
        table: 'users',
        event: LocalFirstEvent.createNewInsertEvent<_TestModel>(
          repository: repo,
          data: _TestModel('1', username: 'alice'),
          needSync: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await storage.updateEvent('users', 'evt-1', {
        '_event_id': 'evt-1',
        '_data_id': '1',
        '_sync_status': SyncStatus.ok.index,
        '_sync_operation': SyncOperation.insert.index,
        '_sync_created_at': DateTime.now().millisecondsSinceEpoch,
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      expect(emitted, isNotEmpty);
    });

    test('containsId checks presence in box', () async {
      await storage.insert('users', {'id': '1', 'name': 'Alice'}, 'id');
      expect(await storage.containsId('users', '1'), isTrue);
      expect(await storage.containsId('users', 'missing'), isFalse);
    });
  });
}
