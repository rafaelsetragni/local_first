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
  Future<void> pullChanges(List<JsonMap> changes) async {
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
  Future<String?> getMeta(String key) async => null;

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
  Future<void> setMeta(String key, String value) async {}

  @override
  Future<void> update(String tableName, String id, JsonMap item) async {}

  @override
  Future<void> updateEvent(String tableName, String id, JsonMap item) async {}

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

      await strategy.pullChangesToLocal(payload);

      expect(client.pulledChanges.single, payload);
    });
  });
}
