import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_periodic_strategy/local_first_periodic_strategy.dart';

// Helper to build a standard test repository
LocalFirstRepository<JsonMap> _buildRepo(String name) =>
    LocalFirstRepository<JsonMap>.create(
      name: name,
      getId: (item) => item['id'] as String,
      toJson: (item) => item,
      fromJson: (json) => json,
    );

// Helper to build a started strategy + client using InMemoryLocalFirstStorage
Future<({PeriodicSyncStrategy strategy, LocalFirstClient client})>
_startInMemory({
  required PeriodicSyncStrategy strategy,
  List<LocalFirstRepository>? repos,
}) async {
  final client = LocalFirstClient(
    repositories: repos ?? [_buildRepo('test_repo')],
    localStorage: InMemoryLocalFirstStorage(),
    syncStrategies: [strategy],
  );
  await client.initialize();
  await strategy.start();
  return (strategy: strategy, client: client);
}

// Helper to build a started strategy + client using _NoopStorage
Future<({PeriodicSyncStrategy strategy, LocalFirstClient client})>
_startNoop({
  required PeriodicSyncStrategy strategy,
  List<LocalFirstRepository>? repos,
}) async {
  final client = LocalFirstClient(
    repositories: repos ?? [_buildRepo('test_repo')],
    localStorage: _NoopStorage(),
    syncStrategies: [strategy],
  );
  await client.initialize();
  await strategy.start();
  return (strategy: strategy, client: client);
}

