import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

class _StubStorage implements LocalFirstStorage {
  final List<JsonMap> events = [];
  final List<JsonMap> updatedEvents = [];
  bool containsIdReturn = false;
  int ensureSchemaCount = 0;
  int insertCount = 0;
  int updateCount = 0;
  int deleteCount = 0;
  int insertEventCount = 0;
  int updateEventCount = 0;
  JsonMap? lastInsertedData;
  JsonMap? lastUpdatedData;
  String? lastDeletedId;
  JsonMap? lastInsertedEvent;
  JsonMap? lastUpdatedEvent;

  @override
  Future<void> clearAllData() async {}

  @override
  Future<void> close() async {}

  @override
  Future<bool> containsId(String tableName, String id) async =>
      containsIdReturn;

  @override
  Future<void> delete(String repositoryName, String id) async {
    deleteCount++;
    lastDeletedId = id;
  }

  @override
  Future<void> deleteAll(String tableName) async {}

  @override
  Future<void> deleteAllEvents(String tableName) async {}

  @override
  Future<void> deleteEvent(String repositoryName, String id) async {
    deleteCount++;
  }

  @override
  Future<void> ensureSchema(
    String tableName,
    Map<String, LocalFieldType> schema, {
    required String idFieldName,
  }) async {
    ensureSchemaCount++;
  }

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
  Future<bool> removeConfig(String key) async => true;

  @override
  Future<bool> clearConfig() async => true;

  @override
  Future<Set<String>> getConfigKeys() async => {};

  @override
  Future<void> useNamespace(String namespace) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> insert(String tableName, JsonMap item, String idField) async {
    insertCount++;
    lastInsertedData = item;
  }

  @override
  Future<void> insertEvent(
    String tableName,
    JsonMap item,
    String idField,
  ) async {
    insertEventCount++;
    events.add(item);
    lastInsertedEvent = item;
  }

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
    lastUpdatedEvent = item;
  }

  @override
  Stream<List<LocalFirstEvent<T>>> watchQuery<T>(LocalFirstQuery<T> query) =>
      const Stream.empty();
}

class _DummyStrategy extends DataSyncStrategy {}

LocalFirstRepository<JsonMap> _buildRepo(_StubStorage storage) {
  final repo = LocalFirstRepository<JsonMap>.create(
    name: 'repo',
    getId: (item) => item['id'] as String,
    toJson: (item) => item,
    fromJson: (json) => json,
  );
  LocalFirstClient(
    repositories: [repo],
    localStorage: storage,
    syncStrategies: [_DummyStrategy()],
  );
  return repo;
}

LocalFirstRepository<JsonMap> _buildRepoWithStrategy(
  _StubStorage storage,
  DataSyncStrategy strategy,
) {
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
  return repo;
}

