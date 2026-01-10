// ignore_for_file: override_on_non_overriding_member

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

class _TestModel {
  _TestModel(this.id, {this.value});
  final String id;
  final String? value;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (value != null) 'value': value,
  };

  factory _TestModel.fromJson(Map<String, dynamic> json) =>
      _TestModel(json['id'] as String, value: json['value'] as String?);
}

class _InMemoryStorage implements LocalFirstStorage {
  final Map<String, Map<String, Map<String, dynamic>>> tables = {};
  final Map<String, String> meta = {};
  final Map<String, StreamController<List<Map<String, dynamic>>>> _controllers =
      {};
  bool initialized = false;

  StreamController<List<Map<String, dynamic>>> _controller(String name) {
    return _controllers.putIfAbsent(
      name,
      () => StreamController<List<Map<String, dynamic>>>.broadcast(),
    );
  }

  Future<void> _emit(String tableName) async {
    final controller = _controller(tableName);
    if (controller.isClosed) return;
    controller.add(await getAll(tableName));
  }

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> close() async {
    initialized = false;
    for (final controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();
  }

  @override
  Future<void> clearAllData() async {
    tables.clear();
    meta.clear();
    for (final controller in _controllers.values) {
      if (!controller.isClosed) {
        controller.add([]);
      }
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getAll(String tableName) async {
    return tables[tableName]?.values.map((e) => Map.of(e)).toList() ?? [];
  }

  @override
  Future<Map<String, dynamic>?> getById(String tableName, String id) async {
    return tables[tableName]?[id];
  }

  @override
  Future<void> insert(
    String tableName,
    Map<String, dynamic> item,
    String idField,
  ) async {
    tables.putIfAbsent(tableName, () => {});
    tables[tableName]![item[idField] as String] = item;
    await _emit(tableName);
  }

  @override
  Future<void> update(
    String tableName,
    String id,
    Map<String, dynamic> item,
  ) async {
    tables.putIfAbsent(tableName, () => {});
    tables[tableName]![id] = item;
    await _emit(tableName);
  }

  @override
  Future<void> delete(String repositoryName, String id) async {
    tables[repositoryName]?.remove(id);
    await _emit(repositoryName);
  }

  @override
  Future<void> deleteAll(String tableName) async {
    tables[tableName]?.clear();
    await _emit(tableName);
  }

  String _eventsTable(String name) => '${name}__events';

  @override
  Future<List<Map<String, dynamic>>> getAllEvents(String tableName) {
    return getAll(_eventsTable(tableName));
  }

  @override
  Future<Map<String, dynamic>?> getEventById(
    String tableName,
    String id,
  ) {
    return getById(_eventsTable(tableName), id);
  }

  @override
  Future<void> insertEvent(
    String tableName,
    Map<String, dynamic> item,
    String idField,
  ) async {
    await insert(_eventsTable(tableName), item, idField);
  }

  @override
  Future<void> updateEvent(
    String tableName,
    String id,
    Map<String, dynamic> item,
  ) async {
    await update(_eventsTable(tableName), id, item);
  }

  @override
  Future<void> deleteEvent(String repositoryName, String id) async {
    await delete(_eventsTable(repositoryName), id);
  }

  @override
  Future<void> deleteAllEvents(String tableName) async {
    await deleteAll(_eventsTable(tableName));
  }

  @override
  Future<DateTime?> getLastSyncAt(String repositoryName) async => null;

  @override
  Future<void> setLastSyncAt(String repositoryName, DateTime time) async {}

  @override
  Future<void> setMeta(String key, String value) async {
    meta[key] = value;
  }

  @override
  Future<String?> getMeta(String key) async => meta[key];

  @override
  Future<void> ensureSchema(
    String tableName,
    Map<String, LocalFieldType> schema, {
    required String idFieldName,
  }) async {}

  @override
  Future<List<Map<String, dynamic>>> query(LocalFirstQuery query) async {
    return getAll(query.repositoryName);
  }

  @override
  Stream<List<Map<String, dynamic>>> watchQuery(LocalFirstQuery query) async* {
    final controller = _controller(query.repositoryName);
    controller.onListen = () async {
      controller.add(await getAll(query.repositoryName));
    };
    yield* controller.stream;
  }
}

class _NoopStrategy extends DataSyncStrategy {
  @override
  Future<SyncStatus> onPushToRemote(LocalFirstEvent localData) async {
    return SyncStatus.ok;
  }
}

class _FailingStrategy extends DataSyncStrategy {
  @override
  Future<SyncStatus> onPushToRemote(LocalFirstEvent localData) async {
    return SyncStatus.failed;
  }
}

class _ConditionalStrategy extends DataSyncStrategy {
  @override
  Future<SyncStatus> onPushToRemote(LocalFirstEvent localData) async {
    if (localData.state is _TestModel &&
        (localData.state as _TestModel).id == 'fail-push') {
      throw Exception('push failed');
    }
    return SyncStatus.ok;
  }
}

LocalFirstEvent<_TestModel> _event(
  String id, {
  String? value,
  SyncStatus status = SyncStatus.ok,
  SyncOperation operation = SyncOperation.insert,
  DateTime? createdAt,
}) {
  return LocalFirstEvent<_TestModel>(
    state: _TestModel(id, value: value),
    syncStatus: status,
    syncOperation: operation,
    syncCreatedAt: createdAt,
  );
}

void main() {
  group('LocalFirstRepository', () {
    late _InMemoryStorage storage;
    late LocalFirstClient client;
    late LocalFirstRepository<_TestModel> repo;

    setUp(() async {
      storage = _InMemoryStorage();
      repo = LocalFirstRepository<_TestModel>.create(
        name: 'tests',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: _TestModel.fromJson,
        onConflict: (l, r) => l,
      );
      client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        syncStrategies: [_NoopStrategy()],
      );
      await client.initialize();
    });

    test('initialize can be re-run after reset without errors', () async {
      repo.reset();
      await repo.initialize();
      await repo.upsert(_event('reinit', value: 'ok'), needSync: true);
      final stored = await storage.getById('tests', 'reinit');
      expect(stored, isNotNull);
    });

    test('insert sets sync metadata and persists', () async {
      final model = _event('1', value: 'a');
      await repo.upsert(model, needSync: true);

      final stored = await storage.getById('tests', '1');
      expect(stored, isNotNull);
      expect(stored!['_sync_status'], SyncStatus.ok.index);
      expect(stored['_sync_operation'], SyncOperation.insert.index);
      expect(
        stored['_sync_created_at'] is int &&
            DateTime.fromMillisecondsSinceEpoch(
              stored['_sync_created_at'] as int,
              isUtc: true,
            ).isBefore(DateTime.now().toUtc().add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('delete removes state row and logs delete event', () async {
      final model = _event('1', value: 'a');
      await repo.upsert(model, needSync: true);

      await repo.delete('1', needSync: true);

      final storedState = await storage.getById('tests', '1');
      expect(storedState, isNull);
      final events = await storage.getAllEvents('tests');
      expect(events, isNotEmpty);
      final deleteEvent =
          events.firstWhere((e) => e['_sync_operation'] == SyncOperation.delete.index);
      expect(deleteEvent['_sync_status'], SyncStatus.pending.index);
      expect(deleteEvent['id'], '1');
    });

    test('delete returns silently when item not found', () async {
      await repo.delete('missing-id', needSync: true);
      final stored = await storage.getById('tests', 'missing-id');
      expect(stored, isNull);
    });

    test(
      '_updateObjectStatus persists last sync status from failing strategy',
      () async {
        final failingStorage = _InMemoryStorage();
        final failingRepo = LocalFirstRepository<_TestModel>.create(
          name: 'tests',
          getId: (m) => m.id,
          toJson: (m) => m.toJson(),
          fromJson: _TestModel.fromJson,
          onConflict: (l, r) => l,
        );
        final failingClient = LocalFirstClient(
          repositories: [failingRepo],
          localStorage: failingStorage,
          syncStrategies: [_FailingStrategy()],
        );
        await failingClient.initialize();

        await failingRepo.upsert(_event('fail', value: 'x'), needSync: true);

        final stored = await failingStorage.getById('tests', 'fail');
        expect(stored?['_sync_status'], SyncStatus.failed.index);
        expect(stored?['_sync_operation'], SyncOperation.insert.index);
      },
    );

    test('_pushLocalObject failure does not affect subsequent items', () async {
      final conditionalStorage = _InMemoryStorage();
      final conditionalRepo = LocalFirstRepository<_TestModel>.create(
        name: 'tests',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: _TestModel.fromJson,
        onConflict: (l, r) => l,
      );
      final conditionalClient = LocalFirstClient(
        repositories: [conditionalRepo],
        localStorage: conditionalStorage,
        syncStrategies: [_ConditionalStrategy()],
      );
      await conditionalClient.initialize();

      await conditionalRepo.upsert(_event('fail-push', value: 'x'),
          needSync: true);
      await conditionalRepo.upsert(_event('ok-push', value: 'y'),
          needSync: true);

      final failed = await conditionalStorage.getById('tests', 'fail-push');
      final ok = await conditionalStorage.getById('tests', 'ok-push');

      expect(failed?['_sync_status'], SyncStatus.failed.index);
      expect(failed?['_sync_operation'], SyncOperation.insert.index);

      expect(ok?['_sync_status'], isNot(SyncStatus.failed.index));
      expect(ok?['_sync_operation'], SyncOperation.insert.index);
    });

    test('query returns mapped models with sync metadata', () async {
      final createdAt = DateTime.now().toUtc().millisecondsSinceEpoch;
      await storage.insert('tests', {
        'id': '10',
        'value': 'v',
        '_sync_status': SyncStatus.ok.index,
        '_sync_operation': SyncOperation.insert.index,
        '_sync_created_at': createdAt,
      }, 'id');

      final results = await repo.query().getAll();
      expect(results.length, 1);
      expect(results.first.state.id, '10');
      expect(results.first.syncStatus, SyncStatus.ok);
      expect(results.first.syncOperation, SyncOperation.insert);
      expect(results.first.syncCreatedAt.millisecondsSinceEpoch, createdAt);
    });

    test('getPendingEvents returns only pending items', () async {
      await storage.insert('tests', {
        'id': 'p1',
        'value': 'pending',
        '_sync_status': SyncStatus.pending.index,
        '_sync_operation': SyncOperation.insert.index,
        '_sync_created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      }, 'id');
      await storage.insert('tests', {
        'id': 'ok1',
        'value': 'ok',
        '_sync_status': SyncStatus.ok.index,
        '_sync_operation': SyncOperation.insert.index,
        '_sync_created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      }, 'id');

      final pending = await repo.getPendingEvents();
      expect(pending.map((e) => e.state.id), contains('p1'));
      expect(pending.any((e) => e.state.id == 'ok1'), isFalse);
    });

    test(
      'upsert keeps insert operation for existing pending inserts',
      () async {
        await storage.insert('tests', {
          'id': 'ins',
          'value': 'old',
          '_sync_status': SyncStatus.pending.index,
          '_sync_operation': SyncOperation.insert.index,
          '_sync_created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        }, 'id');

        await repo.upsert(_event('ins', value: 'new'), needSync: true);

        final stored = await storage.getById('tests', 'ins');
        expect(stored!['_sync_operation'], SyncOperation.insert.index);
        expect(stored['_sync_status'], SyncStatus.ok.index);
        expect(stored['value'], 'new');
      },
    );

    test('resolveConflict uses provided resolver', () {
      final local = _TestModel('1', value: 'local');
      final remote = _TestModel('1', value: 'remote');

      final resolved = repo.resolveConflict(local, remote);

      expect(resolved.value, 'local'); // onConflict returns local
    });

    test('resolveConflict can prefer remote when resolver defines so', () {
      final remoteFirstRepo = LocalFirstRepository<_TestModel>.create(
        name: 'tests',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: _TestModel.fromJson,
        onConflict: (l, r) => r,
      );

      final resolved = remoteFirstRepo.resolveConflict(
        _TestModel('1', value: 'local'),
        _TestModel('1', value: 'remote'),
      );

      expect(resolved.value, 'remote');
    });

    test('resolveConflict surfaces resolver exceptions', () {
      final throwingRepo = LocalFirstRepository<_TestModel>.create(
        name: 'tests',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: _TestModel.fromJson,
        onConflict: (l, r) => throw Exception('resolver failed'),
      );

      expect(
        () => throwingRepo.resolveConflict(
          _TestModel('1', value: 'a'),
          _TestModel('1', value: 'b'),
        ),
        throwsException,
      );
    });

    test('upsert on synced item marks update pending', () async {
      await storage.insert('tests', {
        'id': 'synced',
        'value': 'old',
        '_sync_status': SyncStatus.ok.index,
        '_sync_operation': SyncOperation.insert.index,
        '_sync_created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      }, 'id');

      await repo.upsert(_event('synced', value: 'new'), needSync: true);

      final stored = await storage.getById('tests', 'synced');
      expect(stored?['_sync_operation'], SyncOperation.update.index);
      expect(stored?['_sync_status'], SyncStatus.ok.index);
      expect(stored?['value'], 'new');
    });

    test(
      'upsert preserves pending insert operation for unsynced records',
      () async {
        final createdAt = DateTime.now().toUtc().millisecondsSinceEpoch;
        await storage.insert('tests', {
          'id': 'pending',
          'value': 'v1',
          '_sync_status': SyncStatus.pending.index,
          '_sync_operation': SyncOperation.insert.index,
          '_sync_created_at': createdAt,
        }, 'id');

        await repo.upsert(_event('pending', value: 'v2'), needSync: true);

        final stored = await storage.getById('tests', 'pending');
        expect(stored?['_sync_operation'], SyncOperation.insert.index);
        expect(stored?['_sync_status'], SyncStatus.ok.index);
        expect(stored?['_sync_created_at'], createdAt);
        expect(stored?['value'], 'v2');
      },
    );

    test('upsert converts synced insert record to update', () async {
      final createdAt = DateTime.now().toUtc().millisecondsSinceEpoch;
      await storage.insert('tests', {
        'id': 'syncedInsert',
        'value': 'old',
        '_sync_status': SyncStatus.ok.index,
        '_sync_operation': SyncOperation.insert.index,
        '_sync_created_at': createdAt,
      }, 'id');

      await repo.upsert(_event('syncedInsert', value: 'new'), needSync: true);

      final stored = await storage.getById('tests', 'syncedInsert');
      expect(stored?['_sync_operation'], SyncOperation.update.index);
      expect(stored?['_sync_status'], SyncStatus.ok.index);
      expect(stored?['_sync_created_at'], createdAt);
      expect(stored?['value'], 'new');
    });

    test(
      'upsert generates sync_created_at when missing on existing synced item',
      () async {
        await storage.insert('tests', {
          'id': 'legacy',
          'value': 'old',
          '_sync_status': SyncStatus.ok.index,
          '_sync_operation': SyncOperation.insert.index,
          // intentionally omit _sync_created_at to simulate legacy data
        }, 'id');

        await repo.upsert(_event('legacy', value: 'new'), needSync: true);

        final stored = await storage.getById('tests', 'legacy');
        expect(stored?['_sync_operation'], SyncOperation.update.index);
        expect(stored?['_sync_status'], SyncStatus.ok.index);
        expect(stored?['_sync_created_at'], isNotNull);
        final createdAt = stored?['_sync_created_at'] as int;
        final createdAtDate = DateTime.fromMillisecondsSinceEpoch(
          createdAt,
          isUtc: true,
        );
        expect(
          createdAtDate.isAfter(
            DateTime.now().toUtc().subtract(const Duration(seconds: 2)),
          ),
          isTrue,
        );
        expect(stored?['value'], 'new');
      },
    );

    test('pullChangesToLocal inserts remote objects', () async {
      final strategy = client.syncStrategies.first;
      final payload = {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'changes': {
          'tests': {
            'insert': [
              {'id': 'r1', 'value': 'remote'},
            ],
          },
        },
      };

      await strategy.pullChangesToLocal(payload);

      final stored = await storage.getById('tests', 'r1');
      expect(stored?['value'], 'remote');
      expect(stored?['_sync_status'], SyncStatus.ok.index);
      expect(stored?['_sync_operation'], SyncOperation.insert.index);
    });

    test('pullChangesToLocal updates existing object via resolver', () async {
      await storage.insert('tests', {
        'id': 'u1',
        'value': 'local',
        '_sync_status': SyncStatus.ok.index,
        '_sync_operation': SyncOperation.insert.index,
        '_sync_created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      }, 'id');

      final strategy = client.syncStrategies.first;
      final payload = {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'changes': {
          'tests': {
            'update': [
              {'id': 'u1', 'value': 'remote'},
            ],
          },
        },
      };

      await strategy.pullChangesToLocal(payload);

      final stored = await storage.getById('tests', 'u1');
      expect(stored?['value'], 'local'); // resolver keeps local
      expect(stored?['_sync_status'], SyncStatus.ok.index);
      expect(stored?['_sync_operation'], SyncOperation.update.index);
    });

    test(
      'pullChangesToLocal deletes when remote marks deleted and local clean',
      () async {
        await storage.insert('tests', {
          'id': 'd1',
          'value': 'keep?',
          '_sync_status': SyncStatus.ok.index,
          '_sync_operation': SyncOperation.insert.index,
          '_sync_created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        }, 'id');

        final strategy = client.syncStrategies.first;
        final payload = {
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'changes': {
            'tests': {
              'delete': ['d1'],
            },
          },
        };

        await strategy.pullChangesToLocal(payload);

        final stored = await storage.getById('tests', 'd1');
        expect(stored, isNull);
      },
    );

    test(
      'pullChangesToLocal keeps pending local insert when remote deletes',
      () async {
        await storage.insert('tests', {
          'id': 'd2',
          'value': 'pending',
          '_sync_status': SyncStatus.pending.index,
          '_sync_operation': SyncOperation.insert.index,
          '_sync_created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        }, 'id');

        final strategy = client.syncStrategies.first;
        final payload = {
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'changes': {
            'tests': {
              'delete': ['d2'],
            },
          },
        };

        await strategy.pullChangesToLocal(payload);

        final stored = await storage.getById('tests', 'd2');
        expect(stored, isNotNull); // should not be deleted
        expect(stored?['_sync_status'], SyncStatus.pending.index);
        expect(stored?['_sync_operation'], SyncOperation.insert.index);
        expect(stored?['value'], 'pending');
      },
    );

    test(
      'pullChangesToLocal ignores delete when item not found locally',
      () async {
        final strategy = client.syncStrategies.first;
        final payload = {
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'changes': {
            'tests': {
              'delete': ['missing'],
            },
          },
        };

        await strategy.pullChangesToLocal(payload);

        final stored = await storage.getById('tests', 'missing');
        expect(stored, isNull);
      },
    );

    test(
      'pullChangesToLocal sets sync_created_at when missing on existing local during update',
      () async {
        await storage.insert('tests', {
          'id': 'legacy-update',
          'value': 'local',
          '_sync_status': SyncStatus.ok.index,
          '_sync_operation': SyncOperation.insert.index,
          // no _sync_created_at to simulate legacy data
        }, 'id');

        final strategy = client.syncStrategies.first;
        final payload = {
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'changes': {
            'tests': {
              'update': [
                {'id': 'legacy-update', 'value': 'remote'},
              ],
            },
          },
        };

        await strategy.pullChangesToLocal(payload);

        final stored = await storage.getById('tests', 'legacy-update');
        expect(stored?['_sync_created_at'], isNotNull);
        final createdAt = DateTime.fromMillisecondsSinceEpoch(
          stored?['_sync_created_at'] as int,
          isUtc: true,
        );
        expect(
          createdAt.isAfter(
            DateTime.now().toUtc().subtract(const Duration(seconds: 2)),
          ),
          isTrue,
        );
        // onConflict keeps local value
        expect(stored?['value'], 'local');
        expect(stored?['_sync_operation'], SyncOperation.update.index);
        expect(stored?['_sync_status'], SyncStatus.ok.index);
      },
    );

    test('query().watch streams updates', () async {
      final eventsFuture = repo
          .query()
          .watch()
          .take(2)
          .toList()
          .timeout(const Duration(seconds: 5));

      await storage.insert('tests', {
        'id': 'w1',
        'value': 'watch',
        '_sync_status': SyncStatus.ok.index,
        '_sync_operation': SyncOperation.insert.index,
        '_sync_created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      }, 'id');

      await Future<void>.delayed(Duration.zero);
      final events = await eventsFuture;
      expect(events.length, 2);
      expect(events[1].any((m) => m.state.id == 'w1'), isTrue);
    });
  });
}
