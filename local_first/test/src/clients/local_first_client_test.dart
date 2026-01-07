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

class _OkStrategy extends DataSyncStrategy {
  @override
  Future<SyncStatus> onPushToRemote(LocalFirstEvent localData) async {
    return SyncStatus.ok;
  }
}

class _InitProbeRepo extends LocalFirstRepository<_TestModel> {
  _InitProbeRepo({
    required super.name,
    required super.getId,
    required super.toJson,
    required super.fromJson,
    required super.onConflict,
  });

  bool initialized = false;
  bool resetCalled = false;

  @override
  Future<void> initialize() async {
    initialized = true;
    await super.initialize();
  }

  @override
  void reset() {
    resetCalled = true;
    initialized = false;
    super.reset();
  }
}

class _InMemoryStorage implements LocalFirstStorage {
  bool initialized = false;
  bool closed = false;
  final Map<String, Map<String, Map<String, dynamic>>> tables = {};
  final Map<String, String> meta = {};
  final Map<String, StreamController<List<Map<String, dynamic>>>> _controllers =
      {};

  StreamController<List<Map<String, dynamic>>> _controller(String name) {
    return _controllers.putIfAbsent(
      name,
      () => StreamController<List<Map<String, dynamic>>>.broadcast(),
    );
  }

  Future<void> _emit(String tableName) async {
    if (_controllers[tableName]?.isClosed ?? true) return;
    _controller(tableName).add(await getAll(tableName));
  }

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> close() async {
    closed = true;
    for (final c in _controllers.values) {
      await c.close();
    }
  }

  @override
  Future<void> clearAllData() async {
    tables.clear();
    meta.clear();
    for (final c in _controllers.values) {
      if (!c.isClosed) c.add([]);
    }
  }

  @override
  Future<void> deleteAll(String tableName) async {
    tables[tableName]?.clear();
    await _emit(tableName);
  }

  @override
  Future<void> delete(String repositoryName, String id) async {
    tables[repositoryName]?.remove(id);
    await _emit(repositoryName);
  }

  @override
  Future<List<Map<String, dynamic>>> getAll(String tableName) async {
    return tables[tableName]?.values.map((e) => Map.of(e)).toList() ?? [];
  }

  @override
  Future<Map<String, dynamic>?> getById(String tableName, String id) async {
    return tables[tableName]?[id];
  }

  Future<DateTime?> getLastSyncAt(String repositoryName) async => null;

  @override
  Future<String?> getMeta(String key) async => meta[key];

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

  Future<void> setLastSyncAt(String repositoryName, DateTime time) async {}

  @override
  Future<void> setMeta(String key, String value) async {
    meta[key] = value;
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
  Future<List<Map<String, dynamic>>> query(LocalFirstQuery query) async {
    return getAll(query.repositoryName);
  }

  @override
  Stream<List<Map<String, dynamic>>> watchQuery(LocalFirstQuery query) {
    final controller = _controller(query.repositoryName);
    controller.addStream(Stream.value([]));
    return controller.stream;
  }

  @override
  Future<void> ensureSchema(
    String tableName,
    Map<String, LocalFieldType> schema, {
    required String idFieldName,
  }) async {
    return;
  }
}

void main() {
  group('LocalFirstClient', () {
    late _InMemoryStorage storage;
    late LocalFirstRepository<_TestModel> repo;
    late LocalFirstClient client;

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
        syncStrategies: [_OkStrategy()],
      );
    });

    test('initialize sets up storage and repositories', () async {
      await client.initialize();
      expect(storage.initialized, isTrue);
    });

    test('duplicate repository names throw ArgumentError', () {
      expect(
        () => LocalFirstClient(
          repositories: [repo, repo],
          localStorage: _InMemoryStorage(),
          syncStrategies: [_OkStrategy()],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('getRepositoryByName returns repo and throws when missing', () async {
      await client.initialize();
      expect(client.getRepositoryByName('tests'), equals(repo));
      expect(() => client.getRepositoryByName('missing'), throwsStateError);
    });

    test('clearAllData wipes storage and reinitializes repositories', () async {
      final probeRepo = _InitProbeRepo(
        name: 'probe',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: _TestModel.fromJson,
        onConflict: (l, r) => l,
      );
      final clientWithProbe = LocalFirstClient(
        repositories: [probeRepo],
        localStorage: storage,
        syncStrategies: [_OkStrategy()],
      );
      await clientWithProbe.initialize();
      await probeRepo.upsert(LocalFirstEvent(payload: _TestModel('1')));

      expect(await storage.getById('probe', '1'), isNotNull);
      expect(probeRepo.initialized, isTrue);

      await clientWithProbe.clearAllData();

      expect(await storage.getById('probe', '1'), isNull);
      expect(probeRepo.resetCalled, isTrue);
      expect(probeRepo.initialized, isTrue);
    });

    test('setKeyValue / getMeta delegates to storage', () async {
      await client.setKeyValue('k', 'v');
      expect(await client.getMeta('k'), 'v');
    });

    test('getAllPendingObjects aggregates pending from repositories', () async {
      await client.initialize();
      await storage.insert('tests', {
        'id': 'p1',
        'value': 'pending',
        '_sync_status': SyncStatus.pending.index,
        '_sync_operation': SyncOperation.insert.index,
        '_sync_created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      }, 'id');

      final pending = await client.getAllPendingObjects();
      expect(pending.length, 1);
      expect(pending.first.payload, isA<_TestModel>());
      expect(pending.first.payload.id, 'p1');
    });

    test('dispose closes storage', () async {
      await client.initialize();
      await client.dispose();
      expect(storage.closed, isTrue);
    });

    test('awaitInitialization completes only after initialize runs', () async {
      final completerOrder = <String>[];

      unawaited(
        client.awaitInitialization.then((_) {
          completerOrder.add('awaitInitialization');
        }),
      );

      // Ensure not completed before initialize
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(completerOrder, isEmpty);

      await client.initialize();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(completerOrder, contains('awaitInitialization'));
    });

    test(
      'pullChangesToLocal throws on invalid offline response format',
      () async {
        await client.initialize();
        final strategy = client.syncStrategies.first;
        final invalidPayloads = [
          <String, dynamic>{}, // missing everything
          <String, dynamic>{
            'timestamp': DateTime.now().toIso8601String(),
          }, // missing changes
          <String, dynamic>{
            'changes': <String, dynamic>{},
          }, // missing timestamp
        ];

        for (final payload in invalidPayloads) {
          expect(
            () => strategy.pullChangesToLocal(payload),
            throwsA(isA<FormatException>()),
          );
        }
      },
    );
  });
}
