import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

class _SpyStorage implements LocalFirstStorage {
  int initialized = 0;
  int cleared = 0;
  int closed = 0;
  int namespaceChanges = 0;
  final Map<String, Object?> meta = {};

  @override
  Future<void> clearAllData() async {
    cleared++;
  }

  @override
  Future<void> close() async {
    closed++;
  }

  @override
  Future<void> useNamespace(String namespace) async {
    namespaceChanges++;
  }

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
    Map<String, LocalFieldType> schema, {
    required String idFieldName,
  }) async {}

  @override
  Future<List<Map<String, dynamic>>> getAll(String tableName) async => [];

  @override
  Future<List<Map<String, dynamic>>> getAllEvents(String tableName) async => [];

  @override
  Future<Map<String, dynamic>?> getById(String tableName, String id) async =>
      null;

  @override
  Future<Map<String, dynamic>?> getEventById(
    String tableName,
    String id,
  ) async => null;

  @override
  Future<bool> containsConfigKey(String key) async => meta.containsKey(key);

  @override
  Future<T?> getConfigValue<T>(String key) async => meta[key] as T?;

  @override
  Future<void> initialize() async {
    initialized++;
  }

  @override
  Future<void> insert(
    String tableName,
    Map<String, dynamic> item,
    String idField,
  ) async {}

  @override
  Future<void> insertEvent(
    String tableName,
    Map<String, dynamic> item,
    String idField,
  ) async {}

  @override
  Future<List<LocalFirstEvent<T>>> query<T>(LocalFirstQuery<T> query) async =>
      [];

  @override
  Future<bool> setConfigValue<T>(String key, T value) async {
    meta[key] = value;
    return true;
  }

  @override
  Future<bool> removeConfig(String key) async {
    meta.remove(key);
    return true;
  }

  @override
  Future<bool> clearConfig() async {
    meta.clear();
    return true;
  }

  @override
  Future<Set<String>> getConfigKeys() async => meta.keys.toSet();

  @override
  Future<void> update(
    String tableName,
    String id,
    Map<String, dynamic> item,
  ) async {}

  @override
  Future<void> updateEvent(
    String tableName,
    String id,
    Map<String, dynamic> item,
  ) async {}

  @override
  Stream<List<LocalFirstEvent<T>>> watchQuery<T>(LocalFirstQuery<T> query) =>
      const Stream.empty();
}

class _SpyConfigStorage implements ConfigKeyValueStorage {
  int initialized = 0;
  int closed = 0;
  int namespaceChanges = 0;
  final Map<String, Object?> meta = {};

  @override
  Future<bool> clearConfig() async {
    meta.clear();
    return true;
  }

  @override
  Future<bool> containsConfigKey(String key) async => meta.containsKey(key);

  @override
  Future<bool> removeConfig(String key) async {
    meta.remove(key);
    return true;
  }

  @override
  Future<bool> setConfigValue<T>(String key, T value) async {
    meta[key] = value;
    return true;
  }

  @override
  Future<T?> getConfigValue<T>(String key) async => meta[key] as T?;

  @override
  Future<Set<String>> getConfigKeys() async => meta.keys.toSet();

  @override
  Future<void> close() async {
    closed++;
  }

  @override
  Future<void> initialize() async {
    initialized++;
  }

  @override
  Future<void> useNamespace(String namespace) async {
    namespaceChanges++;
  }
}

class _SpyRepository extends LocalFirstRepository<dynamic> {
  _SpyRepository(String name)
    : super(
        name: name,
        getId: (item) => item['id'] as String,
        toJson: (item) => item,
        fromJson: (json) => json,
      );

  bool initialized = false;
  bool resetCalled = false;
  int pendingCalls = 0;
  List<LocalFirstEvent<dynamic>> pendingToReturn = const [];
  final List<LocalFirstEvent<dynamic>> mergedRemote = [];

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> reset() async {
    resetCalled = true;
  }

  @override
  Future<List<LocalFirstEvent<dynamic>>> getPendingEvents() async {
    pendingCalls++;
    return pendingToReturn;
  }

  @override
  Future<void> mergeRemoteEvent({
    required LocalFirstEvent<dynamic> remoteEvent,
  }) async {
    mergedRemote.add(remoteEvent);
  }
}

class _SpyStrategy extends DataSyncStrategy {
  LocalFirstClient? attached;

  @override
  void attach(LocalFirstClient client) {
    attached = client;
    super.attach(client);
  }
}

