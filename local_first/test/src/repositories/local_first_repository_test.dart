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

class _OtherModel {
  _OtherModel(this.id);
  final String id;

  Map<String, dynamic> toJson() => {'id': id};
}

class _ConfigurableRepo with LocalFirstRepository<_TestModel> {
  void configure({String name = 'tests'}) {
    initLocalFirstRepository(
      name: name,
      getId: (model) => model.id,
      toJson: (model) => model.toJson(),
      fromJson: _TestModel.fromJson,
      onConflict: (local, remote) => local,
    );
  }
}

class _InMemoryStorage implements LocalFirstStorage {
  final Map<String, Map<String, Map<String, dynamic>>> tables = {};
  final Map<String, String> meta = {};
  final Map<String, DateTime> registeredEvents = {};
  final Map<String, StreamController<List<Map<String, dynamic>>>> _controllers =
      {};
  bool initialized = false;
  bool opened = false;

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
  Future<void> open({String namespace = 'default'}) async {
    opened = true;
  }

  @override
  bool get isOpened => opened;

  @override
  bool get isClosed => !opened;

  @override
  String get currentNamespace => 'default';

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> close() async {
    opened = false;
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

  @override
  Future<DateTime?> getLastSyncAt(String repositoryName) async => null;

  @override
  Future<void> setLastSyncAt(String repositoryName, DateTime time) async {}

  @override
  Future<void> setMeta(String key, String value) async {
    meta[key] = value;
  }

  @override
  Future<void> registerEvent(String eventId, DateTime createdAt) async {
    registeredEvents.putIfAbsent(eventId, () => createdAt.toUtc());
  }

  @override
  Future<bool> isEventRegistered(String eventId) async {
    return registeredEvents.containsKey(eventId);
  }

  @override
  Future<void> pruneRegisteredEvents(DateTime before) async {
    final threshold = before.toUtc();
    registeredEvents.removeWhere((_, value) => value.isBefore(threshold));
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

class _InMemoryKeyValueStorage implements LocalFirstKeyValueStorage {
  final Map<String, Object?> _store = {};
  bool _opened = false;
  String _namespace = 'default';

  @override
  bool get isOpened => _opened;

  @override
  bool get isClosed => !_opened;

  @override
  String get currentNamespace => _namespace;

  @override
  Future<void> open({String namespace = 'default'}) async {
    _namespace = namespace;
    _opened = true;
  }

  @override
  Future<void> close() async {
    _opened = false;
  }

  @override
  Future<void> set<T>(String key, T value) async {
    _ensureOpen();
    _store[_namespaced(key)] = value;
  }

  @override
  Future<T?> get<T>(String key) async {
    _ensureOpen();
    final value = _store[_namespaced(key)];
    return value is T ? value : null;
  }

  @override
  Future<bool> contains(String key) async {
    _ensureOpen();
    return _store.containsKey(_namespaced(key));
  }

  @override
  Future<void> delete(String key) async {
    _ensureOpen();
    _store.remove(_namespaced(key));
  }

  void _ensureOpen() {
    if (!_opened) {
      throw StateError('KeyValueStorage not open');
    }
  }

  String _namespaced(String key) => '${_namespace}__$key';
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
    if (localData.isA<_TestModel>() &&
        localData.dataAs<_TestModel>().id == 'fail-push') {
      throw Exception('push failed');
    }
    return SyncStatus.ok;
  }
}

class _TypedOtherStrategy extends DataSyncStrategy<_OtherModel> {
  int callCount = 0;

  @override
  Future<SyncStatus> onPushToRemote(LocalFirstEvent localData) async {
    callCount += 1;
    return SyncStatus.ok;
  }
}

void main() {
  group('LocalFirstRepository', () {
    late _InMemoryStorage storage;
    late LocalFirstClient client;
    late LocalFirstRepository<_TestModel> repo;

    setUp(() async {
      storage = _InMemoryStorage();
      final metaStorage = _InMemoryKeyValueStorage();
      repo = LocalFirstRepository.create<_TestModel>(
        name: 'tests',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: _TestModel.fromJson,
        onConflict: (l, r) => l,
      );
      client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        metaStorage: metaStorage,
        syncStrategies: [_NoopStrategy()],
      );
      await client.initialize();
    });

    test('initLocalFirstRepository throws when already configured', () {
      final repo = _ConfigurableRepo();
      repo.configure(name: 'first');
      expect(
        () => repo.configure(name: 'second'),
        throwsA(isA<StateError>()),
      );
    });

    test('initialize can be re-run after reset without errors', () async {
      repo.reset();
      await repo.initialize();
      await repo.upsert(_TestModel('reinit', value: 'ok'));
      final stored = await storage.getById('tests', 'reinit');
      expect(stored, isNotNull);
    });

    test('insert sets sync metadata and persists', () async {
      final model = _TestModel('1', value: 'a');
      await repo.upsert(model);

      final stored = await storage.getById('tests', '1');
      expect(stored, isNotNull);
      expect(stored!['_sync_status'], SyncStatus.pending.index);
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

    test('delete marks as pending delete when previously synced', () async {
      final model = _TestModel('1', value: 'a');
      await repo.upsert(model);
      // Simulate synced
      await storage.update('tests', '1', {
        ...model.toJson(),
        '_sync_status': SyncStatus.ok.index,
        '_sync_operation': SyncOperation.insert.index,
        '_sync_created_at': DateTime.now().millisecondsSinceEpoch,
      });

      await repo.delete('1');
      final stored = await storage.getById('tests', '1');
      expect(stored!['_sync_operation'], SyncOperation.delete.index);
      expect(stored['_sync_status'], SyncStatus.pending.index);
    });

    test('typed sync strategy ignores unrelated model types', () async {
      final typedStrategy = _TypedOtherStrategy();
      final typedStorage = _InMemoryStorage();
      final typedRepo = LocalFirstRepository.create<_TestModel>(
        name: 'typed_tests',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: _TestModel.fromJson,
        onConflict: (l, r) => l,
      );
      final typedClient = LocalFirstClient(
        repositories: [typedRepo],
        localStorage: typedStorage,
        metaStorage: _InMemoryKeyValueStorage(),
        syncStrategies: [typedStrategy],
      );
      await typedClient.initialize();

      await typedRepo.upsert(_TestModel('typed'));

      expect(typedStrategy.callCount, 0);
    });

    test('delete removes unsynced insert', () async {
      final model = _TestModel('del', value: 'temp');
      await repo.upsert(model);

      await repo.delete('del');

      final stored = await storage.getById('tests', 'del');
      expect(stored, isNull);
    });

    test('delete returns silently when item not found', () async {
      await repo.delete('missing-id');
      final stored = await storage.getById('tests', 'missing-id');
      expect(stored, isNull);
    });

    test(
      '_updateEventStatus persists last sync status from failing strategy',
      () async {
        final failingStorage = _InMemoryStorage();
        final failingRepo = LocalFirstRepository.create<_TestModel>(
          name: 'tests',
          getId: (m) => m.id,
          toJson: (m) => m.toJson(),
          fromJson: _TestModel.fromJson,
          onConflict: (l, r) => l,
        );
        final failingClient = LocalFirstClient(
          repositories: [failingRepo],
          localStorage: failingStorage,
          metaStorage: _InMemoryKeyValueStorage(),
          syncStrategies: [_FailingStrategy()],
        );
        await failingClient.initialize();

        await failingRepo.upsert(_TestModel('fail', value: 'x'));

        final stored = await failingStorage.getById('tests', 'fail');
        expect(stored?['_sync_status'], SyncStatus.failed.index);
        expect(stored?['_sync_operation'], SyncOperation.insert.index);
      },
    );

    test('_pushLocalEvent failure does not affect subsequent items', () async {
      final conditionalStorage = _InMemoryStorage();
      final conditionalRepo = LocalFirstRepository.create<_TestModel>(
        name: 'tests',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: _TestModel.fromJson,
        onConflict: (l, r) => l,
      );
      final conditionalClient = LocalFirstClient(
        repositories: [conditionalRepo],
        localStorage: conditionalStorage,
        metaStorage: _InMemoryKeyValueStorage(),
        syncStrategies: [_ConditionalStrategy()],
      );
      await conditionalClient.initialize();

      await conditionalRepo.upsert(_TestModel('fail-push', value: 'x'));
      await conditionalRepo.upsert(_TestModel('ok-push', value: 'y'));

      final failed = await conditionalStorage.getById('tests', 'fail-push');
      final ok = await conditionalStorage.getById('tests', 'ok-push');

      expect(failed?['_sync_status'], SyncStatus.failed.index);
      expect(failed?['_sync_operation'], SyncOperation.insert.index);

      expect(ok?['_sync_status'], isNot(SyncStatus.failed.index));
      expect(ok?['_sync_operation'], SyncOperation.insert.index);
    });

    test('query returns mapped models', () async {
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
      expect(results.first.id, '10');
    });

    test('getPendingObjects returns only pending items', () async {
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

      final pending = await repo.getPendingObjects();
      expect(
        pending.map((e) => e.dataAs<_TestModel>().id),
        contains('p1'),
      );
      expect(
        pending.any((e) => e.dataAs<_TestModel>().id == 'ok1'),
        isFalse,
      );
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

        await repo.upsert(_TestModel('ins', value: 'new'));

        final stored = await storage.getById('tests', 'ins');
        expect(stored!['_sync_operation'], SyncOperation.insert.index);
        expect(stored['_sync_status'], SyncStatus.pending.index);
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
      final remoteFirstRepo = LocalFirstRepository.create<_TestModel>(
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
      final throwingRepo = LocalFirstRepository.create<_TestModel>(
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

      await repo.upsert(_TestModel('synced', value: 'new'));

      final stored = await storage.getById('tests', 'synced');
      expect(stored?['_sync_operation'], SyncOperation.update.index);
      expect(stored?['_sync_status'], SyncStatus.pending.index);
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

        await repo.upsert(_TestModel('pending', value: 'v2'));

        final stored = await storage.getById('tests', 'pending');
        expect(stored?['_sync_operation'], SyncOperation.insert.index);
        expect(stored?['_sync_status'], SyncStatus.pending.index);
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

      await repo.upsert(_TestModel('syncedInsert', value: 'new'));

      final stored = await storage.getById('tests', 'syncedInsert');
      expect(stored?['_sync_operation'], SyncOperation.update.index);
      expect(stored?['_sync_status'], SyncStatus.pending.index);
      expect(
        stored?['_sync_created_at'],
        greaterThanOrEqualTo(createdAt),
      );
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

        await repo.upsert(_TestModel('legacy', value: 'new'));

        final stored = await storage.getById('tests', 'legacy');
        expect(stored?['_sync_operation'], SyncOperation.update.index);
        expect(stored?['_sync_status'], SyncStatus.pending.index);
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
      final eventId = LocalFirstEvent.generateEventId();
      final payload = {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'changes': {
          'tests': {
            'insert': [
              {'id': 'r1', 'value': 'remote', 'event_id': eventId},
            ],
          },
        },
      };

      await strategy.pullChangesToLocal(payload);

      final stored = await storage.getById('tests', 'r1');
      expect(stored?['value'], 'remote');
      expect(stored?['_sync_status'], SyncStatus.ok.index);
      expect(stored?['_sync_operation'], SyncOperation.insert.index);
      expect(stored?['_event_id'], eventId);
      expect(await storage.isEventRegistered(eventId), isTrue);
    });

    test('pullChangesToLocal generates event_id when missing', () async {
      final strategy = client.syncStrategies.first;
      final payload = {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'changes': {
          'tests': {
            'insert': [
              {'id': 'r2', 'value': 'remote'},
            ],
          },
        },
      };

      await strategy.pullChangesToLocal(payload);

      final stored = await storage.getById('tests', 'r2');
      final storedEventId = stored?['_event_id'];
      expect(storedEventId, isA<String>());
      expect((storedEventId as String).isNotEmpty, isTrue);
      expect(await storage.isEventRegistered(storedEventId), isTrue);
    });

    test('pullChangesToLocal sets sync_created_at when missing', () async {
      final strategy = client.syncStrategies.first;
      final payload = {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'changes': {
          'tests': {
            'insert': [
              {'id': 'r3', 'value': 'remote'},
            ],
          },
        },
      };

      await strategy.pullChangesToLocal(payload);

      final stored = await storage.getById('tests', 'r3');
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
      final eventId = LocalFirstEvent.generateEventId();
      final payload = {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'changes': {
          'tests': {
            'update': [
              {'id': 'u1', 'value': 'remote', 'event_id': eventId},
            ],
          },
        },
      };

      await strategy.pullChangesToLocal(payload);

      final stored = await storage.getById('tests', 'u1');
      expect(stored?['value'], 'local'); // resolver keeps local
      expect(stored?['_sync_status'], SyncStatus.ok.index);
      expect(stored?['_sync_operation'], SyncOperation.update.index);
      expect(stored?['_event_id'], eventId);
      expect(await storage.isEventRegistered(eventId), isTrue);
    });

    test(
      'pullChangesToLocal ignores event already registered when local is synced',
      () async {
        await storage.insert('tests', {
          'id': 'dupe-synced',
          'value': 'local',
          '_sync_status': SyncStatus.ok.index,
          '_sync_operation': SyncOperation.insert.index,
          '_sync_created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        }, 'id');

        final eventId = LocalFirstEvent.generateEventId();
        await storage.registerEvent(eventId, DateTime.now().toUtc());

        final strategy = client.syncStrategies.first;
        final payload = {
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'changes': {
            'tests': {
              'update': [
                {'id': 'dupe-synced', 'value': 'remote', 'event_id': eventId},
              ],
            },
          },
        };

        await strategy.pullChangesToLocal(payload);

        final stored = await storage.getById('tests', 'dupe-synced');
        expect(stored?['value'], 'local');
        expect(stored?['_sync_status'], SyncStatus.ok.index);
        expect(stored?['_sync_operation'], SyncOperation.insert.index);
      },
    );

    test(
      'pullChangesToLocal ignores event already registered when local is pending',
      () async {
        await storage.insert('tests', {
          'id': 'dupe-pending',
          'value': 'pending',
          '_sync_status': SyncStatus.pending.index,
          '_sync_operation': SyncOperation.insert.index,
          '_sync_created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        }, 'id');

        final eventId = LocalFirstEvent.generateEventId();
        await storage.registerEvent(eventId, DateTime.now().toUtc());

        final strategy = client.syncStrategies.first;
        final payload = {
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'changes': {
            'tests': {
              'update': [
                {'id': 'dupe-pending', 'value': 'remote', 'event_id': eventId},
              ],
            },
          },
        };

        await strategy.pullChangesToLocal(payload);

        final stored = await storage.getById('tests', 'dupe-pending');
        expect(stored?['value'], 'pending');
        expect(stored?['_sync_status'], SyncStatus.pending.index);
        expect(stored?['_sync_operation'], SyncOperation.insert.index);
      },
    );

    test(
      'pullChangesToLocal ignores event already registered when item missing',
      () async {
        final eventId = LocalFirstEvent.generateEventId();
        await storage.registerEvent(eventId, DateTime.now().toUtc());

        final strategy = client.syncStrategies.first;
        final payload = {
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'changes': {
            'tests': {
              'insert': [
                {'id': 'dupe-missing', 'value': 'remote', 'event_id': eventId},
              ],
            },
          },
        };

        await strategy.pullChangesToLocal(payload);

        final stored = await storage.getById('tests', 'dupe-missing');
        expect(stored, isNull);
      },
    );

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
      expect(events[1].any((m) => m.id == 'w1'), isTrue);
    });
  });
}
