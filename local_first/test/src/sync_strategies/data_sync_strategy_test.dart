// ignore_for_file: override_on_non_overriding_member

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:mocktail/mocktail.dart';

class _DummyModel with LocalFirstModel {
  _DummyModel(this.id);
  final String id;

  @override
  JsonMap<dynamic> toJson() => {'id': id};
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
  Future<SyncStatus> onPushToRemote(LocalFirstModel localData) async {
    return SyncStatus.ok;
  }
}

class _FakeStorage implements LocalFirstStorage {
  final JsonMap<JsonMap<JsonMap<dynamic>>> _tables = {};
  final JsonMap<String> _meta = {};
  bool initialized = false;

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
  Future<List<JsonMap<dynamic>>> getAll(String tableName) async {
    return _tables[tableName]?.values.map((e) => Map.of(e)).toList() ?? [];
  }

  @override
  Future<JsonMap<dynamic>?> getById(String tableName, String id) async {
    return _tables[tableName]?[id];
  }

  @override
  Future<void> insert(
    String tableName,
    JsonMap<dynamic> item,
    String idField,
  ) async {
    _tables.putIfAbsent(tableName, () => {});
    _tables[tableName]![item[idField] as String] = item;
  }

  @override
  Future<void> update(
    String tableName,
    String id,
    JsonMap<dynamic> item,
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
  Future<String?> getMeta(String key) async => _meta[key];

  // Event log stubs
  final JsonMap<JsonMap<dynamic>> events = {};

  @override
  Future<void> insertEvent(JsonMap<dynamic> event) async {
    events[event['event_id'] as String] = event;
  }

  @override
  Future<JsonMap<dynamic>?> getEventById(String eventId) async {
    return events[eventId];
  }

  @override
  Future<List<JsonMap<dynamic>>> getEvents({String? repositoryName}) async {
    return events.values
        .where(
          (e) => repositoryName == null || e['repository'] == repositoryName,
        )
        .map((e) => JsonMap<dynamic>.from(e))
        .toList();
  }

  @override
  Future<void> deleteEvent(String eventId) async {
    events.remove(eventId);
  }

  @override
  Future<void> clearEvents() async {
    events.clear();
  }

  @override
  Future<void> pruneEvents(DateTime before) async {
    events.removeWhere((_, e) {
      final ts = e['_sync_created_at'];
      return ts is int && ts < before.toUtc().millisecondsSinceEpoch;
    });
  }

  @override
  Future<List<JsonMap<dynamic>>> query(LocalFirstQuery query) async {
    return _tables[query.repositoryName]?.values
            .map((e) => Map.of(e))
            .toList() ??
        [];
  }

  @override
  Stream<List<JsonMap<dynamic>>> watchQuery(LocalFirstQuery query) async* {
    yield await this.query(query);
  }

  @override
  Future<void> ensureSchema(
    String tableName,
    JsonMap<LocalFieldType> schema, {
    required String idFieldName,
  }) async {}
}

void main() {
  setUpAll(() {
    registerFallbackValue(<LocalFirstModel>[]);
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
      final pending = [_DummyModel('1')];

      when(
        () => client.getAllPendingObjects(),
      ).thenAnswer((_) async => pending);
      strategy.attach(client);

      final result = await strategy.getPendingObjects();

      expect(result, pending);
      verify(() => client.getAllPendingObjects()).called(1);
    });

    test('pullChangesToLocal calls client pull logic', () async {
      final strategy = _TestStrategy();
      final storage = _FakeStorage();
      final repo = LocalFirstRepository<_DummyModel>.create(
        name: 'users',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: (json) => _DummyModel(json['id'] as String),
        onConflictEvent: (l, r) => l,
      );
      final client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        syncStrategies: [strategy],
      );
      await client.initialize();

      await strategy.pullChangesToLocal({
        'timestamp': DateTime.now().toIso8601String(),
        'changes': {},
      });

      final metaKey = '__last_sync__users';
      final value = await storage.getMeta(metaKey);
      expect(value, isNotNull);
    });
  });
}
