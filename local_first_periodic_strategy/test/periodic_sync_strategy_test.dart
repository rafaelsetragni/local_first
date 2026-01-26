import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_periodic_strategy/local_first_periodic_strategy.dart';

/// Mock storage implementation for testing
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

void main() {
  group('PeriodicSyncStrategy', () {
    group('Initialization', () {
      test('should create strategy with required callbacks', () {
        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(seconds: 5),
          repositoryNames: ['test_repo'],
          onFetchEvents: (_) async => [],
          onPushEvents: (_, events) async => true,
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
        );

        expect(strategy, isNotNull);
        expect(strategy.syncInterval, const Duration(seconds: 5));
        expect(strategy.repositoryNames, ['test_repo']);
      });

      test('should support optional onPing callback', () {
        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(seconds: 5),
          repositoryNames: ['test_repo'],
          onFetchEvents: (_) async => [],
          onPushEvents: (_, events) async => true,
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
          onPing: () async => true,
        );

        expect(strategy.onPing, isNotNull);
      });
    });

    group('Sync Lifecycle', () {
      test('should start and stop sync timer', () async {
        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(milliseconds: 100),
          repositoryNames: ['test_repo'],
          onFetchEvents: (_) async => [],
          onPushEvents: (_, events) async => true,
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
        );

        final testRepo = LocalFirstRepository<JsonMap>.create(
          name: 'test_repo',
          getId: (item) => item['id'] as String,
          toJson: (item) => item,
          fromJson: (json) => json,
        );

        final client = LocalFirstClient(
          repositories: [testRepo],
          localStorage: _NoopStorage(),
          syncStrategies: [strategy],
        );

        await client.initialize();
        await strategy.start();

        expect(strategy.latestConnectionState, isTrue);

        strategy.stop();

        expect(strategy.latestConnectionState, isFalse);
      });

      test('should not start twice', () async {
        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(milliseconds: 100),
          repositoryNames: ['test_repo'],
          onFetchEvents: (_) async => [],
          onPushEvents: (_, events) async => true,
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
        );

        final testRepo = LocalFirstRepository<JsonMap>.create(
          name: 'test_repo',
          getId: (item) => item['id'] as String,
          toJson: (item) => item,
          fromJson: (json) => json,
        );

        final client = LocalFirstClient(
          repositories: [testRepo],
          localStorage: _NoopStorage(),
          syncStrategies: [strategy],
        );

        await client.initialize();
        await strategy.start();
        await strategy.start(); // Second call should be no-op

        expect(strategy.latestConnectionState, isTrue);

        strategy.stop();
      });

      test('should perform initial sync on start', () async {
        var fetchCalled = false;
        var pushAttempted = false;

        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(milliseconds: 50),
          repositoryNames: ['test_repo'],
          onFetchEvents: (_) async {
            fetchCalled = true;
            return [];
          },
          onPushEvents: (_, events) async {
            pushAttempted = true;
            return true;
          },
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
        );

        final testRepo = LocalFirstRepository<JsonMap>.create(
          name: 'test_repo',
          getId: (item) => item['id'] as String,
          toJson: (item) => item,
          fromJson: (json) => json,
        );

        final client = LocalFirstClient(
          repositories: [testRepo],
          localStorage: _NoopStorage(),
          syncStrategies: [strategy],
        );

        await client.initialize();
        await strategy.start();

        // start() awaits _performSync(), so sync is already complete
        expect(fetchCalled, isTrue, reason: 'onFetchEvents should have been called');
        // pushAttempted will be false because _NoopStorage has no pending events
        expect(pushAttempted, isFalse, reason: 'onPushEvents should NOT be called when there are no pending events');

        strategy.stop();
      });
    });

    group('Callbacks', () {
      test('should call onFetchEvents for each repository', () async {
        final fetchedRepos = <String>[];

        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(seconds: 100),
          repositoryNames: ['repo1', 'repo2'],
          onFetchEvents: (repositoryName) async {
            fetchedRepos.add(repositoryName);
            return [];
          },
          onPushEvents: (_, events) async => true,
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
        );

        final testRepo = LocalFirstRepository<JsonMap>.create(
          name: 'test_repo',
          getId: (item) => item['id'] as String,
          toJson: (item) => item,
          fromJson: (json) => json,
        );

        final client = LocalFirstClient(
          repositories: [testRepo],
          localStorage: _NoopStorage(),
          syncStrategies: [strategy],
        );

        await client.initialize();
        await strategy.start();

        // start() awaits _performSync(), so sync is already complete
        expect(fetchedRepos, containsAll(['repo1', 'repo2']));

        strategy.stop();
      });

      // Note: Testing onSaveSyncState integration requires properly formatted
      // events that match the repository schema. This is better tested in
      // integration tests or example applications where real data flows through
      // the system. The callback itself is validated by other tests.

      test('should call onPing if provided', () async {
        var pingCalled = false;

        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(seconds: 100),
          repositoryNames: ['test_repo'],
          onFetchEvents: (_) async => [],
          onPushEvents: (_, events) async => true,
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
          onPing: () async {
            pingCalled = true;
            return true;
          },
        );

        final testRepo = LocalFirstRepository<JsonMap>.create(
          name: 'test_repo',
          getId: (item) => item['id'] as String,
          toJson: (item) => item,
          fromJson: (json) => json,
        );

        final client = LocalFirstClient(
          repositories: [testRepo],
          localStorage: _NoopStorage(),
          syncStrategies: [strategy],
        );

        await client.initialize();
        await strategy.start();

        // start() awaits _performSync(), so sync is already complete
        expect(pingCalled, isTrue);

        strategy.stop();
      });
    });

    group('Error Handling', () {
      test('should continue syncing other repos if one fails', () async {
        final fetchedRepos = <String>[];

        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(seconds: 100),
          repositoryNames: ['repo1', 'repo2', 'repo3'],
          onFetchEvents: (repositoryName) async {
            fetchedRepos.add(repositoryName);
            if (repositoryName == 'repo2') {
              throw Exception('Fetch failed for repo2');
            }
            return [];
          },
          onPushEvents: (_, events) async => true,
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
        );

        final testRepo = LocalFirstRepository<JsonMap>.create(
          name: 'test_repo',
          getId: (item) => item['id'] as String,
          toJson: (item) => item,
          fromJson: (json) => json,
        );

        final client = LocalFirstClient(
          repositories: [testRepo],
          localStorage: _NoopStorage(),
          syncStrategies: [strategy],
        );

        await client.initialize();
        await strategy.start();

        // start() awaits _performSync(), so sync is already complete
        // All repos should be attempted
        expect(fetchedRepos, containsAll(['repo1', 'repo2', 'repo3']));

        strategy.stop();
      });

      test('should report disconnected on ping failure', () async {
        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(seconds: 100),
          repositoryNames: ['test_repo'],
          onFetchEvents: (_) async => [],
          onPushEvents: (_, events) async => true,
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
          onPing: () async => false,
        );

        final testRepo = LocalFirstRepository<JsonMap>.create(
          name: 'test_repo',
          getId: (item) => item['id'] as String,
          toJson: (item) => item,
          fromJson: (json) => json,
        );

        final client = LocalFirstClient(
          repositories: [testRepo],
          localStorage: _NoopStorage(),
          syncStrategies: [strategy],
        );

        await client.initialize();
        await strategy.start();

        // start() awaits _performSync(), so sync is already complete
        // Should report disconnected due to failed ping
        expect(strategy.latestConnectionState, isFalse);

        strategy.stop();
      });
    });

    group('Push to Remote', () {
      test('should return pending status on push', () async {
        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(seconds: 5),
          repositoryNames: ['test_repo'],
          onFetchEvents: (_) async => [],
          onPushEvents: (_, events) async => true,
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
        );

        final testRepo = LocalFirstRepository<JsonMap>.create(
          name: 'test_repo',
          getId: (item) => item['id'] as String,
          toJson: (item) => item,
          fromJson: (json) => json,
        );

        final event = LocalFirstEvent.createNewInsertEvent(
          needSync: true,
          data: {'id': '1'},
          repository: testRepo,
        );

        final status = await strategy.onPushToRemote(event);

        expect(status, SyncStatus.pending);
      });
    });

    group('Dispose', () {
      test('should stop sync on dispose', () async {
        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(milliseconds: 100),
          repositoryNames: ['test_repo'],
          onFetchEvents: (_) async => [],
          onPushEvents: (_, events) async => true,
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
        );

        final testRepo = LocalFirstRepository<JsonMap>.create(
          name: 'test_repo',
          getId: (item) => item['id'] as String,
          toJson: (item) => item,
          fromJson: (json) => json,
        );

        final client = LocalFirstClient(
          repositories: [testRepo],
          localStorage: _NoopStorage(),
          syncStrategies: [strategy],
        );

        await client.initialize();
        await strategy.start();

        expect(strategy.latestConnectionState, isTrue);

        strategy.dispose();

        expect(strategy.latestConnectionState, isFalse);
      });
    });
  });
}
