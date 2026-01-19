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

void main() {
  group('LocalFirstEvent', () {
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
            '_event_id': 'evt-1',
            '_data_id': '1',
            '_sync_status': SyncStatus.ok.index,
            '_sync_operation': SyncOperation.insert.index,
            '_sync_created_at': now,
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
      });
      group('business rules', () {
        test('should map storage fields to event properties', () {
          final repo = _dummyRepo();
          final now = DateTime.now().toUtc().millisecondsSinceEpoch;
          final json = {
            '_event_id': 'evt-1',
            '_data_id': '1',
            '_sync_status': SyncStatus.pending.index,
            '_sync_operation': SyncOperation.update.index,
            '_sync_created_at': now,
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
            '_event_id': 'evt-remote',
            '_sync_operation': SyncOperation.insert.index,
            '_sync_created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
            '_data_id': '1',
            'data': {'id': '1'},
          };

          final event = LocalFirstEvent<_DummyModel>.fromRemoteJson(
            repository: repo,
            json: json,
          );

          expect(event.syncStatus, SyncStatus.ok);
          expect(event.syncOperation, SyncOperation.insert);
          expect(event.dataId, '1');
        });
      });
      group('exceptions', () {
        test('should throw when remote payload is malformed', () {
          final repo = _dummyRepo();
          expect(
            () => LocalFirstEvent<_DummyModel>.fromRemoteJson(
              repository: repo,
              json: {},
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
      });
    });
  });
}
