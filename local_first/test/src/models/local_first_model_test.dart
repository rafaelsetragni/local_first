import 'package:flutter_test/flutter_test.dart';

import 'package:local_first/local_first.dart';

class _DummyModel {
  _DummyModel({required this.id, required this.value});

  final String id;
  final String value;

  Map<String, dynamic> toJson() => {'id': id, 'value': value};
}

void main() {
  group('LocalFirstEvent', () {
    test('defaults to ok/insert and createdAt set to now UTC', () {
      final event = LocalFirstEvent(
        payload: _DummyModel(id: '1', value: 'a'),
      );

      expect(event.syncStatus, SyncStatus.ok);
      expect(event.syncOperation, SyncOperation.insert);
      expect(event.syncCreatedAt, isA<DateTime>());
      expect(event.repositoryName, '');
      expect(event.needSync, isFalse);
      expect(event.isDeleted, isFalse);
    });

    test('needSync reflects pending or failed states', () {
      final base = LocalFirstEvent(payload: _DummyModel(id: '1', value: 'a'));
      final pending = base.copyWith(syncStatus: SyncStatus.pending);
      final failed = base.copyWith(syncStatus: SyncStatus.failed);

      expect(pending.needSync, isTrue);
      expect(failed.needSync, isTrue);
    });

    test('isDeleted reflects delete operation', () {
      final model = LocalFirstEvent(
        payload: _DummyModel(id: '1', value: 'a'),
        syncOperation: SyncOperation.delete,
      );

      expect(model.isDeleted, isTrue);
    });

    test('LocalFirstModelsX.toJson groups by operation', () {
      final insert = LocalFirstEvent(
        payload: _DummyModel(id: '1', value: 'one'),
        syncOperation: SyncOperation.insert,
      );
      final update = LocalFirstEvent(
        payload: _DummyModel(id: '2', value: 'two'),
        syncOperation: SyncOperation.update,
      );
      final delete = LocalFirstEvent(
        payload: _DummyModel(id: '3', value: 'three'),
        syncOperation: SyncOperation.delete,
      );

      final payload = [insert, update, delete].toJson((p) => p.toJson());

      expect(payload['insert'], [
        {'id': '1', 'value': 'one'},
      ]);
      expect(payload['update'], [
        {'id': '2', 'value': 'two'},
      ]);
      expect(payload['delete'], ['3']);
    });

    test('copyWith updates sync metadata immutably', () {
      final model = LocalFirstEvent(
        payload: _DummyModel(id: '1', value: 'x'),
      ).copyWith(
        syncStatus: SyncStatus.failed,
        syncOperation: SyncOperation.update,
        syncCreatedAt: DateTime.utc(2020, 1, 1),
        repositoryName: 'repo',
      );

      expect(model.syncStatus, SyncStatus.failed);
      expect(model.syncOperation, SyncOperation.update);
      expect(model.syncCreatedAt, DateTime.utc(2020, 1, 1));
      expect(model.repositoryName, 'repo');
      expect(model.needSync, isTrue);
    });
  });
}
