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
      final pending = LocalFirstEvent(
        data: _DummyModel(id: '1', value: 'a'),
        syncStatus: SyncStatus.pending,
      );
      final failed = LocalFirstEvent(
        data: _DummyModel(id: '2', value: 'b'),
        syncStatus: SyncStatus.failed,
      );

      expect(pending.needSync, isTrue);
      expect(failed.needSync, isTrue);
    });

    test('isDeleted reflects delete operation', () {
      final event = LocalFirstEvent(
        data: _DummyModel(id: '1', value: 'a'),
        syncOperation: SyncOperation.delete,
      );

      expect(event.isDeleted, isTrue);
    });

    test('LocalFirstEventsX.toJson groups by operation', () {
      final insert = LocalFirstEvent(
        data: _DummyModel(id: '1', value: 'one'),
        syncOperation: SyncOperation.insert,
      );
      final update = LocalFirstEvent(
        data: _DummyModel(id: '2', value: 'two'),
        syncOperation: SyncOperation.update,
      );
      final delete = LocalFirstEvent(
        data: _DummyModel(id: '3', value: 'three'),
        syncOperation: SyncOperation.delete,
      );

      final payload = [insert, update, delete].toJson<_DummyModel>(
        serializer: (model) => model.toJson(),
      );

      final inserts = payload['insert'] as List;
      final updates = payload['update'] as List;
      expect(inserts, hasLength(1));
      expect(updates, hasLength(1));
      expect(
        inserts.first,
        {
          'id': '1',
          'value': 'one',
          'event_id': isA<String>(),
        },
      );
      expect(
        updates.first,
        {
          'id': '2',
          'value': 'two',
          'event_id': isA<String>(),
        },
      );
      expect(payload['delete'], ['3']);
    });

    test('LocalFirstEventsX.toJson uses default id field for deletes', () {
      final delete = LocalFirstEvent(
        data: _DummyModel(id: '9', value: 'nine'),
        syncOperation: SyncOperation.delete,
      );

      final payload = [delete].toJson<_DummyModel>(
        serializer: (model) => model.toJson(),
      );

      expect(payload['delete'], ['9']);
      expect(payload['insert'], isEmpty);
      expect(payload['update'], isEmpty);
    });

    test('LocalFirstEventsX.toJson uses custom id field for deletes', () {
      final delete = LocalFirstEvent(
        data: _UuidModel(uuid: '3'),
        syncOperation: SyncOperation.delete,
      );

      final payload = [delete].toJson<_UuidModel>(
        serializer: (model) => model.toJson(),
        idFieldName: 'uuid',
      );

      expect(payload['delete'], ['3']);
      expect(payload['insert'], isEmpty);
      expect(payload['update'], isEmpty);
    });

    test('constructor sets sync metadata', () {
      final event = LocalFirstEvent(
        data: _DummyModel(id: '1', value: 'x'),
        syncStatus: SyncStatus.failed,
        syncOperation: SyncOperation.update,
        syncCreatedAt: DateTime.utc(2020, 1, 1),
        syncCreatedAtServer: DateTime.utc(2020, 1, 2),
        repositoryName: 'repo',
      );

      expect(event.syncStatus, SyncStatus.failed);
      expect(event.syncOperation, SyncOperation.update);
      expect(event.syncCreatedAt, DateTime.utc(2020, 1, 1));
      expect(event.syncCreatedAtServer, DateTime.utc(2020, 1, 2));
      expect(event.repositoryName, 'repo');
      expect(event.needSync, isTrue);
    });

    test('copyWith updates fields while keeping original intact', () {
      final original = LocalFirstEvent(
        data: _DummyModel(id: '1', value: 'x'),
        syncStatus: SyncStatus.pending,
        syncOperation: SyncOperation.insert,
        syncCreatedAt: DateTime.utc(2020, 1, 1),
        repositoryName: 'repo',
      );

      final updated = original.copyWith(
        syncStatus: SyncStatus.ok,
        syncOperation: SyncOperation.update,
        syncCreatedAtServer: DateTime.utc(2020, 1, 2),
      );

      expect(original.syncStatus, SyncStatus.pending);
      expect(original.syncOperation, SyncOperation.insert);
      expect(original.syncCreatedAtServer, isNull);

      expect(updated.syncStatus, SyncStatus.ok);
      expect(updated.syncOperation, SyncOperation.update);
      expect(updated.syncCreatedAt, DateTime.utc(2020, 1, 1));
      expect(updated.syncCreatedAtServer, DateTime.utc(2020, 1, 2));
      expect(updated.repositoryName, 'repo');
    });
  });
}
