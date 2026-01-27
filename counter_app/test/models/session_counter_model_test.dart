import 'package:flutter_test/flutter_test.dart';
import 'package:counter_app/models/session_counter_model.dart';
import 'package:counter_app/models/field_names.dart';

void main() {
  group('SessionCounterModel', () {
    test('creates SessionCounterModel with default values', () {
      final counter = SessionCounterModel(
        username: 'testuser',
        sessionId: 'session123',
      );

      expect(counter.username, 'testuser');
      expect(counter.sessionId, 'session123');
      expect(counter.id, 'session123');
      expect(counter.count, 0);
      expect(counter.createdAt, isNotNull);
      expect(counter.updatedAt, isNotNull);
    });

    test('creates SessionCounterModel with custom values', () {
      final created = DateTime(2024, 1, 1).toUtc();
      final updated = DateTime(2024, 1, 2).toUtc();

      final counter = SessionCounterModel(
        id: 'custom_id',
        username: 'testuser',
        sessionId: 'session123',
        count: 42,
        createdAt: created,
        updatedAt: updated,
      );

      expect(counter.id, 'custom_id');
      expect(counter.count, 42);
      expect(counter.createdAt, created);
      expect(counter.updatedAt, updated);
    });

    test('uses sessionId as id when id is null', () {
      final counter = SessionCounterModel(
        username: 'testuser',
        sessionId: 'session123',
      );

      expect(counter.id, 'session123');
    });

    test('uses createdAt for updatedAt when updatedAt is null', () {
      final created = DateTime(2024, 1, 1).toUtc();

      final counter = SessionCounterModel(
        username: 'testuser',
        sessionId: 'session123',
        createdAt: created,
      );

      expect(counter.updatedAt, created);
    });

    test('copyWith creates new instance with updated values', () {
      final original = SessionCounterModel(
        username: 'testuser',
        sessionId: 'session123',
        count: 5,
      );

      final updated = original.copyWith(
        count: 10,
        updatedAt: DateTime(2024, 1, 2).toUtc(),
      );

      expect(updated.username, 'testuser');
      expect(updated.sessionId, 'session123');
      expect(updated.count, 10);
      expect(updated.updatedAt, DateTime(2024, 1, 2).toUtc());
      expect(updated.id, original.id);
      expect(updated.createdAt, original.createdAt);
    });

    test('copyWith preserves original values when not specified', () {
      final original = SessionCounterModel(
        username: 'testuser',
        sessionId: 'session123',
        count: 5,
      );

      final updated = original.copyWith();

      expect(updated.username, original.username);
      expect(updated.sessionId, original.sessionId);
      expect(updated.count, original.count);
      expect(updated.createdAt, original.createdAt);
      expect(updated.updatedAt, original.updatedAt);
    });

    test('toJson serializes correctly', () {
      final created = DateTime(2024, 1, 1).toUtc();
      final updated = DateTime(2024, 1, 2).toUtc();

      final counter = SessionCounterModel(
        id: 'counter123',
        username: 'testuser',
        sessionId: 'session123',
        count: 42,
        createdAt: created,
        updatedAt: updated,
      );

      final json = counter.toJson();

      expect(json[CommonFields.id], 'counter123');
      expect(json[CommonFields.username], 'testuser');
      expect(json[SessionCounterFields.sessionId], 'session123');
      expect(json[SessionCounterFields.count], 42);
      expect(json[CommonFields.createdAt], created.toIso8601String());
      expect(json[CommonFields.updatedAt], updated.toIso8601String());
    });

    test('fromJson deserializes correctly', () {
      final created = DateTime(2024, 1, 1).toUtc();
      final updated = DateTime(2024, 1, 2).toUtc();

      final json = {
        CommonFields.id: 'counter123',
        CommonFields.username: 'testuser',
        SessionCounterFields.sessionId: 'session123',
        SessionCounterFields.count: 42,
        CommonFields.createdAt: created.toIso8601String(),
        CommonFields.updatedAt: updated.toIso8601String(),
      };

      final counter = SessionCounterModel.fromJson(json);

      expect(counter.id, 'counter123');
      expect(counter.username, 'testuser');
      expect(counter.sessionId, 'session123');
      expect(counter.count, 42);
      expect(counter.createdAt, created);
      expect(counter.updatedAt, updated);
    });

    test('fromJson uses sessionId as fallback for id', () {
      final json = {
        CommonFields.username: 'testuser',
        SessionCounterFields.sessionId: 'session123',
        CommonFields.createdAt: DateTime.now().toUtc().toIso8601String(),
      };

      final counter = SessionCounterModel.fromJson(json);

      expect(counter.id, 'session123');
    });

    test('fromJson uses createdAt for updatedAt when updatedAt is null', () {
      final created = DateTime(2024, 1, 1).toUtc();

      final json = {
        CommonFields.id: 'counter123',
        CommonFields.username: 'testuser',
        SessionCounterFields.sessionId: 'session123',
        CommonFields.createdAt: created.toIso8601String(),
      };

      final counter = SessionCounterModel.fromJson(json);

      expect(counter.updatedAt, created);
    });

    test('fromJson defaults count to 0 when null', () {
      final json = {
        CommonFields.id: 'counter123',
        CommonFields.username: 'testuser',
        SessionCounterFields.sessionId: 'session123',
        CommonFields.createdAt: DateTime.now().toUtc().toIso8601String(),
      };

      final counter = SessionCounterModel.fromJson(json);

      expect(counter.count, 0);
    });

    test('resolveConflict prefers newer based on updatedAt', () {
      final older = DateTime(2024, 1, 1).toUtc();
      final newer = DateTime(2024, 1, 2).toUtc();

      final local = SessionCounterModel(
        username: 'testuser',
        sessionId: 'session123',
        count: 10,
        updatedAt: newer,
      );

      final remote = SessionCounterModel(
        username: 'testuser',
        sessionId: 'session123',
        count: 5,
        updatedAt: older,
      );

      final result = SessionCounterModel.resolveConflict(local, remote);

      expect(result.count, 10);
      expect(result.updatedAt, newer);
    });

    test('resolveConflict prefers remote when it is newer', () {
      final older = DateTime(2024, 1, 1).toUtc();
      final newer = DateTime(2024, 1, 2).toUtc();

      final local = SessionCounterModel(
        username: 'testuser',
        sessionId: 'session123',
        count: 5,
        updatedAt: older,
      );

      final remote = SessionCounterModel(
        username: 'testuser',
        sessionId: 'session123',
        count: 10,
        updatedAt: newer,
      );

      final result = SessionCounterModel.resolveConflict(local, remote);

      expect(result.count, 10);
      expect(result.updatedAt, newer);
    });
  });
}
