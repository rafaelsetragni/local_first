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
  static const Set<String> _metadataKeys = {
    '_last_event_id',
    '_event_id',
    '_data_id',
    '_sync_status',
    '_sync_operation',
    '_sync_created_at',
  };

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
    final events = tables[_eventsTable(tableName)] ?? {};
    final data = tables[tableName];
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
    final events = tables[_eventsTable(tableName)] ?? {};
    final data = tables[tableName]?[id];
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
    final id = item[idField] as String;
    final lastEventId = item['_last_event_id'] ?? item['_event_id'];
    final cleaned = _stripMetadata(item);
    if (lastEventId is String) {
      cleaned['_last_event_id'] = lastEventId;
    }
    tables[tableName]![id] = cleaned;

    if (lastEventId is String &&
        (item['_sync_status'] != null || item['_sync_operation'] != null)) {
      tables.putIfAbsent(_eventsTable(tableName), () => {});
      tables[_eventsTable(tableName)]![lastEventId] = {
        '_event_id': lastEventId,
        '_data_id': id,
        '_sync_status': item['_sync_status'],
        '_sync_operation': item['_sync_operation'],
        '_sync_created_at': item['_sync_created_at'],
      };
    }
    await _emit(tableName);
  }

  Future<void> setLastSyncAt(String repositoryName, DateTime time) async {}

  @override
  Future<void> setMeta(String key, String value) async {
    meta[key] = value;
  }

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
  Future<List<Map<String, dynamic>>> getAllEvents(String tableName) {
    final events = tables[_eventsTable(tableName)] ?? {};
    final data = tables[tableName] ?? {};

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
    final meta = tables[_eventsTable(tableName)]?[id];
    if (meta == null) return Future.value(null);
    final data = tables[tableName]?[meta['_data_id']];
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
    tables.putIfAbsent(_eventsTable(tableName), () => {});
    final id = item[idField] as String;
    tables[_eventsTable(tableName)]![id] = {
      '_event_id': id,
      '_data_id': item['_data_id'] ?? id,
      '_sync_status': item['_sync_status'],
      '_sync_operation': item['_sync_operation'],
      '_sync_created_at': item['_sync_created_at'],
    };
    await _emit(tableName);
  }

  @override
  Future<void> updateEvent(
    String tableName,
    String id,
    Map<String, dynamic> item,
  ) async {
    tables.putIfAbsent(_eventsTable(tableName), () => {});
    tables[_eventsTable(tableName)]![id] = {
      '_event_id': id,
      '_data_id': item['_data_id'] ?? id,
      '_sync_status': item['_sync_status'],
      '_sync_operation': item['_sync_operation'],
      '_sync_created_at': item['_sync_created_at'],
    };
    await _emit(tableName);
  }

  @override
  Future<void> deleteEvent(String repositoryName, String id) async {
    tables[_eventsTable(repositoryName)]?.remove(id);
    await _emit(repositoryName);
  }

  @override
  Future<void> deleteAllEvents(String tableName) async {
    tables[_eventsTable(tableName)]?.clear();
    await _emit(tableName);
  }

  @override
  Future<void> update(
    String tableName,
    String id,
    Map<String, dynamic> item,
  ) async {
    tables.putIfAbsent(tableName, () => {});
    final cleaned = _stripMetadata(item);
    final lastEventId = item['_last_event_id'] ?? item['_event_id'];
    if (lastEventId is String) {
      cleaned['_last_event_id'] = lastEventId;
    }
    tables[tableName]![id] = cleaned;

    if (lastEventId is String &&
        (item['_sync_status'] != null || item['_sync_operation'] != null)) {
      tables.putIfAbsent(_eventsTable(tableName), () => {});
      tables[_eventsTable(tableName)]![lastEventId] = {
        '_event_id': lastEventId,
        '_data_id': id,
        '_sync_status': item['_sync_status'],
        '_sync_operation': item['_sync_operation'],
        '_sync_created_at': item['_sync_created_at'],
      };
    }
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
      await probeRepo.upsert(
        LocalFirstEvent(state: _TestModel('1')),
        needSync: true,
      );

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

    test('getAllPendingEvents aggregates pending from repositories', () async {
      await client.initialize();
      final eventId = 'evt-1';
      final createdAt = DateTime.now().toUtc().millisecondsSinceEpoch;

      await storage.insert(
        'tests',
        {
          'id': 'p1',
          'value': 'pending',
          '_last_event_id': eventId,
        },
        'id',
      );
      await storage.insertEvent(
        'tests',
        {
          '_event_id': eventId,
          '_data_id': 'p1',
          '_sync_status': SyncStatus.pending.index,
          '_sync_operation': SyncOperation.insert.index,
          '_sync_created_at': createdAt,
        },
        '_event_id',
      );

      final pending = await client.getAllPendingEvents();
      expect(pending.length, 1);
      expect(pending.first.state, isA<_TestModel>());
      expect(pending.first.state.id, 'p1');
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
