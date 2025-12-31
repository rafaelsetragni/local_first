import 'package:flutter_test/flutter_test.dart';

import 'package:local_first/local_first.dart';

class _DummyModel {
  _DummyModel({required this.id, required this.value});

  final String id;
  final String value;
  JsonMap toJson() => {'id': id, 'value': value};
}

void main() {
  group('LocalFirstEvent parameters', () {
    LocalFirstEvent _event({
      String id = '1',
      String value = 'v',
      String repo = 'repo',
      SyncStatus status = SyncStatus.ok,
      SyncOperation op = SyncOperation.insert,
      DateTime? createdAt,
      DateTime? createdAtServer,
      int? seq,
      String? eventId,
    }) {
      return LocalFirstEvent(
        data: _DummyModel(id: id, value: value),
        repositoryName: repo,
        syncStatus: status,
        syncOperation: op,
        syncCreatedAt: createdAt,
        syncCreatedAtServer: createdAtServer,
        syncServerSequence: seq,
        eventId: eventId,
      );
    }

    test('data is stored and typed correctly', () {
      final model = _DummyModel(id: '1', value: 'v');
      final event = LocalFirstEvent(
        data: model,
        repositoryName: 'repo',
        syncOperation: SyncOperation.insert,
        syncStatus: SyncStatus.ok,
      );
      expect(event.dataAs<_DummyModel>(), same(model));
      expect(event.isA<_DummyModel>(), isTrue);
      expect(event.isA<String>(), isFalse);
    });

    test('eventId auto-generates when not provided', () {
      final event = _event();
      expect(event.eventId, isNotEmpty);
    });

    test('eventId auto-generates must not repeat for different events', () {
      final e1 = _event();
      final e2 = _event();
      final e3 = _event();
      final ids = {e1.eventId, e2.eventId, e3.eventId};
      expect(ids.length, 3);
    });

    test('eventId uses provided value', () {
      final empty = _event(eventId: '');
      final oneChar = _event(eventId: 'a');
      final twoChars = _event(eventId: 'ab');
      final custom = _event(eventId: 'custom-id');

      expect(empty.eventId, '');
      expect(oneChar.eventId, 'a');
      expect(twoChars.eventId, 'ab');
      expect(custom.eventId, 'custom-id');
    });

    test('syncStatus accepts custom value', () {
      final pending = _event(status: SyncStatus.pending);
      final ok = _event(status: SyncStatus.ok);
      final failed = _event(status: SyncStatus.failed);

      expect(pending.syncStatus, SyncStatus.pending);
      expect(pending.needSync, isTrue);

      expect(ok.syncStatus, SyncStatus.ok);
      expect(ok.needSync, isFalse);

      expect(failed.syncStatus, SyncStatus.failed);
      expect(failed.needSync, isTrue);
    });

    test('syncOperation accepts custom value', () {
      final insert = _event(op: SyncOperation.insert);
      final update = _event(op: SyncOperation.update);
      final del = _event(op: SyncOperation.delete);

      expect(insert.syncOperation, SyncOperation.insert);
      expect(insert.isDeleted, isFalse);

      expect(update.syncOperation, SyncOperation.update);
      expect(update.isDeleted, isFalse);

      expect(del.syncOperation, SyncOperation.delete);
      expect(del.isDeleted, isTrue);
    });

    test('syncCreatedAt and syncCreatedAtServer are stored in UTC', () {
      final created = DateTime(2023, 1, 1, 12, 0).toUtc();
      final server = DateTime(2023, 1, 1, 13, 0).toUtc();
      final event = _event(createdAt: created, createdAtServer: server);
      expect(event.syncCreatedAt, created);
      expect(event.syncCreatedAt.isUtc, isTrue);
      expect(event.syncCreatedAtServer, server);
      expect(event.syncCreatedAtServer?.isUtc, isTrue);
    });

    test('syncServerSequence stores provided value', () {
      final values = [123, 0, -1, 0x7fffffff, -0x80000000];
      for (final v in values) {
        final event = _event(seq: v);
        expect(event.syncServerSequence, v);
      }
    });

    test('repositoryName stores provided value', () {
      final empty = _event(repo: '');
      final one = _event(repo: 'a');
      final two = _event(repo: 'ab');
      final many = _event(repo: 'myRepoNameLong');
      expect(empty.repositoryName, '');
      expect(one.repositoryName, 'a');
      expect(two.repositoryName, 'ab');
      expect(many.repositoryName, 'myRepoNameLong');
    });

    test('copyWith updates fields and keeps others', () {
      final base = _event(
        id: '1',
        value: 'v',
        eventId: 'id1',
        status: SyncStatus.pending,
        op: SyncOperation.insert,
        createdAt: DateTime.utc(2020, 1, 1),
        createdAtServer: DateTime.utc(2020, 1, 2),
        seq: 10,
        repo: 'repo',
      );

      final copy = base.copyWith(
        data: _DummyModel(id: '1', value: 'v2'),
        eventId: 'id2',
        syncStatus: SyncStatus.ok,
        syncOperation: SyncOperation.update,
        syncCreatedAt: DateTime.utc(2020, 1, 3),
        syncCreatedAtServer: DateTime.utc(2020, 1, 4),
        syncServerSequence: 20,
        repositoryName: 'other',
      );

      expect(copy.dataAs<_DummyModel>().value, 'v2');
      expect(copy.eventId, 'id2');
      expect(copy.syncStatus, SyncStatus.ok);
      expect(copy.syncOperation, SyncOperation.update);
      expect(copy.syncCreatedAt, DateTime.utc(2020, 1, 3));
      expect(copy.syncCreatedAtServer, DateTime.utc(2020, 1, 4));
      expect(copy.syncServerSequence, 20);
      expect(copy.repositoryName, 'other');

      // original unchanged
      expect(base.eventId, 'id1');
      expect(base.syncStatus, SyncStatus.pending);
      expect(base.syncOperation, SyncOperation.insert);
      expect(base.syncCreatedAt, DateTime.utc(2020, 1, 1));
      expect(base.syncCreatedAtServer, DateTime.utc(2020, 1, 2));
      expect(base.syncServerSequence, 10);
      expect(base.repositoryName, 'repo');
    });
  });
}