void main() {
  group('LocalFirstRepository', () {
    late _StubStorage storage;
    late LocalFirstRepository<JsonMap> repository;

    setUp(() {
      storage = _StubStorage();
      repository = _buildRepo(storage);
    });

    test('initialize should ensure schema only once until reset', () async {
      await repository.initialize();
      await repository.initialize();

      expect(storage.ensureSchemaCount, 1);

      repository.reset();
      await repository.initialize();
      expect(storage.ensureSchemaCount, 2);
    });

    test('upsert should insert when id does not exist', () async {
      storage.containsIdReturn = false;

      await repository.upsert({'id': '1'}, needSync: false);

      expect(storage.insertCount, 1);
      expect(storage.updateEventCount, 1);
      expect(storage.insertEventCount, 0);
    });

    test('upsert should update when id exists', () async {
      storage.containsIdReturn = true;

      await repository.upsert({'id': '1'}, needSync: false);

      expect(storage.updateCount, 1);
      expect(storage.updateEventCount, 1);
      expect(storage.insertCount, 0);
    });

    test('upsert should accept LocalFirstEvent payloads', () async {
      storage.containsIdReturn = false;
      await repository.upsert({'id': '1'}, needSync: false);

      expect(storage.insertCount, 1);
      expect(storage.updateEventCount, 1);
    });

    test('upsert should push event to sync strategies when needSync is true',
        () async {
      final strategy = _StrategyWithStatus(SyncStatus.ok);
      repository = _buildRepoWithStrategy(storage, strategy);

      await repository.upsert({'id': '1'}, needSync: true);

      expect(strategy.received, isNotEmpty);
      expect(storage.updateEventCount, greaterThan(0));
    });

    test('delete should log delete event and remove data', () async {
      final existing = LocalFirstEvent.createNewInsertEvent(
        repository: repository,
        data: {'id': '1'},
        needSync: false,
      );
      storage.events.add(existing.toLocalStorageJson());

      await repository.delete('1', needSync: true);

      expect(storage.deleteCount, 1);
      expect(storage.insertEventCount, 1);
      expect(
        storage.updatedEvents.map((e) => e[LocalFirstEvent.kEventId]),
        isNotEmpty,
      );
    });

    test('query should honor includeDeleted flag', () {
      final q1 = repository.query();
      final q2 = repository.query(includeDeleted: true);

      expect(q1.includeDeleted, isFalse);
      expect(q2.includeDeleted, isTrue);
      expect(q2.repository, same(repository));
    });

    test('getPendingEvents should return only events needing sync', () async {
      final pending = LocalFirstEvent.createNewInsertEvent(
        repository: repository,
        data: {'id': '1'},
        needSync: true,
      );
      final synced = LocalFirstEvent.createNewInsertEvent(
        repository: repository,
        data: {'id': '2'},
        needSync: false,
      );
      storage.events
        ..add(pending.toLocalStorageJson())
        ..add(synced.toLocalStorageJson());

      final result = await repository.getPendingEvents();

      expect(result.map((e) => e.dataId), ['1']);
    });

    test(
      'getLastRespectivePendingEvent should return latest pending for same id',
      () async {
        final older = LocalFirstEvent.createNewUpdateEvent(
          repository: repository,
          data: {'id': '1'},
          needSync: true,
        );
        final newer = LocalFirstEvent.createNewUpdateEvent(
          repository: repository,
          data: {'id': '1'},
          needSync: true,
        );
        final olderJson = older.toLocalStorageJson()
          ..[LocalFirstEvent.kSyncCreatedAt] = 1000;
        final newerJson = newer.toLocalStorageJson()
          ..[LocalFirstEvent.kSyncCreatedAt] = 2000;
        storage.events
          ..add(olderJson)
          ..add(newerJson);

        final result = await repository.getLastRespectivePendingEvent(
          reference: newer,
        );

        expect(result?.eventId, newer.eventId);
      },
    );

    test(
      '_markAllPreviousEventAsOk should update only older events for same data',
      () async {
        final target = LocalFirstEvent.createNewUpdateEvent(
          repository: repository,
          data: {'id': '1'},
          needSync: true,
        );
        final olderSame = LocalFirstEvent.createNewInsertEvent(
          repository: repository,
          data: {'id': '1'},
          needSync: true,
        );
        final newerSame = LocalFirstEvent.createNewUpdateEvent(
          repository: repository,
          data: {'id': '1'},
          needSync: true,
        );
        final otherId = LocalFirstEvent.createNewInsertEvent(
          repository: repository,
          data: {'id': '2'},
          needSync: true,
        );
        final olderJson = olderSame.toLocalStorageJson()
          ..[LocalFirstEvent.kSyncCreatedAt] = 1000;
        final targetJson = target.toLocalStorageJson()
          ..[LocalFirstEvent.kSyncCreatedAt] = 2000;
        final newerJson = newerSame.toLocalStorageJson()
          ..[LocalFirstEvent.kSyncCreatedAt] = 3000;
        final otherJson = otherId.toLocalStorageJson()
          ..[LocalFirstEvent.kSyncCreatedAt] = 1500;
        storage.events.addAll([olderJson, targetJson, newerJson, otherJson]);

        final helper = TestHelperLocalFirstRepository(repository);
        final reference = LocalFirstEvent<JsonMap>.fromLocalStorage(
          repository: repository,
          json: targetJson,
        );
        await helper.markAllPreviousEventAsOk(reference);

        // Only the older event for the same data id should be updated.
        expect(
          storage.updatedEvents.map((e) => e[LocalFirstEvent.kEventId]),
          contains(olderSame.eventId),
        );
        expect(
          storage.updatedEvents.map((e) => e[LocalFirstEvent.kEventId]),
          isNot(contains(newerSame.eventId)),
        );
        expect(
          storage.updatedEvents.map((e) => e[LocalFirstEvent.kEventId]),
          isNot(contains(otherId.eventId)),
        );
      },
    );

    test('mergeInsertEvent should insert when localPendingEvent is null',
        () async {
      final helper = TestHelperLocalFirstRepository(repository);
      final remote = LocalFirstEvent.createNewInsertEvent(
        repository: repository,
        data: {'id': '10'},
        needSync: false,
      ) as LocalFirstStateEvent<JsonMap>;

      await helper.mergeInsertEvent(
        remoteEvent: remote,
        localPendingEvent: null,
      );

      expect(storage.insertCount, 1);
      expect(storage.updateEventCount, greaterThan(0));
    });

    test('mergeInsertEvent should resolve conflict when pending exists',
        () async {
      final helper = TestHelperLocalFirstRepository(repository);
      final pending = LocalFirstEvent.createNewInsertEvent(
        repository: repository,
        data: {'id': '11'},
        needSync: true,
      ) as LocalFirstStateEvent<JsonMap>;
      final remote = LocalFirstEvent.createNewInsertEvent(
        repository: repository,
        data: {'id': '11'},
        needSync: false,
      ) as LocalFirstStateEvent<JsonMap>;

      await helper.mergeInsertEvent(
        remoteEvent: remote,
        localPendingEvent: pending,
      );

      expect(storage.updateCount + storage.insertCount, greaterThan(0));
      expect(storage.updateEventCount, greaterThan(0));
    });

    test('delete should pick latest event for same id before deleting', () async {
      final older = LocalFirstEvent.createNewInsertEvent(
        repository: repository,
        data: {'id': 'late'},
        needSync: false,
      ).toLocalStorageJson()
        ..[LocalFirstEvent.kSyncCreatedAt] = 10;
      final newer = LocalFirstEvent.createNewUpdateEvent(
        repository: repository,
        data: {'id': 'late'},
        needSync: false,
      ).toLocalStorageJson()
        ..[LocalFirstEvent.kSyncCreatedAt] = 20;
      storage.events.addAll([older, newer]);

      await repository.delete('late', needSync: true);

      expect(storage.deleteCount, 1);
      expect(storage.insertEventCount, 1);
    });

    test('delete should no-op when no prior event exists', () async {
      await repository.delete('ghost', needSync: true);

      expect(storage.deleteCount, 0);
      expect(storage.insertEventCount, 0);
    });

    test('mergeRemoteEvent should handle remote insert without pending',
        () async {
      final remote = LocalFirstEvent.createNewInsertEvent(
        repository: repository,
        data: {'id': 'remote-insert'},
        needSync: false,
      );

      await repository.mergeRemoteEvent(remoteEvent: remote);

      expect(storage.insertCount, greaterThan(0));
      expect(storage.updateEventCount + storage.insertEventCount, greaterThan(0));
    });

    test('mergeRemoteEvent should route update events', () async {
      final remote = LocalFirstEvent.createNewUpdateEvent(
        repository: repository,
        data: {'id': 'remote-update'},
        needSync: false,
      );

      await repository.mergeRemoteEvent(remoteEvent: remote);

      expect(storage.insertCount + storage.updateCount, greaterThan(0));
      expect(storage.updateEventCount, greaterThan(0));
    });

    test('mergeRemoteEvent should handle remote deletes', () async {
      final remoteDelete = LocalFirstEvent.createNewDeleteEvent<JsonMap>(
        repository: repository,
        dataId: 'to-remove',
        needSync: false,
      );

      await repository.mergeRemoteEvent(remoteEvent: remoteDelete);

      expect(storage.deleteCount, greaterThan(0));
      expect(storage.insertEventCount + storage.updateEventCount, greaterThan(0));
    });

    test('confirmEvent helper should persist confirmed pending event', () async {
      final helper = TestHelperLocalFirstRepository(repository);
      final localPending = LocalFirstEvent.createNewUpdateEvent(
        repository: repository,
        data: {'id': 'confirm'},
        needSync: true,
      );
      storage.events.add(localPending.toLocalStorageJson());
      final remote = localPending.updateEventState(syncStatus: SyncStatus.ok);

      await helper.confirmEvent(
        remoteEvent: remote,
        localPendingEvent: localPending,
      );

      expect(storage.updateEventCount, greaterThan(0));
    });

    test('mergeDeleteEvent helper should delete and mark previous as ok',
        () async {
      final helper = TestHelperLocalFirstRepository(repository);
      final remoteDelete = LocalFirstEvent.createNewDeleteEvent<JsonMap>(
        repository: repository,
        dataId: 'del',
        needSync: false,
      );

      await helper.mergeDeleteEvent(
        remoteEvent: remoteDelete,
        localPendingEvent: null,
      );

      expect(storage.deleteCount, 1);
      expect(storage.insertEventCount, 1);
    });

    test('resolveConflictEvent should use custom resolver when provided', () {
      final customRepo = LocalFirstRepository<JsonMap>.create(
        name: 'repo',
        getId: (item) => item['id'] as String,
        toJson: (item) => item,
        fromJson: (json) => json,
        onConflictEvent: (LocalFirstStateEvent<JsonMap> local,
                LocalFirstStateEvent<JsonMap> remote) =>
            local,
      );
      LocalFirstClient(
        repositories: [customRepo],
        localStorage: storage,
        syncStrategies: [_DummyStrategy()],
      );
      final LocalFirstStateEvent<JsonMap> local =
          LocalFirstEvent<JsonMap>.fromLocalStorage(
        repository: customRepo,
        json: {
          LocalFirstEvent.kEventId: 'local',
          LocalFirstEvent.kSyncStatus: SyncStatus.pending.index,
          LocalFirstEvent.kOperation: SyncOperation.update.index,
          LocalFirstEvent.kSyncCreatedAt: 2000,
          LocalFirstEvent.kDataId: '1',
          LocalFirstEvent.kData: {'id': '1'},
        },
      ) as LocalFirstStateEvent<JsonMap>;
      final LocalFirstStateEvent<JsonMap> remote =
          LocalFirstEvent<JsonMap>.fromLocalStorage(
        repository: customRepo,
        json: {
          LocalFirstEvent.kEventId: 'remote',
          LocalFirstEvent.kSyncStatus: SyncStatus.pending.index,
          LocalFirstEvent.kOperation: SyncOperation.update.index,
          LocalFirstEvent.kSyncCreatedAt: 3000,
          LocalFirstEvent.kDataId: '1',
          LocalFirstEvent.kData: {'id': '1'},
        },
      ) as LocalFirstStateEvent<JsonMap>;

      final resolved = customRepo.resolveConflictEvent(local, remote);

      expect(resolved, same(local));
    });

    test('resolveConflictEvent should default to lastWriteWins', () {
      final repo = _buildRepo(storage);
      final LocalFirstStateEvent<JsonMap> older =
          LocalFirstEvent<JsonMap>.fromLocalStorage(
        repository: repo,
        json: {
          LocalFirstEvent.kEventId: 'old',
          LocalFirstEvent.kSyncStatus: SyncStatus.pending.index,
          LocalFirstEvent.kOperation: SyncOperation.update.index,
          LocalFirstEvent.kSyncCreatedAt: 1000,
          LocalFirstEvent.kDataId: '1',
          LocalFirstEvent.kData: {'id': '1'},
        },
      ) as LocalFirstStateEvent<JsonMap>;
      final LocalFirstStateEvent<JsonMap> newer =
          LocalFirstEvent<JsonMap>.fromLocalStorage(
        repository: repo,
        json: {
          LocalFirstEvent.kEventId: 'new',
          LocalFirstEvent.kSyncStatus: SyncStatus.pending.index,
          LocalFirstEvent.kOperation: SyncOperation.update.index,
          LocalFirstEvent.kSyncCreatedAt: 2000,
          LocalFirstEvent.kDataId: '1',
          LocalFirstEvent.kData: {'id': '1'},
        },
      ) as LocalFirstStateEvent<JsonMap>;

      final resolved = repo.resolveConflictEvent(older, newer);

      expect(resolved, same(newer));
    });

    test(
      '_pushLocalEventToRemote should update status to ok on success',
      () async {
        final strategy = _StrategyWithStatus(SyncStatus.ok);
        final repo = _buildRepoWithStrategy(storage, strategy);
        final helper = TestHelperLocalFirstRepository(repo);
        final event = LocalFirstEvent.createNewInsertEvent(
          repository: repo,
          data: {'id': '1'},
          needSync: true,
        );

        final result = await helper.pushLocalEventToRemote(event);

        expect(strategy.received.single.syncStatus, SyncStatus.pending);
        expect(result.syncStatus, SyncStatus.ok);
        expect(storage.updateEventCount, greaterThan(0));
      },
    );

    test(
      '_pushLocalEventToRemote should mark failed when strategy throws',
      () async {
        final strategy = _StrategyThrows();
        final repo = _buildRepoWithStrategy(storage, strategy);
        final helper = TestHelperLocalFirstRepository(repo);
        final event = LocalFirstEvent.createNewInsertEvent(
          repository: repo,
          data: {'id': '1'},
          needSync: true,
        );

        final result = await helper.pushLocalEventToRemote(event);

        expect(result.syncStatus, SyncStatus.failed);
        expect(storage.updateEventCount, greaterThan(0));
      },
    );

    test('_getAllEvents should hydrate from storage', () async {
      final stored = LocalFirstEvent.createNewInsertEvent(
        repository: repository,
        data: {'id': '1'},
        needSync: true,
      );
      storage.events.add(stored.toLocalStorageJson());

      final helper = TestHelperLocalFirstRepository(repository);
      final events = await helper.getAllEvents();

      expect(events, hasLength(1));
      expect(events.single.dataId, '1');
    });

    test('persistEvent should delegate to updateEventRecord', () async {
      final helper = TestHelperLocalFirstRepository(repository);
      final event = LocalFirstEvent.createNewInsertEvent(
        repository: repository,
        data: {'id': '1'},
        needSync: true,
      );

      await helper.persistEvent(event);

      expect(storage.updateEventCount, 1);
    });

    test('insertEventRecord should write event', () async {
      final helper = TestHelperLocalFirstRepository(repository);
      final event = LocalFirstEvent.createNewInsertEvent(
        repository: repository,
        data: {'id': '1'},
        needSync: true,
      );

      await helper.insertEventRecord(event);

      expect(storage.insertEventCount, 1);
      expect(storage.events, isNotEmpty);
    });

    test('updateEventRecord should write update', () async {
      final helper = TestHelperLocalFirstRepository(repository);
      final event = LocalFirstEvent.createNewInsertEvent(
        repository: repository,
        data: {'id': '1'},
        needSync: true,
      );

      await helper.updateEventRecord(event);

      expect(storage.updateEventCount, 1);
    });

    test('insertDataFromEvent should write data', () async {
      final helper = TestHelperLocalFirstRepository(repository);
      final LocalFirstStateEvent<JsonMap> event =
          LocalFirstEvent.createNewInsertEvent(
                repository: repository,
                data: {'id': '1'},
                needSync: true,
              )
              as LocalFirstStateEvent<JsonMap>;

      await helper.insertDataFromEvent(event);

      expect(storage.insertCount, 1);
      expect(
        storage.lastInsertedData?[LocalFirstEvent.kLastEventId],
        event.eventId,
      );
    });

    test('updateDataFromEvent should write update', () async {
      final helper = TestHelperLocalFirstRepository(repository);
      final LocalFirstStateEvent<JsonMap> event =
          LocalFirstEvent.createNewUpdateEvent(
                repository: repository,
                data: {'id': '1'},
                needSync: true,
              )
              as LocalFirstStateEvent<JsonMap>;

      await helper.updateDataFromEvent(event);

      expect(storage.updateCount, 1);
      expect(
        storage.lastUpdatedData?[LocalFirstEvent.kLastEventId],
        event.eventId,
      );
    });

    test('insertDataAndEvent should insert both data and event', () async {
      final helper = TestHelperLocalFirstRepository(repository);
      final LocalFirstStateEvent<JsonMap> event =
          LocalFirstEvent.createNewInsertEvent(
                repository: repository,
                data: {'id': '1'},
                needSync: true,
              )
              as LocalFirstStateEvent<JsonMap>;

      await helper.insertDataAndEvent(event);

      expect(storage.insertCount, 1);
      expect(storage.updateEventCount, 1);
      expect(
        storage.lastInsertedData?[LocalFirstEvent.kLastEventId],
        event.eventId,
      );
      expect(
        storage.lastUpdatedEvent?[LocalFirstEvent.kEventId],
        event.eventId,
      );
    });

    test('updateDataAndEvent should update data and event', () async {
      final helper = TestHelperLocalFirstRepository(repository);
      final event = LocalFirstEvent.createNewUpdateEvent(
        repository: repository,
        data: {'id': '1'},
        needSync: true,
      );

      await helper.updateDataAndEvent(event);

      expect(storage.updateCount, 1);
      expect(storage.updateEventCount, 1);
      expect(
        storage.lastUpdatedData?[LocalFirstEvent.kLastEventId],
        event.eventId,
      );
      expect(
        storage.lastUpdatedEvent?[LocalFirstEvent.kEventId],
        event.eventId,
      );
    });

    test('deleteDataAndLogEvent should delete data and log event', () async {
      final helper = TestHelperLocalFirstRepository(repository);
      final event = LocalFirstEvent.createNewDeleteEvent<JsonMap>(
        repository: repository,
        dataId: '1',
        needSync: true,
      );

      await helper.deleteDataAndLogEvent(event);

      expect(storage.deleteCount, 1);
      expect(storage.insertEventCount, 1);
      expect(storage.lastDeletedId, '1');
      expect(
        storage.lastInsertedEvent?[LocalFirstEvent.kEventId],
        event.eventId,
      );
    });

    test('deleteDataById should delete from storage', () async {
      final helper = TestHelperLocalFirstRepository(repository);

      await helper.deleteDataById('1');

      expect(storage.deleteCount, 1);
    });

    test(
      'mergeRemoteEvent should confirm pending event when ids match',
      () async {
        final helper = TestHelperLocalFirstRepository(repository);
        final pending = LocalFirstEvent.createNewInsertEvent(
          repository: repository,
          data: {'id': '1'},
          needSync: true,
        );
        storage.events.add(pending.toLocalStorageJson());
        final remote = pending.updateEventState(syncStatus: SyncStatus.ok);

        await repository.mergeRemoteEvent(remoteEvent: remote);

        expect(storage.updateEventCount, greaterThan(0));
      },
    );

    test(
      'mergeUpdateEvent should insert when no pending local event exists',
      () async {
        final helper = TestHelperLocalFirstRepository(repository);
        final remote = LocalFirstEvent.createNewUpdateEvent(
          repository: repository,
          data: {'id': '2'},
          needSync: false,
        ) as LocalFirstStateEvent<JsonMap>;

        await helper.mergeUpdateEvent(
          remoteEvent: remote,
          localPendingEvent: null,
        );

        expect(storage.insertCount, 1);
        expect(storage.updateEventCount, greaterThan(0));
      },
    );

    test(
      'mergeUpdateEvent should update when matching pending event exists',
      () async {
        final helper = TestHelperLocalFirstRepository(repository);
        final pending = LocalFirstEvent.createNewUpdateEvent(
          repository: repository,
          data: {'id': '3'},
          needSync: true,
        );
        storage.events.add(pending.toLocalStorageJson());
        final remote = pending.updateEventState(syncStatus: SyncStatus.ok)
            as LocalFirstStateEvent<JsonMap>;

        await helper.mergeUpdateEvent(
          remoteEvent: remote,
          localPendingEvent: pending,
        );

        expect(storage.updateCount, greaterThan(0));
        expect(storage.updateEventCount, greaterThan(0));
      },
    );

    test(
      'mergeUpdateEvent should resolve conflicts when pending differs',
      () async {
        final helper = TestHelperLocalFirstRepository(repository);
        final pending = LocalFirstEvent.createNewUpdateEvent(
          repository: repository,
          data: {'id': 'conflict', 'value': 'local'},
          needSync: true,
        ) as LocalFirstStateEvent<JsonMap>;
        final remote = LocalFirstEvent.createNewUpdateEvent(
          repository: repository,
          data: {'id': 'conflict', 'value': 'remote'},
          needSync: false,
        ) as LocalFirstStateEvent<JsonMap>;
        storage.events.add(pending.toLocalStorageJson());

        await helper.mergeUpdateEvent(
          remoteEvent: remote,
          localPendingEvent: pending,
        );

        expect(storage.updateCount, greaterThan(0));
        expect(storage.updateEventCount, greaterThan(0));
      },
    );

    test(
      'updateEventStatus should update event (and data for state events)',
      () async {
        final helper = TestHelperLocalFirstRepository(repository);
        final stateEvent = LocalFirstEvent.createNewInsertEvent(
          repository: repository,
          data: {'id': '1'},
          needSync: true,
        );

        await helper.updateEventStatus(stateEvent);

        expect(storage.updateCount, 1);
        expect(storage.updateEventCount, 1);
        expect(storage.lastUpdatedData, isNotNull);
        expect(
          storage.lastUpdatedEvent?[LocalFirstEvent.kEventId],
          stateEvent.eventId,
        );

        storage.updateCount = 0;
        storage.updateEventCount = 0;
        storage.lastUpdatedData = null;
        final deleteEvent = LocalFirstEvent.createNewDeleteEvent<JsonMap>(
          repository: repository,
          dataId: '1',
          needSync: true,
        );

        await helper.updateEventStatus(deleteEvent);

        expect(storage.updateCount, 0);
        expect(storage.updateEventCount, 1);
        expect(storage.lastUpdatedData, isNull);
        expect(
          storage.lastUpdatedEvent?[LocalFirstEvent.kEventId],
          deleteEvent.eventId,
        );
      },
    );

    test('toDataJson should include lastEventId', () {
      final helper = TestHelperLocalFirstRepository(repository);
      final LocalFirstStateEvent<JsonMap> event =
          LocalFirstEvent.createNewInsertEvent(
                repository: repository,
                data: {'id': '1', 'field': 'value'},
                needSync: true,
              )
              as LocalFirstStateEvent<JsonMap>;

      final json = helper.toDataJson(event);

      expect(json[LocalFirstEvent.kLastEventId], event.eventId);
      expect(json['field'], 'value');
    });
  });
}

class _StrategyWithStatus extends DataSyncStrategy {
  final SyncStatus status;
  final List<LocalFirstEvent> received = [];

  _StrategyWithStatus(this.status);

  @override
  Future<SyncStatus> onPushToRemote(LocalFirstEvent localData) async {
    received.add(localData);
    return status;
  }
}

class _StrategyThrows extends DataSyncStrategy {
  @override
  Future<SyncStatus> onPushToRemote(LocalFirstEvent localData) =>
      Future.error('fail');
}