// Valid remote event JSON for a 'test_repo' insert
JsonMap _remoteInsertEvent({String id = 'remote-1'}) => {
  LocalFirstEvent.kEventId: 'evt-$id',
  LocalFirstEvent.kOperation: SyncOperation.insert.index,
  LocalFirstEvent.kSyncCreatedAt: DateTime.now().toUtc().toIso8601String(),
  LocalFirstEvent.kData: {'id': id},
  LocalFirstEvent.kDataId: id,
};

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
        expect(
          fetchCalled,
          isTrue,
          reason: 'onFetchEvents should have been called',
        );
        // pushAttempted will be false because _NoopStorage has no pending events
        expect(
          pushAttempted,
          isFalse,
          reason:
              'onPushEvents should NOT be called when there are no pending events',
        );

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

    group('forceSync', () {
      test('does nothing when strategy is not running', () async {
        var syncCalled = false;
        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(seconds: 100),
          repositoryNames: ['test_repo'],
          onFetchEvents: (_) async {
            syncCalled = true;
            return [];
          },
          onPushEvents: (_, events) async => true,
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
        );

        // Do NOT call start() — strategy is not running
        await strategy.forceSync();

        expect(syncCalled, isFalse);
      });

      test('executes a sync cycle when running', () async {
        var fetchCallCount = 0;
        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(seconds: 100),
          repositoryNames: ['test_repo'],
          onFetchEvents: (_) async {
            fetchCallCount++;
            return [];
          },
          onPushEvents: (_, events) async => true,
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
        );

        final ctx = await _startNoop(strategy: strategy);
        // start() already performed one sync
        expect(fetchCallCount, 1);

        await strategy.forceSync();
        // forceSync triggers a second sync
        expect(fetchCallCount, 2);

        ctx.strategy.stop();
      });
    });

    group('onPing exception', () {
      test('reports disconnected when onPing throws', () async {
        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(seconds: 100),
          repositoryNames: ['test_repo'],
          onFetchEvents: (_) async => [],
          onPushEvents: (_, events) async => true,
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
          onPing: () async => throw Exception('Network unreachable'),
        );

        final ctx = await _startNoop(strategy: strategy);

        expect(ctx.strategy.latestConnectionState, isFalse);

        ctx.strategy.stop();
      });
    });

    group('Push with pending events', () {
      test('calls onPushEvents when pending events exist', () async {
        var pushedRepo = '';
        var pushedCount = 0;

        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(seconds: 100),
          repositoryNames: ['test_repo'],
          onFetchEvents: (_) async => [],
          onPushEvents: (repoName, events) async {
            pushedRepo = repoName;
            pushedCount = events.length;
            return true;
          },
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
        );

        final testRepo = _buildRepo('test_repo');
        final ctx = await _startInMemory(
          strategy: strategy,
          repos: [testRepo],
        );

        // Insert an item to create a pending event before syncing
        await testRepo.upsert({'id': '1'}, needSync: true);
        await strategy.forceSync();

        expect(pushedRepo, 'test_repo');
        expect(pushedCount, greaterThan(0));

        ctx.strategy.stop();
      });

      test('logs failure when onPushEvents returns false', () async {
        var pushCalled = false;

        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(seconds: 100),
          repositoryNames: ['test_repo'],
          onFetchEvents: (_) async => [],
          onPushEvents: (_, events) async {
            pushCalled = true;
            return false; // simulate server rejection
          },
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
        );

        final testRepo = _buildRepo('test_repo');
        final ctx = await _startInMemory(
          strategy: strategy,
          repos: [testRepo],
        );

        await testRepo.upsert({'id': '1'}, needSync: true);
        await strategy.forceSync();

        expect(pushCalled, isTrue);
        // Connection remains true — only ping failure marks disconnected
        expect(ctx.strategy.latestConnectionState, isTrue);

        ctx.strategy.stop();
      });

      test('continues syncing other repos when onPushEvents throws', () async {
        final pushedRepos = <String>[];

        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(seconds: 100),
          repositoryNames: ['repo1', 'repo2'],
          onFetchEvents: (_) async => [],
          onPushEvents: (repoName, events) async {
            if (repoName == 'repo1') throw Exception('Push failed');
            pushedRepos.add(repoName);
            return true;
          },
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
        );

        final repo1 = _buildRepo('repo1');
        final repo2 = _buildRepo('repo2');
        final ctx = await _startInMemory(
          strategy: strategy,
          repos: [repo1, repo2],
        );

        await repo1.upsert({'id': '1'}, needSync: true);
        await repo2.upsert({'id': '2'}, needSync: true);
        await strategy.forceSync();

        // repo2 should still be attempted even if repo1 push threw
        expect(pushedRepos, contains('repo2'));

        ctx.strategy.stop();
      });
    });

    group('Pull with remote events', () {
      test('applies non-empty remote events to local storage', () async {
        var saveSyncStateCalled = false;

        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(seconds: 100),
          repositoryNames: ['test_repo'],
          onFetchEvents: (_) async => [_remoteInsertEvent(id: 'r1')],
          onPushEvents: (_, events) async => true,
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {
            saveSyncStateCalled = true;
          },
        );

        final ctx = await _startInMemory(strategy: strategy);

        expect(saveSyncStateCalled, isTrue);

        ctx.strategy.stop();
      });

      test('continues when onSaveSyncState throws', () async {
        var fetchCalled = false;

        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(seconds: 100),
          repositoryNames: ['test_repo'],
          onFetchEvents: (_) async {
            fetchCalled = true;
            return [_remoteInsertEvent(id: 'r2')];
          },
          onPushEvents: (_, events) async => true,
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {
            throw Exception('State save failed');
          },
        );

        final ctx = await _startInMemory(strategy: strategy);

        // Sync should have completed despite the onSaveSyncState error
        expect(fetchCalled, isTrue);
        expect(ctx.strategy.latestConnectionState, isTrue);

        ctx.strategy.stop();
      });

      test('continues syncing other repos when pull throws', () async {
        final fetchedRepos = <String>[];

        final strategy = PeriodicSyncStrategy(
          syncInterval: const Duration(seconds: 100),
          repositoryNames: ['repo1', 'repo2'],
          onFetchEvents: (repoName) async {
            fetchedRepos.add(repoName);
            if (repoName == 'repo1') throw Exception('Fetch failed');
            return [];
          },
          onPushEvents: (_, events) async => true,
          onBuildSyncFilter: (_) async => null,
          onSaveSyncState: (_, events) async {},
        );

        final ctx = await _startInMemory(
          strategy: strategy,
          repos: [_buildRepo('repo1'), _buildRepo('repo2')],
        );

        expect(fetchedRepos, containsAll(['repo1', 'repo2']));

        ctx.strategy.stop();
      });
    });
  });
}
