import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';

class _DummyModel {
  _DummyModel(this.id, {this.value});
  final String id;
  final String? value;

  JsonMap toJson() => {'id': id, if (value != null) 'value': value};
}

LocalFirstRepository<_DummyModel> _dummyRepo() {
  return LocalFirstRepository.create(
    name: 'dummy',
    getId: (m) => m.id,
    toJson: (m) => m.toJson(),
    fromJson: (j) =>
        _DummyModel(j['id'] as String, value: j['value'] as String?),
    onConflictEvent: (l, r) => r,
  );
}

LocalFirstRepository<dynamic> _dynamicRepo() {
  return LocalFirstRepository.create(
    name: 'dynamic',
    getId: (m) => (m as JsonMap)['id'] as String? ?? '',
    toJson: (m) => m as JsonMap,
    fromJson: (j) => j,
    onConflictEvent: (l, r) => r,
  );
}

LocalFirstRepository<JsonMap> _throwingRepo() {
  return LocalFirstRepository.create(
    name: 'throwing',
    getId: (m) => m['id'] as String? ?? '',
    toJson: (m) => m,
    fromJson: (j) => throw StateError('boom'),
    onConflictEvent: (l, r) => r,
  );
}

void main() {
  group('LocalFirstEvent', () {
    test('repositoryName getter should mirror repository', () {
      final repo = _dummyRepo();
      final event = LocalFirstEvent.createNewInsertEvent(
        repository: repo,
        needSync: false,
        data: _DummyModel('id-1'),
      );

      expect(event.repositoryName, repo.name);
    });

    group('createNewInsertEvent', () {
      group('edge cases', () {
        test('should create insert event when valid data provided', () {
          final repo = _dummyRepo();
          final data = _DummyModel('1', value: 'a');

          final event = LocalFirstEvent.createNewInsertEvent(
            repository: repo,
            needSync: true,
            data: data,
          );

          expect(event.syncOperation, SyncOperation.insert);
          expect(event.syncStatus, SyncStatus.pending);
          expect(event.dataId, '1');
          expect(event.data, same(data));
          expect(event.syncCreatedAt.isUtc, isTrue);
          expect(event.eventId, isNotEmpty);
        });
      });
      group('business rules', () {
        test('should derive dataId from repository getId for insert', () {
          final repo = _dummyRepo();
          final data = _DummyModel('123');

          final event = LocalFirstEvent.createNewInsertEvent(
            repository: repo,
            needSync: true,
            data: data,
          );

          expect(event.dataId, '123');
          expect(event.syncCreatedAt.isUtc, isTrue);
          expect(event.needSync, isTrue);
        });
        test('should generate event_id as ULID v7 for insert', () {
          final event = LocalFirstEvent.createNewInsertEvent(
            repository: _dummyRepo(),
            needSync: false,
            data: _DummyModel('1'),
          );

          expect(event.eventId, isNotEmpty);
          expect(event.eventId.length, greaterThanOrEqualTo(10));
        });
      });
    });

    group('createNewUpdateEvent', () {
      group('edge cases', () {
        test('should create update event when valid data provided', () {
          final repo = _dummyRepo();
          final event = LocalFirstEvent.createNewUpdateEvent(
            repository: repo,
            needSync: false,
            data: _DummyModel('1'),
          );

          expect(event.syncOperation, SyncOperation.update);
          expect(event.dataId, '1');
          expect(event.syncCreatedAt.isUtc, isTrue);
        });
      });
      group('business rules', () {
        test('should generate event_id as ULID v7 for update', () {
          final event = LocalFirstEvent.createNewUpdateEvent(
            repository: _dummyRepo(),
            needSync: false,
            data: _DummyModel('1'),
          );

          expect(event.eventId, isNotEmpty);
          expect(event.eventId.length, greaterThanOrEqualTo(10));
        });
      });
    });

    test('repositoryName should match repository', () {
      final repo = _dummyRepo();
      final event = LocalFirstEvent.createNewInsertEvent(
        repository: repo,
        needSync: false,
        data: _DummyModel('42'),
      );

      expect(event.repositoryName, repo.name);
    });

    group('createNewDeleteEvent', () {
      group('edge cases', () {
        test('should create delete event when dataId provided', () {
          final event = LocalFirstEvent.createNewDeleteEvent<_DummyModel>(
            repository: _dummyRepo(),
            needSync: true,
            dataId: '1',
          );

          expect(event.syncOperation, SyncOperation.delete);
          expect(event.dataId, '1');
          expect(event.syncCreatedAt.isUtc, isTrue);
        });
      });
      group('exceptions', () {
        test('should assert when delete factory used with dynamic type', () {
          expect(
            () => LocalFirstEvent.createNewDeleteEvent<dynamic>(
              repository: _dynamicRepo(),
              needSync: false,
              dataId: '1',
            ),
            throwsA(isA<AssertionError>()),
          );
        });
      });
      group('business rules', () {
        test('should generate event_id as ULID v7 for delete', () {
          final event = LocalFirstEvent.createNewDeleteEvent<_DummyModel>(
            repository: _dummyRepo(),
            needSync: false,
            dataId: '1',
          );

          expect(event.eventId, isNotEmpty);
        });
      });
    });

    group('fromLocalStorage', () {
      group('edge cases', () {
        test('should parse event when required fields are present', () {
          final repo = _dummyRepo();
          final now = DateTime.now().toUtc().millisecondsSinceEpoch;
          final json = {
            LocalFirstEvent.kEventId: 'evt-1',
            LocalFirstEvent.kDataId: '1',
            LocalFirstEvent.kSyncStatus: SyncStatus.ok.index,
            LocalFirstEvent.kOperation: SyncOperation.insert.index,
            LocalFirstEvent.kSyncCreatedAt: now,
            'id': '1',
          };

          final event = LocalFirstEvent<_DummyModel>.fromLocalStorage(
            repository: repo,
            json: json,
          );

          expect(event.eventId, 'evt-1');
          expect(event.syncOperation, SyncOperation.insert);
          expect(event.dataId, '1');
        });
      });
      group('exceptions', () {
        test('should throw when storage data is invalid', () {
          final repo = _dummyRepo();
          expect(
            () => LocalFirstEvent<_DummyModel>.fromLocalStorage(
              repository: repo,
              json: {},
            ),
            throwsFormatException,
          );
        });

        test('should throw when delete storage event is missing dataId', () {
          final repo = _dummyRepo();
          final now = DateTime.now().toUtc().millisecondsSinceEpoch;
          expect(
            () => LocalFirstEvent<_DummyModel>.fromLocalStorage(
              repository: repo,
              json: {
                LocalFirstEvent.kEventId: 'evt-del',
                LocalFirstEvent.kSyncStatus: SyncStatus.pending.index,
                LocalFirstEvent.kOperation: SyncOperation.delete.index,
                LocalFirstEvent.kSyncCreatedAt: now,
              },
            ),
            throwsFormatException,
          );
        });
      });
      group('business rules', () {
        test('should map storage fields to event properties', () {
          final repo = _dummyRepo();
          final now = DateTime.now().toUtc().millisecondsSinceEpoch;
          final json = {
            LocalFirstEvent.kEventId: 'evt-1',
            LocalFirstEvent.kDataId: '1',
            LocalFirstEvent.kSyncStatus: SyncStatus.pending.index,
            LocalFirstEvent.kOperation: SyncOperation.update.index,
            LocalFirstEvent.kSyncCreatedAt: now,
            'id': '1',
          };

          final event = LocalFirstEvent<_DummyModel>.fromLocalStorage(
            repository: repo,
            json: json,
          );

          expect(event.syncStatus, SyncStatus.pending);
          expect(event.syncOperation, SyncOperation.update);
          expect(event.dataId, '1');
        });
      });
    });

    group('fromRemoteJson', () {
      group('edge cases', () {
        test('should build event with correct sync defaults', () {
          final repo = _dummyRepo();
          final json = {
            LocalFirstEvent.kEventId: 'evt-remote',
            LocalFirstEvent.kOperation: SyncOperation.insert.index,
            LocalFirstEvent.kSyncCreatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
            LocalFirstEvent.kDataId: '1',
            LocalFirstEvent.kData: {'id': '1'},
          };

          final event = LocalFirstEvent.fromRemoteJson(
            repository: repo,
            json: json,
          );

          expect(event.syncStatus, SyncStatus.ok);
          expect(event.syncOperation, SyncOperation.insert);
          expect(event.dataId, '1');
        });

        test('should build delete event with dataId', () {
          final repo = _dummyRepo();
          final json = {
            LocalFirstEvent.kEventId: 'evt-del',
            LocalFirstEvent.kOperation: SyncOperation.delete.index,
            LocalFirstEvent.kSyncCreatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
            LocalFirstEvent.kDataId: '99',
          };

          final event =
              LocalFirstEvent.fromRemoteJson(repository: repo, json: json)
                  as LocalFirstDeleteEvent<_DummyModel>;

          expect(event.dataId, '99');
          expect(event.data, isNull);
        });

        test('should parse createdAt when provided as ISO string', () {
          final repo = _dummyRepo();
          final json = {
            LocalFirstEvent.kEventId: 'evt-remote',
            LocalFirstEvent.kOperation: SyncOperation.update.index,
            LocalFirstEvent.kSyncCreatedAt: DateTime.now().toUtc().toIso8601String(),
            LocalFirstEvent.kDataId: '1',
            LocalFirstEvent.kData: {'id': '1'},
          };

          final event = LocalFirstEvent.fromRemoteJson(
            repository: repo,
            json: json,
          );

          expect(event.syncCreatedAt.isUtc, isTrue);
        });

        test('should parse createdAt when provided as DateTime', () {
          final repo = _dummyRepo();
          final json = {
            LocalFirstEvent.kEventId: 'evt-remote',
            LocalFirstEvent.kOperation: SyncOperation.update.index,
            LocalFirstEvent.kSyncCreatedAt: DateTime.now(),
            LocalFirstEvent.kDataId: '1',
            LocalFirstEvent.kData: {'id': '1'},
          };

          final event = LocalFirstEvent.fromRemoteJson(
            repository: repo,
            json: json,
          );

          expect(event.syncCreatedAt.isUtc, isTrue);
        });

        test('should serialize delete events to remote/local formats', () {
          final repo = _dummyRepo();
          final event =
              LocalFirstEvent.createNewDeleteEvent<_DummyModel>(
                    repository: repo,
                    needSync: false,
                    dataId: 'del-1',
                  )
                  as LocalFirstDeleteEvent<_DummyModel>;

          final remote = event.toJson();
          final local = event.toLocalStorageJson();
          final updated = event.updateEventState(syncStatus: SyncStatus.failed);

          expect(remote[LocalFirstEvent.kDataId], 'del-1');
          expect(remote[LocalFirstEvent.kSyncCreatedAt], isA<DateTime>());
          expect(local[LocalFirstEvent.kSyncCreatedAt], isA<int>());
          expect(updated.syncStatus, SyncStatus.failed);
          expect(event.data, isNull);
        });
      });
      group('exceptions', () {
        test('should throw when remote payload is malformed', () {
          final repo = _dummyRepo();
          expect(
            () => LocalFirstEvent.fromRemoteJson(repository: repo, json: {}),
            throwsFormatException,
          );
        });

        test('should throw when createdAt is missing', () {
          final repo = _dummyRepo();
          expect(
            () => LocalFirstEvent.fromRemoteJson(
              repository: repo,
              json: {
                LocalFirstEvent.kEventId: 'evt-missing-date',
                LocalFirstEvent.kOperation: SyncOperation.insert.index,
                LocalFirstEvent.kDataId: '1',
                LocalFirstEvent.kData: {'id': '1'},
              },
            ),
            throwsFormatException,
          );
        });

        test('should throw when delete payload is missing dataId', () {
          final repo = _dummyRepo();
          expect(
            () => LocalFirstEvent.fromRemoteJson(
              repository: repo,
              json: {
                LocalFirstEvent.kEventId: 'evt-missing-id',
                LocalFirstEvent.kOperation: SyncOperation.delete.index,
                LocalFirstEvent.kSyncCreatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
              },
            ),
            throwsFormatException,
          );
        });

        test('should throw when state payload is missing for non-delete', () {
          final repo = _dummyRepo();
          expect(
            () => LocalFirstEvent.fromRemoteJson(
              repository: repo,
              json: {
                LocalFirstEvent.kEventId: 'evt-missing-state',
                LocalFirstEvent.kOperation: SyncOperation.insert.index,
                LocalFirstEvent.kSyncCreatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
                LocalFirstEvent.kDataId: '1',
              },
            ),
            throwsFormatException,
          );
        });

        test('should wrap unexpected parsing errors as FormatException', () {
          final repo = _throwingRepo();
          expect(
            () => LocalFirstEvent.fromRemoteJson(
              repository: repo,
              json: {
                LocalFirstEvent.kEventId: 'evt-throw',
                LocalFirstEvent.kOperation: SyncOperation.insert.index,
                LocalFirstEvent.kSyncCreatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
                LocalFirstEvent.kDataId: '1',
                LocalFirstEvent.kData: {'id': '1'},
              },
            ),
            throwsFormatException,
          );
        });
      });
    });

    group('toJson', () {
      group('business rules', () {
        test('should output normalized payload for remote', () {
          final repo = _dummyRepo();
          final event = LocalFirstEvent.createNewInsertEvent(
            repository: repo,
            needSync: false,
            data: _DummyModel('1', value: 'a'),
          );

          final json = event.toJson();

          expect(json[LocalFirstEvent.kEventId], event.eventId);
          expect(json[LocalFirstEvent.kOperation], SyncOperation.insert.index);
          expect(json[LocalFirstEvent.kDataId], '1');
          expect(json[LocalFirstEvent.kData], containsPair('id', '1'));
          expect(json[LocalFirstEvent.kSyncCreatedAt], isA<DateTime>());
        });
      });
    });

    group('toLocalStorageJson', () {
      group('business rules', () {
        test('should format timestamps as milliseconds since epoch', () {
          final repo = _dummyRepo();
          final event = LocalFirstEvent.createNewUpdateEvent(
            repository: repo,
            needSync: true,
            data: _DummyModel('1'),
          );

          final json = event.toLocalStorageJson();

          expect(json[LocalFirstEvent.kEventId], event.eventId);
          expect(json[LocalFirstEvent.kDataId], '1');
          expect(json[LocalFirstEvent.kSyncCreatedAt], isA<int>());
        });
      });
    });

    group('updateEventState', () {
      group('business rules', () {
        test('should override provided status and operation only', () {
          final repo = _dummyRepo();
          final original = LocalFirstEvent.createNewInsertEvent(
            repository: repo,
            needSync: true,
            data: _DummyModel('1'),
          );

          final updated = original.updateEventState(
            syncStatus: SyncStatus.ok,
            syncOperation: SyncOperation.update,
          );

          expect(updated.syncStatus, SyncStatus.ok);
          expect(updated.syncOperation, SyncOperation.update);
          expect(updated.syncCreatedAt, original.syncCreatedAt);
          expect(updated.eventId, original.eventId);
        });

        test('delete events should preserve dataId when updating status', () {
          final repo = _dummyRepo();
          final delete =
              LocalFirstEvent.createNewDeleteEvent<_DummyModel>(
                    repository: repo,
                    needSync: true,
                    dataId: 'dead-1',
                  )
                  as LocalFirstDeleteEvent<_DummyModel>;

          final updated = delete.updateEventState(syncStatus: SyncStatus.ok);

          expect(updated.dataId, 'dead-1');
          expect(updated.syncStatus, SyncStatus.ok);
          expect(updated.data, isNull);
        });

        test('delete updateEventState should default to existing status', () {
          final repo = _dummyRepo();
          final delete =
              LocalFirstEvent.createNewDeleteEvent<_DummyModel>(
                    repository: repo,
                    needSync: true,
                    dataId: 'dead-2',
                  )
                  as LocalFirstDeleteEvent<_DummyModel>;

          final updated = delete.updateEventState();

          expect(updated.syncStatus, delete.syncStatus);
          expect(updated.syncOperation, delete.syncOperation);
        });
      });
    });

    group('LocalFirstEventsToJson extension', () {
      test('should serialize list of events to remote JSON array', () {
        final repo = _dummyRepo();
        final insert = LocalFirstEvent.createNewInsertEvent(
          repository: repo,
          needSync: false,
          data: _DummyModel('1'),
        );
        final delete = LocalFirstEvent.createNewDeleteEvent<_DummyModel>(
          repository: repo,
          needSync: false,
          dataId: '1',
        );

        final payload = [insert, delete].toJson();

        expect(payload, hasLength(2));
        expect(payload.first[LocalFirstEvent.kData], isNotNull);
        expect(
          payload.last[LocalFirstEvent.kOperation],
          SyncOperation.delete.index,
        );
      });
    });
  });
}
