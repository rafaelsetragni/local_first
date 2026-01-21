import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

class _TestStrategy extends DataSyncStrategy {
  LocalFirstClient get exposedClient => client;

  void callReport(bool connected) => reportConnectionState(connected);
}

class _SpyLocalFirstClient extends LocalFirstClient {
  _SpyLocalFirstClient({required DataSyncStrategy strategy})
    : super(
        repositories: const [],
        localStorage: _NoopStorage(),
        syncStrategies: [strategy],
      );

  final List<String> pendingCalls = [];
  final List<List<JsonMap>> pulledChanges = [];
  final List<bool> reportedConnections = [];

  @override
  void reportConnectionState(bool connected) {
    reportedConnections.add(connected);
    super.reportConnectionState(connected);
  }

  @override
  Future<LocalFirstEvents> getAllPendingEvents({
    required String repositoryName,
  }) async {
    pendingCalls.add(repositoryName);
    return [];
  }

  @override
  Future<void> pullChanges({
    required String repositoryName,
    required List<JsonMap> changes,
  }) async {
    pulledChanges.add(changes);
  }
}

class _NoopStorage implements LocalFirstStorage {
  @override
  Future<void> clearAllData() async {}

  @override
  Future<void> close() async {}

  @override
  Future<bool> containsId(String tableName, String id) async => false;

  @override
  Future<void> delete(String repositoryName, String id) async {}

  @override
  Future<void> deleteAll(String tableName) async {}

  @override
  Future<void> deleteAllEvents(String tableName) async {}

  @override
  Future<void> deleteEvent(String repositoryName, String id) async {}

  @override
  Future<void> ensureSchema(
    String tableName,
    JsonMap<LocalFieldType> schema, {
    required String idFieldName,
  }) async {}

  @override
  Future<List<JsonMap>> getAll(String tableName) async => [];

  @override
  Future<List<JsonMap>> getAllEvents(String tableName) async => [];

  @override
  Future<JsonMap?> getById(String tableName, String id) async => null;

  @override
  Future<JsonMap?> getEventById(String tableName, String id) async => null;

  @override
  Future<bool> containsConfigKey(String key) async => false;

  @override
  Future<T?> getConfigValue<T>(String key) async => null;

  @override
  Future<void> useNamespace(String namespace) async {}

  @override
  Future<bool> removeConfig(String key) async => true;

  @override
  Future<bool> clearConfig() async => true;

  @override
  Future<Set<String>> getConfigKeys() async => {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> insert(String tableName, JsonMap item, String idField) async {}

  @override
  Future<void> insertEvent(
    String tableName,
    JsonMap item,
    String idField,
  ) async {}

  @override
  Future<List<LocalFirstEvent<T>>> query<T>(LocalFirstQuery<T> query) async =>
      [];

  @override
  Future<bool> setConfigValue<T>(String key, T value) async => true;

  @override
  Future<void> update(String tableName, String id, JsonMap item) async {}

  @override
  Future<void> updateEvent(String tableName, String id, JsonMap item) async {}

  @override
  Stream<List<LocalFirstEvent<T>>> watchQuery<T>(LocalFirstQuery<T> query) =>
      const Stream.empty();
}

class _RecordingStorage implements LocalFirstStorage {
  final List<JsonMap> events = [];
  final List<JsonMap> updatedEvents = [];
  int updateCount = 0;
  int updateEventCount = 0;
  JsonMap? lastUpdatedData;

  @override
  Future<void> clearAllData() async {}

  @override
  Future<void> close() async {}

  @override
  Future<bool> containsId(String tableName, String id) async => false;

  @override
  Future<void> delete(String repositoryName, String id) async {}

  @override
  Future<void> deleteAll(String tableName) async {}

  @override
  Future<void> deleteAllEvents(String tableName) async {}

  @override
  Future<void> deleteEvent(String repositoryName, String id) async {}

  @override
  Future<void> ensureSchema(
    String tableName,
    JsonMap<LocalFieldType> schema, {
    required String idFieldName,
  }) async {}

  @override
  Future<List<JsonMap>> getAll(String tableName) async => [];

  @override
  Future<List<JsonMap>> getAllEvents(String tableName) async =>
      List.unmodifiable(events);