void main() {
  group('LocalFirstClient', () {
    late _SpyStorage storage;
    late _SpyStrategy strategy;

    setUp(() {
      storage = _SpyStorage();
      strategy = _SpyStrategy();
    });

    test('should allow creation without sync strategies', () {
      final client = LocalFirstClient(
        repositories: [],
        localStorage: storage,
        syncStrategies: [],
      );
      expect(client.syncStrategies, isEmpty);
    });

    test('should throw on duplicate repository names', () {
      final repo1 = _SpyRepository('repo');
      final repo2 = _SpyRepository('repo');

      expect(
        () => LocalFirstClient(
          repositories: [repo1, repo2],
          localStorage: storage,
          syncStrategies: [strategy],
        ),
        throwsArgumentError,
      );
    });

    test('should attach strategy and expose client', () {
      final repo = _SpyRepository('r1');
      final client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        syncStrategies: [strategy],
      );

      expect(strategy.attached, same(client));
    });

    test('should initialize storage and repositories', () async {
      final repo = _SpyRepository('r1');
      final client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        syncStrategies: [strategy],
      );

      await client.initialize();
      await client.awaitInitialization;

      expect(storage.initialized, 1);
      expect(repo.initialized, isTrue);
    });

    test('should clear data and reinitialize repositories', () async {
      final repo = _SpyRepository('r1');
      final client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        syncStrategies: [strategy],
      );

      await client.clearAllData();

      expect(storage.cleared, 1);
      expect(repo.resetCalled, isTrue);
      expect(repo.initialized, isTrue);
    });

    test('should dispose storage and close connection stream', () async {
      final repo = _SpyRepository('r1');
      final client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        syncStrategies: [strategy],
      );
      await client.dispose();

      expect(storage.closed, 1);
      expect(client.latestConnectionState, isNull);
      // Should not throw when reporting after dispose.
      client.reportConnectionState(true);
    });

    test('should return repository by name', () {
      final repo = _SpyRepository('r1');
      final client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        syncStrategies: [strategy],
      );

      expect(client.getRepositoryByName('r1'), same(repo));
      expect(() => client.getRepositoryByName('missing'), throwsStateError);
    });

    test('should stream connection changes', () async {
      final repo = _SpyRepository('r1');
      final client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        syncStrategies: [strategy],
      );
      final values = <bool>[];
      final sub = client.connectionChanges.listen(values.add);

      client.reportConnectionState(true);
      client.reportConnectionState(false);
      await Future<void>.delayed(Duration.zero);

      expect(values, [true, false]);
      expect(client.latestConnectionState, isFalse);
      await sub.cancel();
    });

    test('should pull changes and forward to repository', () async {
      final repo = _SpyRepository('r1');
      final client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        syncStrategies: [strategy],
      );
      final payload = {
        LocalFirstEvent.kEventId: IdUtil.uuidV7(),
        LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
        LocalFirstEvent.kOperation: SyncOperation.insert.index,
        LocalFirstEvent.kSyncCreatedAt: DateTime.now()
            .toUtc()
            .millisecondsSinceEpoch,
        LocalFirstEvent.kDataId: '1',
        LocalFirstEvent.kData: {'id': '1'},
      };

      await client.pullChanges(repositoryName: 'r1', changes: [payload]);

      expect(repo.mergedRemote, hasLength(1));
      expect(repo.mergedRemote.single.dataId, '1');
    });

    test('should throw on malformed remote events', () async {
      final repo = _SpyRepository('r1');
      final client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        syncStrategies: [strategy],
      );

      expect(
        () => client.pullChanges(
          repositoryName: 'r1',
          changes: [
            {LocalFirstEvent.kEventId: 'invalid'},
          ],
        ),
        throwsFormatException,
      );
    });

    test('should get pending events for repository', () async {
      final repo1 = _SpyRepository('r1')..pendingToReturn = [];
      final repo2 = _SpyRepository('r2')..pendingToReturn = [];
      final client = LocalFirstClient(
        repositories: [repo1, repo2],
        localStorage: storage,
        syncStrategies: [strategy],
      );

      repo1.pendingToReturn = [
        LocalFirstEvent.createNewInsertEvent(
          repository: repo1,
          data: {'id': '1'},
          needSync: true,
        ),
      ];
      repo2.pendingToReturn = [
        LocalFirstEvent.createNewInsertEvent(
          repository: repo2,
          data: {'id': '2'},
          needSync: true,
        ),
      ];

      final result = await client.getAllPendingEvents(repositoryName: 'r1');

      expect(result.map((e) => e.dataId), ['1']);
      expect(repo1.pendingCalls, 1);
      expect(repo2.pendingCalls, 0);
    });

    test('should delegate meta operations to storage', () async {
      final repo = _SpyRepository('r1');
      final client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        syncStrategies: [strategy],
      );

      await client.setConfigValue('k', 'v');
      final value = await client.getConfigValue('k');

      expect(value, 'v');
    });

    test(
      'should delegate meta operations to provided key-value storage',
      () async {
        final repo = _SpyRepository('r1');
        final configStorage = _SpyConfigStorage();
        final client = LocalFirstClient(
          repositories: [repo],
          localStorage: storage,
          keyValueStorage: configStorage,
          syncStrategies: [strategy],
        );

        await client.initialize();
        await client.setConfigValue('k', 'v');

        expect(configStorage.meta['k'], 'v');
        expect(storage.meta['k'], isNull);
        expect(configStorage.initialized, 1);

        await client.dispose();
        expect(configStorage.closed, 1);
      },
    );

    test('useNamespace propagates to both storages when different', () async {
      final repo = _SpyRepository('r1');
      final configStorage = _SpyConfigStorage();
      final client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        keyValueStorage: configStorage,
        syncStrategies: [strategy],
      );

      await client.useNamespace('ns1');
      expect(storage.namespaceChanges, 1);
      expect(configStorage.namespaceChanges, 1);
    });

    test('TestHelperLocalFirstClient should expose internals for testing', () {
      final repo = _SpyRepository('r1');
      final client = LocalFirstClient(
        repositories: [repo],
        localStorage: storage,
        syncStrategies: [strategy],
      );
      final helper = TestHelperLocalFirstClient(client);

      expect(helper.repositories.single, same(repo));
      expect(helper.onInitializeCompleter.isCompleted, isFalse);
      expect(helper.connectionController.isClosed, isFalse);
      expect(helper.latestConnection, isNull);
      helper.connectionController.add(true);
    });
  });
}
