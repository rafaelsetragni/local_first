// ignore_for_file: override_on_non_overriding_member

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:mocktail/mocktail.dart';

class _DummyModel {
  _DummyModel(this.id);
  final String id;

  Map<String, dynamic> toJson() => {'id': id};
}

class _MockClient extends Mock implements LocalFirstClient {}

class _TestStrategy extends DataSyncStrategy {
  LocalFirstClient? lastAttached;

  @override
  void attach(LocalFirstClient client) {
    super.attach(client);
    lastAttached = client;
  }

  @override
  Future<SyncStatus> onPushToRemote(LocalFirstEvent localData) async {
    return SyncStatus.ok;
  }
}

class _OtherModel {
  _OtherModel(this.id);
  final String id;

  Map<String, dynamic> toJson() => {'id': id};
}

class _TypedStrategy extends DataSyncStrategy<_DummyModel> {
  @override
  Future<SyncStatus> onPushToRemote(LocalFirstEvent event) async {
    return SyncStatus.ok;
  }
}

class _FakeStorage implements LocalFirstStorage {
  final Map<String, Map<String, Map<String, dynamic>>> _tables = {};
  final Map<String, String> _meta = {};
  final Map<String, DateTime> _registeredEvents = {};
  bool initialized = false;

  @override
  Future<void> open({String namespace = 'default'}) async {}

  @override
  bool get isOpened => initialized;

  @override
  bool get isClosed => !initialized;

  @override
  String get currentNamespace => 'default';

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> close() async {
    initialized = false;
  }

  @override
  Future<void> clearAllData() async {
    _tables.clear();
    _meta.clear();
  }

  @override
  Future<List<Map<String, dynamic>>> getAll(String tableName) async {
    return _tables[tableName]?.values.map((e) => Map.of(e)).toList() ?? [];
  }

  @override
  Future<Map<String, dynamic>?> getById(String tableName, String id) async {
    return _tables[tableName]?[id];
  }

  @override
  Future<void> insert(
    String tableName,
    Map<String, dynamic> item,
    String idField,
  ) async {
    _tables.putIfAbsent(tableName, () => {});
    _tables[tableName]![item[idField] as String] = item;
  }

  @override
  Future<void> update(
    String tableName,
    String id,
    Map<String, dynamic> item,
  ) async {
    _tables.putIfAbsent(tableName, () => {});
    _tables[tableName]![id] = item;
  }

  @override
  Future<void> delete(String repositoryName, String id) async {
    _tables[repositoryName]?.remove(id);
  }

  @override
  Future<void> deleteAll(String tableName) async {
    _tables[tableName]?.clear();
  }

  @override
  Future<DateTime?> getLastSyncAt(String repositoryName) async => null;

  @override
  Future<void> setLastSyncAt(String repositoryName, DateTime time) async {}

  @override
  Future<void> setMeta(String key, String value) async {
    _meta[key] = value;
  }

  @override
  Future<void> registerEvent(String eventId, DateTime createdAt) async {
    _registeredEvents.putIfAbsent(eventId, () => createdAt.toUtc());
  }

  @override
  Future<bool> isEventRegistered(String eventId) async {
    return _registeredEvents.containsKey(eventId);
  }

  @override
  Future<void> pruneRegisteredEvents(DateTime before) async {
    final threshold = before.toUtc();
    _registeredEvents.removeWhere((_, value) => value.isBefore(threshold));
  }

  @override
  Future<String?> getMeta(String key) async => _meta[key];

  @override
  Future<List<Map<String, dynamic>>> query(LocalFirstQuery query) async {
    return _tables[query.repositoryName]?.values
            .map((e) => Map.of(e))
            .toList() ??
        [];
  }

  @override
  Stream<List<Map<String, dynamic>>> watchQuery(LocalFirstQuery query) async* {
    yield await this.query(query);
  }

  @override
  Future<void> ensureSchema(
    String tableName,
    Map<String, LocalFieldType> schema, {
    required String idFieldName,
  }) async {}
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

void main() {
  setUpAll(() {
    registerFallbackValue(<LocalFirstEvent>[]);
  });

  group('DataSyncStrategy', () {
    test('attach stores client', () {
      final strategy = _TestStrategy();
      final client = _MockClient();

      strategy.attach(client);

      expect(strategy.lastAttached, equals(client));
    });

    test('client getter exposes attached client', () {
      final strategy = _TestStrategy();
      final client = _MockClient();

      strategy.attach(client);

      expect(strategy.client, same(client));
    });

    test('getPendingObjects delegates to client', () async {
      final strategy = _TestStrategy();
      final client = _MockClient();
      final pending = <LocalFirstEvent>[
        LocalFirstEvent(data: _DummyModel('1')),
      ];

      when(
        () => client.getAllPendingObjects(),
      ).thenAnswer((_) async => pending);
      strategy.attach(client);

      final result = await strategy.getPendingObjects();

      expect(result, pending);
      verify(() => client.getAllPendingObjects()).called(1);
    });

    test('getPendingObjects filters to typed model', () async {
      final strategy = _TypedStrategy();
      final client = _MockClient();
      final pending = <LocalFirstEvent>[
        LocalFirstEvent(data: _DummyModel('1')),
        LocalFirstEvent(data: _OtherModel('2')),
        LocalFirstEvent(data: _DummyModel('3')),
      ];

      when(
        () => client.getAllPendingObjects(),
      ).thenAnswer((_) async => pending);
      strategy.attach(client);

      final result = await strategy.getPendingObjects();

      expect(result.map((e) => e.dataAs<_DummyModel>().id), ['1', '3']);
      verify(() => client.getAllPendingObjects()).called(1);
    });

    test('pullChangesToLocal calls client pull logic', () async {
      final strategy = _TestStrategy();
      final storage = _FakeStorage();
      final metaStorage = _InMemoryKeyValueStorage();
      final repo = LocalFirstRepository.create<_DummyModel>(
        name: 'users',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: (json) => _DummyModel(json['id'] as String),
        onConflict: (l, r) => l,
      );
      final client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        metaStorage: metaStorage,
        syncStrategies: [strategy],
      );
      await client.initialize();

      await strategy.pullChangesToLocal({
        'timestamp': DateTime.now().toIso8601String(),
        'changes': {},
      });

      final metaKey = '__last_sync__users';
      final value = await metaStorage.get<String>(metaKey);
      expect(value, isNotNull);
    });
  });
}