  @override
  Future<JsonMap?> getById(String tableName, String id) async => null;

  @override
  Future<JsonMap?> getEventById(String tableName, String id) async => null;

  @override
  Future<bool> containsConfigKey(String key) async => false;

  @override
  Future<T?> getConfigValue<T>(String key) async => null;

  @override
  Future<void> useNamespace(String namespace) async {}

  @override
  Future<bool> removeConfig(String key) async => true;

  @override
  Future<bool> clearConfig() async => true;

  @override
  Future<Set<String>> getConfigKeys() async => {};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> insert(String tableName, JsonMap item, String idField) async {}

  @override
  Future<void> insertEvent(
    String tableName,
    JsonMap item,
    String idField,
  ) async {}

  @override
  Future<List<LocalFirstEvent<T>>> query<T>(LocalFirstQuery<T> query) async =>
      [];

  @override
  Future<bool> setConfigValue<T>(String key, T value) async => true;

  @override
  Future<void> update(String tableName, String id, JsonMap item) async {
    updateCount++;
    lastUpdatedData = item;
  }

  @override
  Future<void> updateEvent(String tableName, String id, JsonMap item) async {
    updateEventCount++;
    updatedEvents.add(item);
  }

  @override
  Stream<List<LocalFirstEvent<T>>> watchQuery<T>(LocalFirstQuery<T> query) =>
      const Stream.empty();
}

void main() {
  group('DataSyncStrategy', () {
    late _TestStrategy strategy;
    late _SpyLocalFirstClient client;

    setUp(() {
      strategy = _TestStrategy();
      client = _SpyLocalFirstClient(strategy: strategy);
    });

    test('should attach client on construction', () {
      expect(strategy.exposedClient, same(client));
    });

    test('should return pending on default onPushToRemote', () async {
      final repo = LocalFirstRepository<JsonMap>.create(
        name: 'dummy',
        getId: (item) => '',
        toJson: (item) => item,
        fromJson: (json) => json,
      );
      final event = LocalFirstEvent.createNewInsertEvent(
        needSync: true,
        data: {'id': '1'},
        repository: repo,
      );

      final status = await strategy.onPushToRemote(event);

      expect(status, SyncStatus.pending);
    });

    test('should forward reportConnectionState to client', () async {
      final events = <bool>[];
      final subscription = client.connectionChanges.listen(events.add);

      strategy.callReport(true);
      strategy.callReport(false);
      await Future<void>.delayed(Duration.zero);

      expect(client.reportedConnections, [true, false]);
      expect(events, [true, false]);
      expect(strategy.latestConnectionState, isFalse);

      await subscription.cancel();
    });

    test('should delegate getPendingEvents to client', () async {
      final result = await strategy.getPendingEvents(repositoryName: 'repo1');

      expect(result, isEmpty);
      expect(client.pendingCalls, ['repo1']);
    });

  test('should delegate pullChangesToLocal to client', () async {
    final payload = [
      {LocalFirstEvent.kRepository: 'repo1'},
    ];

      await strategy.pullChangesToLocal(
        repositoryName: 'repo1',
        remoteChanges: payload,
      );

    expect(client.pulledChanges.single, payload);
  });

  test('connectionChanges getter should expose client stream reference', () {
    expect(strategy.connectionChanges, isA<Stream<bool>>());
  });

  test('connectionChanges getter should proxy underlying client stream',
      () async {
    final events = <bool>[];
    final sub = strategy.connectionChanges.listen(events.add);

      client.reportConnectionState(true);
      await Future<void>.delayed(Duration.zero);

      expect(events, [true]);
      await sub.cancel();
    });

    test('markEventsAsSynced should mark current and previous events as ok',
        () async {
      final storage = _RecordingStorage();
      final repo = LocalFirstRepository<JsonMap>.create(
        name: 'repo',
        getId: (item) => item['id'] as String,
        toJson: (item) => item,
        fromJson: (json) => json,
      );
      LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        syncStrategies: [strategy],
      );
      final older = LocalFirstEvent.createNewInsertEvent(
        repository: repo,
        data: {'id': '1'},
        needSync: true,
      );
      final latest = LocalFirstEvent.createNewUpdateEvent(
        repository: repo,
        data: {'id': '1'},
        needSync: true,
      );
      final otherId = LocalFirstEvent.createNewInsertEvent(
        repository: repo,
        data: {'id': '2'},
        needSync: true,
      );
      final referenceCreatedAt =
          latest.syncCreatedAt.millisecondsSinceEpoch;
      storage.events.addAll([
        older.toLocalStorageJson()
          ..[LocalFirstEvent.kSyncCreatedAt] = referenceCreatedAt - 1,
        latest.toLocalStorageJson()
          ..[LocalFirstEvent.kSyncCreatedAt] = referenceCreatedAt + 1,
        otherId.toLocalStorageJson()
          ..[LocalFirstEvent.kSyncCreatedAt] = referenceCreatedAt - 1,
      ]);

      await strategy.markEventsAsSynced([latest]);

      expect(storage.updateCount, greaterThanOrEqualTo(1));
      expect(storage.updateEventCount, 2); // latest + older
      expect(
        storage.updatedEvents
            .where(
              (e) => e[LocalFirstEvent.kEventId] == latest.eventId,
            )
            .single[LocalFirstEvent.kSyncStatus],
        SyncStatus.ok.index,
      );
      expect(
        storage.updatedEvents
            .where((e) => e[LocalFirstEvent.kEventId] == older.eventId)
            .single[LocalFirstEvent.kSyncStatus],
        SyncStatus.ok.index,
      );
      expect(
        storage.updatedEvents
            .where((e) => e[LocalFirstEvent.kEventId] == otherId.eventId),
        isEmpty,
      );
    });

  test('markEventsAsSynced should pick the latest event per data id', () async {
    final storage = _RecordingStorage();
    final repo = LocalFirstRepository<JsonMap>.create(
      name: 'repo',
      getId: (item) => item['id'] as String,
        toJson: (item) => item,
        fromJson: (json) => json,
      );
      LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        syncStrategies: [strategy],
      );
      final older = LocalFirstEvent.createNewInsertEvent(
        repository: repo,
        data: {'id': '1'},
        needSync: true,
      );
      final latest = LocalFirstEvent.createNewUpdateEvent(
        repository: repo,
        data: {'id': '1'},
        needSync: true,
      );

      await strategy.markEventsAsSynced([latest, older]);

      expect(storage.updateEventCount, 1);
      expect(storage.updateCount, 1);
    expect(
      storage.lastUpdatedData?[LocalFirstEvent.kLastEventId],
      latest.eventId,
    );
  });

  test('markEventsAsSynced keeps newest when older duplicate arrives', () async {
    final storage = _RecordingStorage();
    final repo = LocalFirstRepository<JsonMap>.create(
      name: 'repo',
      getId: (item) => item['id'] as String,
      toJson: (item) => item,
      fromJson: (json) => json,
    );
    LocalFirstClient(
      repositories: [repo],
      localStorage: storage,
      syncStrategies: [strategy],
    );
    final older = LocalFirstEvent<JsonMap>.fromLocalStorage(
      repository: repo,
      json: {
        LocalFirstEvent.kEventId: 'older',
        LocalFirstEvent.kDataId: '1',
        LocalFirstEvent.kSyncStatus: SyncStatus.pending.index,
        LocalFirstEvent.kOperation: SyncOperation.insert.index,
        LocalFirstEvent.kSyncCreatedAt: 1000,
        'id': '1',
      },
    );
    final latest = LocalFirstEvent<JsonMap>.fromLocalStorage(
      repository: repo,
      json: {
        LocalFirstEvent.kEventId: 'latest',
        LocalFirstEvent.kDataId: '1',
        LocalFirstEvent.kSyncStatus: SyncStatus.pending.index,
        LocalFirstEvent.kOperation: SyncOperation.insert.index,
        LocalFirstEvent.kSyncCreatedAt: 2000,
        'id': '1',
      },
    );

    await strategy.markEventsAsSynced([older, latest]);

    expect(storage.updateEventCount, 1);
    expect(
      storage.updatedEvents.single[LocalFirstEvent.kEventId],
      latest.eventId,
    );
  });
  });
}
