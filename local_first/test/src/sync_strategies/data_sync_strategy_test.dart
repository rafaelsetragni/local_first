// ignore_for_file: override_on_non_overriding_member

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:mocktail/mocktail.dart';

class _DummyModel {
  _DummyModel(this.id);
  final String id;

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
  Future<SyncStatus> onPushToRemote(LocalFirstEvent localData) async {
    return SyncStatus.ok;
  }
}

class _FakeStorage implements LocalFirstStorage {
  final JsonMap<JsonMap<JsonMap<dynamic>>> _tables = {};
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
  // Event log stubs
  final JsonMap<JsonMap<dynamic>> events = {};

  @override
  Future<void> pullRemoteEvent(JsonMap<dynamic> event) async {
    events[event['event_id'] as String] = Map.of(event);
  }

  @override
  Future<JsonMap<dynamic>?> getEventById(String eventId) async {
    final e = events[eventId];
    return e == null ? null : Map.of(e);
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
      final ts = e['created_at'];
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
      final pending = [
        LocalFirstEvent.createLocalInsert(
          repositoryName: 'users',
          recordId: '1',
          data: _DummyModel('1'),
          createdAt: DateTime.utc(2024, 1, 1),
          eventId: 'e1',
        ),
      ];

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
      final kv = LocalFirstMemoryKeyValueStorage();
      final client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        syncStrategies: [strategy],
        keyValueStorage: kv,
      );
      await client.initialize();

      await strategy.pullChangesToLocal({
        'users': {
          'server_sequence': 1,
          'events': <JsonMap<dynamic>>[],
        },
      });

      final metaKey = '_last_sync_seq_users';
      final value = await kv.get<String>(metaKey);
      expect(value, equals('1'));
    });
  });
}
