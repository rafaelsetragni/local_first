import 'package:flutter_test/flutter_test.dart';

import 'package:local_first/local_first.dart';

class _DummyModel with LocalFirstModel {
  _DummyModel({required this.id, required this.value});

  final String id;
  final String value;

  @override
  Map<String, dynamic> toJson() => {'id': id, 'value': value};
}

void main() {
  group('LocalFirstModel mixin', () {
    test('defaults to ok/insert and no createdAt', () {
      final model = _DummyModel(id: '1', value: 'a');

      expect(model.syncStatus, SyncStatus.ok);
      expect(model.syncOperation, SyncOperation.insert);
      expect(model.syncCreatedAt, isNull);
      expect(model.repositoryName, '');
      expect(model.needSync, isFalse);
      expect(model.isDeleted, isFalse);
    });

    test('needSync reflects pending or failed states', () {
      final pending = _DummyModel(id: '1', value: 'a')
        ..debugSetSyncStatus(SyncStatus.pending);
      final failed = _DummyModel(id: '2', value: 'b')
        ..debugSetSyncStatus(SyncStatus.failed);

      expect(pending.needSync, isTrue);
      expect(failed.needSync, isTrue);
    });

    test('isDeleted reflects delete operation', () {
      final model = _DummyModel(id: '1', value: 'a')
        ..debugSetSyncOperation(SyncOperation.delete);

      expect(model.isDeleted, isTrue);
    });

    test('LocalFirstModelsX.toJson groups by operation', () {
      final insert = _DummyModel(id: '1', value: 'one')
        ..debugSetSyncOperation(SyncOperation.insert);
      final update = _DummyModel(id: '2', value: 'two')
        ..debugSetSyncOperation(SyncOperation.update);
      final delete = _DummyModel(id: '3', value: 'three')
        ..debugSetSyncOperation(SyncOperation.delete);

      final payload = [insert, update, delete].toJson();

      expect(payload['insert'], [
        {'id': '1', 'value': 'one'},
      ]);
      expect(payload['update'], [
        {'id': '2', 'value': 'two'},
      ]);
      expect(payload['delete'], ['3']);
    });

    test('debug setters update sync metadata internally', () {
      final model = _DummyModel(id: '1', value: 'x')
        ..debugSetSyncStatus(SyncStatus.failed)
        ..debugSetSyncOperation(SyncOperation.update)
        ..debugSetSyncCreatedAt(DateTime.utc(2020, 1, 1))
        ..debugSetRepositoryName('repo');

      expect(model.syncStatus, SyncStatus.failed);
      expect(model.syncOperation, SyncOperation.update);
      expect(model.syncCreatedAt, DateTime.utc(2020, 1, 1));
      expect(model.repositoryName, 'repo');
      expect(model.needSync, isTrue);
    });
  });
}
