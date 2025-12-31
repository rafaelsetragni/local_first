import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestModel {
  _TestModel(this.id, {this.value});
  final String id;
  final String? value;

  JsonMap toJson() => {'id': id, if (value != null) 'value': value};

  factory _TestModel.fromJson(JsonMap json) =>
      _TestModel(json['id'] as String, value: json['value'] as String?);
}

class _OkStrategy extends DataSyncStrategy {
  @override
  Future<SyncStatus> onPushToRemote(LocalFirstEvent localData) async {
    return SyncStatus.ok;
  }
}

class _InitProbeRepo with LocalFirstRepository<_TestModel> {
  _InitProbeRepo({
    required String name,
    required String Function(_TestModel item) getId,
    required JsonMap Function(_TestModel item) toJson,
    required _TestModel Function(JsonMap) fromJson,
    required _TestModel Function(_TestModel local, _TestModel remote)
    onConflict,
  }) {
    initLocalFirstRepository(
      name: name,
      getId: getId,
      toJson: toJson,
      fromJson: fromJson,
      onConflict: onConflict,
    );
  }

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
  bool opened = false;
  bool initialized = false;
  bool closed = false;
  int initializeCalls = 0;
  int closeCalls = 0;
  final Map<String, Map<String, JsonMap>> tables = {};
  final Map<String, String> meta = {};
  final Map<String, DateTime> registeredEvents = {};
  final Map<String, StreamController<List<JsonMap>>> _controllers = {};

  StreamController<List<JsonMap>> _controller(String name) {
    return _controllers.putIfAbsent(
      name,
      () => StreamController<List<JsonMap>>.broadcast(),
    );
  }

  Future<void> _emit(String tableName) async {
    if (_controllers[tableName]?.isClosed ?? true) return;
    _controller(tableName).add(await getAll(tableName));
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
    initializeCalls += 1;
  }

