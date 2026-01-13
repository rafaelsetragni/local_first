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

class _FakeStorage implements LocalFirstStorage {
  final Map<String, Map<String, Map<String, dynamic>>> _tables = {};
  final Map<String, String> _meta = {};
  bool initialized = false;
  static const Set<String> _metadataKeys = {
    '_last_event_id',
    '_event_id',
    '_data_id',
    '_sync_status',
    '_sync_operation',
    '_sync_created_at',
  };

  String _eventsTable(String name) => '${name}__events';

  Map<String, dynamic> _mergeEventWithData(
    Map<String, dynamic> meta,
    Map<String, dynamic>? data,
  ) {
    final merged = <String, dynamic>{
      if (data != null) ...data,
      ...meta,
    };
    final eventId = meta['_event_id'];
    final dataId = meta['_data_id'];
    if (eventId is String) merged['_last_event_id'] = eventId;
    if (dataId is String) merged.putIfAbsent('id', () => dataId);
    return merged;
  }

  Map<String, dynamic> _stripMetadata(Map<String, dynamic> map) {
    final copy = Map<String, dynamic>.from(map);
    copy.removeWhere((key, _) => _metadataKeys.contains(key));
    return copy;
  }

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
    final events = _tables[_eventsTable(tableName)] ?? {};
    final data = _tables[tableName];
    if (data == null) return [];

    return data.values.map((value) {
      final item = Map<String, dynamic>.from(value);
      final lastEventId = item['_last_event_id'];
      if (lastEventId is String) {
        final meta = events[lastEventId];
        if (meta != null) {
          item.addAll(meta);
        }
        item['_last_event_id'] = lastEventId;
      }
      return item;
    }).toList();
  }

  @override
  Future<Map<String, dynamic>?> getById(String tableName, String id) async {
    final events = _tables[_eventsTable(tableName)] ?? {};
    final data = _tables[tableName]?[id];
    if (data == null) return null;
    final item = Map<String, dynamic>.from(data);
    final lastEventId = item['_last_event_id'];
    if (lastEventId is String) {
      final meta = events[lastEventId];
      if (meta != null) {
        item.addAll(meta);
      }
      item['_last_event_id'] = lastEventId;
    }
    return item;
  }

  @override
  Future<void> insert(
    String tableName,
    Map<String, dynamic> item,
    String idField,
  ) async {
    _tables.putIfAbsent(tableName, () => {});
    final id = item[idField] as String;
    final lastEventId = item['_last_event_id'] ?? item['_event_id'];
    final cleaned = _stripMetadata(item);
    if (lastEventId is String) {
      cleaned['_last_event_id'] = lastEventId;
    }
    _tables[tableName]![id] = cleaned;

    if (lastEventId is String &&
        (item['_sync_status'] != null || item['_sync_operation'] != null)) {
      _tables.putIfAbsent(_eventsTable(tableName), () => {});
      _tables[_eventsTable(tableName)]![lastEventId] = {
        '_event_id': lastEventId,
        '_data_id': id,
        '_sync_status': item['_sync_status'],
        '_sync_operation': item['_sync_operation'],
        '_sync_created_at': item['_sync_created_at'],
      };
    }
  }

  @override
  Future<void> update(
    String tableName,
    String id,
    Map<String, dynamic> item,
  ) async {
    _tables.putIfAbsent(tableName, () => {});
    final cleaned = _stripMetadata(item);
    final lastEventId = item['_last_event_id'] ?? item['_event_id'];
    if (lastEventId is String) {
      cleaned['_last_event_id'] = lastEventId;
    }
    _tables[tableName]![id] = cleaned;

    if (lastEventId is String &&
        (item['_sync_status'] != null || item['_sync_operation'] != null)) {
      _tables.putIfAbsent(_eventsTable(tableName), () => {});
      _tables[_eventsTable(tableName)]![lastEventId] = {
        '_event_id': lastEventId,
        '_data_id': id,
        '_sync_status': item['_sync_status'],
        '_sync_operation': item['_sync_operation'],
        '_sync_created_at': item['_sync_created_at'],
      };
    }
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
  Future<List<Map<String, dynamic>>> getAllEvents(String tableName) {
    final events = _tables[_eventsTable(tableName)] ?? {};
    final data = _tables[tableName] ?? {};

    return Future.value([
      for (final meta in events.values)
        _mergeEventWithData(
          Map<String, dynamic>.from(meta),
          data[meta['_data_id']],
        ),
    ]);
  }

  @override
  Future<Map<String, dynamic>?> getEventById(
    String tableName,
    String id,
  ) {
    final meta = _tables[_eventsTable(tableName)]?[id];
    if (meta == null) return Future.value(null);
    final data = _tables[tableName]?[meta['_data_id']];
    return Future.value(
      _mergeEventWithData(Map<String, dynamic>.from(meta), data),
    );
  }

  @override
  Future<void> insertEvent(
    String tableName,
    Map<String, dynamic> item,
    String idField,
  ) async {
    _tables.putIfAbsent(_eventsTable(tableName), () => {});
    final id = item[idField] as String;
    _tables[_eventsTable(tableName)]![id] = {
      '_event_id': id,
      '_data_id': item['_data_id'] ?? id,
      '_sync_status': item['_sync_status'],
      '_sync_operation': item['_sync_operation'],
      '_sync_created_at': item['_sync_created_at'],
    };
  }

  @override
  Future<void> updateEvent(
    String tableName,
    String id,
    Map<String, dynamic> item,
  ) async {
    _tables.putIfAbsent(_eventsTable(tableName), () => {});
    _tables[_eventsTable(tableName)]![id] = {
      '_event_id': id,
      '_data_id': item['_data_id'] ?? id,
      '_sync_status': item['_sync_status'],
      '_sync_operation': item['_sync_operation'],
      '_sync_created_at': item['_sync_created_at'],
    };
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
    _meta[key] = value;
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

void main() {
  setUpAll(() {
    registerFallbackValue(<LocalFirstEvent<_DummyModel>>[]);
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

    test('getPendingEvents delegates to client', () async {
      final strategy = _TestStrategy();
      final client = _MockClient();
      final pending = [LocalFirstEvent(state: _DummyModel('1'))];

      when(
        () => client.getAllPendingEvents(),
      ).thenAnswer((_) async => pending);
      strategy.attach(client);

      final result = await strategy.getPendingEvents();

      expect(result, pending);
      verify(() => client.getAllPendingEvents()).called(1);
    });

    test('pullChangesToLocal calls client pull logic', () async {
      final strategy = _TestStrategy();
      final storage = _FakeStorage();
      final repo = LocalFirstRepository<_DummyModel>.create(
        name: 'users',
        getId: (m) => m.id,
        toJson: (m) => m.toJson(),
        fromJson: (json) => _DummyModel(json['id'] as String),
        onConflict: (l, r) => l,
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
