import 'package:flutter_test/flutter_test.dart';

import 'package:local_first/local_first.dart';

class _DummyModel {
  _DummyModel({required this.id, required this.value});

  final String id;
  final String value;
  Map<String, dynamic> toJson() => {'id': id, 'value': value};
}

class _UuidModel {
  _UuidModel({required this.uuid});

  final String uuid;
  Map<String, dynamic> toJson() => {'uuid': uuid};
}

void main() {
  group('LocalFirstEvent', () {
    test('defaults to ok/insert and no createdAt', () {
      final event = LocalFirstEvent(data: _DummyModel(id: '1', value: 'a'));

      expect(event.syncStatus, SyncStatus.ok);
      expect(event.syncOperation, SyncOperation.insert);
      expect(event.syncCreatedAt, isNull);
      expect(event.repositoryName, '');
      expect(event.needSync, isFalse);
      expect(event.isDeleted, isFalse);
    });

    test('needSync reflects pending or failed states', () {
      final pending = LocalFirstEvent(data: _DummyModel(id: '1', value: 'a'))
        ..debugSetSyncStatus(SyncStatus.pending);
      final failed = LocalFirstEvent(data: _DummyModel(id: '2', value: 'b'))
        ..debugSetSyncStatus(SyncStatus.failed);

      expect(pending.needSync, isTrue);
      expect(failed.needSync, isTrue);
    });

    test('isDeleted reflects delete operation', () {
      final event = LocalFirstEvent(data: _DummyModel(id: '1', value: 'a'))
        ..debugSetSyncOperation(SyncOperation.delete);

      expect(event.isDeleted, isTrue);
    });

    test('LocalFirstEventsX.toJson groups by operation', () {
      final insert =
          LocalFirstEvent(data: _DummyModel(id: '1', value: 'one'))
            ..debugSetSyncOperation(SyncOperation.insert);
      final update =
          LocalFirstEvent(data: _DummyModel(id: '2', value: 'two'))
            ..debugSetSyncOperation(SyncOperation.update);
      final delete =
          LocalFirstEvent(data: _DummyModel(id: '3', value: 'three'))
            ..debugSetSyncOperation(SyncOperation.delete);

      final payload = [insert, update, delete].toJson<_DummyModel>(
        serializer: (model) => model.toJson(),
      );

      expect(payload['insert'], [
        {'id': '1', 'value': 'one'},
      ]);
      expect(payload['update'], [
        {'id': '2', 'value': 'two'},
      ]);
      expect(payload['delete'], ['3']);
    });

    test('LocalFirstEventsX.toJson uses default id field for deletes', () {
      final delete =
          LocalFirstEvent(data: _DummyModel(id: '9', value: 'nine'))
            ..debugSetSyncOperation(SyncOperation.delete);

      final payload = [delete].toJson<_DummyModel>(
        serializer: (model) => model.toJson(),
      );

      expect(payload['delete'], ['9']);
      expect(payload['insert'], isEmpty);
      expect(payload['update'], isEmpty);
    });

    test('LocalFirstEventsX.toJson uses custom id field for deletes', () {
      final delete = LocalFirstEvent(data: _UuidModel(uuid: '3'))
        ..debugSetSyncOperation(SyncOperation.delete);

      final payload = [delete].toJson<_UuidModel>(
        serializer: (model) => model.toJson(),
        idFieldName: 'uuid',
      );

      expect(payload['delete'], ['3']);
      expect(payload['insert'], isEmpty);
      expect(payload['update'], isEmpty);
    });

    test('debug setters update sync metadata internally', () {
      final event = LocalFirstEvent(data: _DummyModel(id: '1', value: 'x'))
        ..debugSetSyncStatus(SyncStatus.failed)
        ..debugSetSyncOperation(SyncOperation.update)
        ..debugSetSyncCreatedAt(DateTime.utc(2020, 1, 1))
        ..debugSetRepositoryName('repo');

      expect(event.syncStatus, SyncStatus.failed);
      expect(event.syncOperation, SyncOperation.update);
      expect(event.syncCreatedAt, DateTime.utc(2020, 1, 1));
      expect(event.repositoryName, 'repo');
      expect(event.needSync, isTrue);
    });
  });
}