  @override
  Future<void> close() async {
    closed = true;
    opened = false;
    for (final c in _controllers.values) {
      await c.close();
    }
    closeCalls += 1;
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
  Future<List<JsonMap>> getAll(String tableName) async {
    return tables[tableName]?.values.map((e) => Map.of(e)).toList() ?? [];
  }

  @override
  Future<JsonMap?> getById(String tableName, String id) async {
    return tables[tableName]?[id];
  }

  Future<DateTime?> getLastSyncAt(String repositoryName) async => null;

  @override
  Future<String?> getMeta(String key) async => meta[key];

  @override
  Future<void> insert(String tableName, JsonMap item, String idField) async {
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
  Future<void> update(String tableName, String id, JsonMap item) async {
    tables.putIfAbsent(tableName, () => {});
    tables[tableName]![id] = item;
    await _emit(tableName);
  }

  @override
  Future<List<JsonMap>> query(LocalFirstQuery query) async {
    return getAll(query.repositoryName);
  }

  @override
  Stream<List<JsonMap>> watchQuery(LocalFirstQuery query) {
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

class _InMemoryKeyValueStorage implements LocalFirstKeyValueStorage {
  final Map<String, Object?> _store = {};
  bool _opened = false;
  String _namespace = 'default';
  int openCalls = 0;

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
    openCalls += 1;
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

void main() {
  group('LocalFirstClient', () {
    late _InMemoryStorage storage;
    late _InMemoryKeyValueStorage metaStorage;
    late LocalFirstRepository<_TestModel> repo;
    late LocalFirstClient client;

    LocalFirstRepository<_TestModel> buildRepo(String name) {
      return LocalFirstRepository.create<_TestModel>(
        name: name,
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: _TestModel.fromJson,
        onConflict: (l, r) => l,
      );
    }

    setUp(() async {
      storage = _InMemoryStorage();
      metaStorage = _InMemoryKeyValueStorage();
      repo = buildRepo('tests');
      client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        metaStorage: metaStorage,
        syncStrategies: [_OkStrategy()],
      );
    });

    test('initialize sets up storage', () async {
      await client.initialize();
      expect(storage.initialized, isTrue);
    });

    test(
      'initialize can be called multiple times without reinitializing',
      () async {
        await Future.wait([client.initialize(), client.initialize()]);
        expect(storage.initialized, isTrue);
        expect(storage.initializeCalls, 1);
        expect(metaStorage.openCalls, 1);
      },
    );

    test('constructor registers repositories and sync strategies', () async {
      final repoA = buildRepo('repo_a');
      final strategyA = _OkStrategy();
      final strategyB = _OkStrategy();
      final client = LocalFirstClient(
        repositories: [repoA],
        localStorage: _InMemoryStorage(),
        metaStorage: _InMemoryKeyValueStorage(),
        syncStrategies: [strategyA, strategyB],
      );

      expect(client.getRepositoryByName('repo_a'), same(repoA));
      expect(client.syncStrategies.length, 2);
    });

    test('constructor defaults metaStorage to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final repoA = buildRepo('repo_meta');
      final client = LocalFirstClient(
        repositories: [repoA],
        localStorage: _InMemoryStorage(),
        syncStrategies: [_OkStrategy()],
      );

      await client.initialize();
      await client.setKeyValue('k', 'v');
      expect(await client.getMeta('k'), 'v');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('default__k'), 'v');
    });

    test('initialize asserts when no repositories registered', () {
      final emptyClient = LocalFirstClient(
        repositories: const [],
        localStorage: storage,
        metaStorage: metaStorage,
        syncStrategies: [_OkStrategy()],
      );

      expect(() => emptyClient.initialize(), throwsA(isA<AssertionError>()));
    });

    test('initialize asserts when no sync strategies registered', () {
      final emptyClient = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        metaStorage: metaStorage,
        syncStrategies: const [],
      );

      expect(() => emptyClient.initialize(), throwsA(isA<AssertionError>()));
    });

    test(
      'registerRepositories supports multiple calls before initialize',
      () async {
        final emptyClient = LocalFirstClient(
          repositories: const [],
          localStorage: storage,
          metaStorage: metaStorage,
          syncStrategies: [_OkStrategy()],
        );
        final repoA = buildRepo('repo_a');
        final repoB = buildRepo('repo_b');

        emptyClient.registerRepositories([repoA]);
        emptyClient.registerRepositories([repoB]);

        await emptyClient.initialize();
        expect(emptyClient.getRepositoryByName('repo_a'), same(repoA));
        expect(emptyClient.getRepositoryByName('repo_b'), same(repoB));
      },
    );

    test('registerRepositories throws on duplicate names across calls', () {
      final emptyClient = LocalFirstClient(
        repositories: const [],
        localStorage: storage,
        metaStorage: metaStorage,
        syncStrategies: [_OkStrategy()],
      );
      final repoA = buildRepo('dup');
      final repoB = buildRepo('dup');

      emptyClient.registerRepositories([repoA]);
      expect(
        () => emptyClient.registerRepositories([repoB]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('registerRepositories throws after initialize', () async {
      final repoA = buildRepo('init_repo');
      final emptyClient = LocalFirstClient(
        repositories: [repoA],
        localStorage: storage,
        metaStorage: metaStorage,
        syncStrategies: [_OkStrategy()],
      );
      await emptyClient.initialize();

      expect(
        () => emptyClient.registerRepositories([buildRepo('late_repo')]),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'registerSyncStrategies supports multiple calls before initialize',
      () async {
        final emptyClient = LocalFirstClient(
          repositories: [repo],
          localStorage: storage,
          metaStorage: metaStorage,
          syncStrategies: const [],
        );

        emptyClient.registerSyncStrategies([_OkStrategy()]);
        emptyClient.registerSyncStrategies([_OkStrategy()]);

        await emptyClient.initialize();
        expect(emptyClient.syncStrategies.length, 2);
      },
    );

    test('registerSyncStrategies throws after initialize', () async {
      final emptyClient = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        metaStorage: metaStorage,
        syncStrategies: [_OkStrategy()],
      );
      await emptyClient.initialize();

      expect(
        () => emptyClient.registerSyncStrategies([_OkStrategy()]),
        throwsA(isA<StateError>()),
      );
    });

    test('duplicate repository names throw ArgumentError', () {
      expect(
        () => LocalFirstClient(
          repositories: [repo, repo],
          localStorage: _InMemoryStorage(),
          metaStorage: metaStorage,
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
        metaStorage: metaStorage,
        syncStrategies: [_OkStrategy()],
      );
      await clientWithProbe.initialize();
      await clientWithProbe.openStorage();
      await probeRepo.upsert(_TestModel('1'));

      expect(await storage.getById('probe', '1'), isNotNull);
      expect(probeRepo.initialized, isTrue);

      await clientWithProbe.clearAllData();

      expect(await storage.getById('probe', '1'), isNull);
      expect(probeRepo.resetCalled, isTrue);
      expect(probeRepo.initialized, isTrue);
    });

    test('setKeyValue / getMeta delegates to storage', () async {
      await metaStorage.open();
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
      expect(pending.first, isA<LocalFirstEvent>());
      expect(pending.first.dataAs<_TestModel>().id, 'p1');
    });

    test('dispose closes storage', () async {
      await client.initialize();
      await client.dispose();
      expect(storage.closed, isTrue);
    });

    test('closeStorage closes local storage connection', () async {
      await client.initialize();
      await client.openStorage();

      await client.closeStorage();

      expect(storage.closed, isTrue);
      expect(storage.closeCalls, 1);
    });

    test('awaitInitialization completes only after openStorage runs', () async {
      final completerOrder = <String>[];

      unawaited(
        client.awaitInitialization.then((_) {
          completerOrder.add('awaitInitialization');
        }),
      );

      // Ensure not completed before initialize
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(completerOrder, isEmpty);

      await client.openStorage();
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
