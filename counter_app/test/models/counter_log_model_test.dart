import 'package:flutter_test/flutter_test.dart';
import 'package:counter_app/models/counter_log_model.dart';
import 'package:counter_app/models/field_names.dart';

void main() {
  group('CounterLogModel', () {
    test('creates CounterLogModel with auto-generated id', () {
      final log = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: 5,
      );

      expect(log.username, 'testuser');
      expect(log.sessionId, 'session123');
      expect(log.increment, 5);
      expect(log.id, startsWith('testuser_'));
      expect(log.createdAt, isNotNull);
      expect(log.updatedAt, isNotNull);
    });

    test('creates CounterLogModel with custom id', () {
      final log = CounterLogModel(
        id: 'custom_id',
        username: 'testuser',
        sessionId: 'session123',
        increment: -3,
      );

      expect(log.id, 'custom_id');
      expect(log.increment, -3);
    });

    test('creates CounterLogModel with custom timestamps', () {
      final created = DateTime(2024, 1, 1).toUtc();
      final updated = DateTime(2024, 1, 2).toUtc();

      final log = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: 1,
        createdAt: created,
        updatedAt: updated,
      );

      expect(log.createdAt, created);
      expect(log.updatedAt, updated);
    });

    test('uses createdAt for updatedAt when updatedAt is null', () {
      final created = DateTime(2024, 1, 1).toUtc();

      final log = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: 1,
        createdAt: created,
      );

      expect(log.updatedAt, created);
    });

    test('allows null sessionId', () {
      final log = CounterLogModel(
        username: 'testuser',
        sessionId: null,
        increment: 1,
      );

      expect(log.sessionId, null);
    });

    test('toJson serializes correctly', () {
      final created = DateTime(2024, 1, 1).toUtc();
      final updated = DateTime(2024, 1, 2).toUtc();

      final log = CounterLogModel(
        id: 'log123',
        username: 'testuser',
        sessionId: 'session123',
        increment: 5,
        createdAt: created,
        updatedAt: updated,
      );

      final json = log.toJson();

      expect(json[CommonFields.id], 'log123');
      expect(json[CommonFields.username], 'testuser');
      expect(json[CounterLogFields.sessionId], 'session123');
      expect(json[CounterLogFields.increment], 5);
      expect(json[CommonFields.createdAt], created.toIso8601String());
      expect(json[CommonFields.updatedAt], updated.toIso8601String());
    });

    test('fromJson deserializes correctly', () {
      final created = DateTime(2024, 1, 1).toUtc();
      final updated = DateTime(2024, 1, 2).toUtc();

      final json = {
        CommonFields.id: 'log123',
        CommonFields.username: 'testuser',
        CounterLogFields.sessionId: 'session123',
        CounterLogFields.increment: 5,
        CommonFields.createdAt: created.toIso8601String(),
        CommonFields.updatedAt: updated.toIso8601String(),
      };

      final log = CounterLogModel.fromJson(json);

      expect(log.id, 'log123');
      expect(log.username, 'testuser');
      expect(log.sessionId, 'session123');
      expect(log.increment, 5);
      expect(log.createdAt, created);
      expect(log.updatedAt, updated);
    });

    test('fromJson uses createdAt for updatedAt when updatedAt is null', () {
      final created = DateTime(2024, 1, 1).toUtc();

      final json = {
        CommonFields.id: 'log123',
        CommonFields.username: 'testuser',
        CounterLogFields.sessionId: 'session123',
        CounterLogFields.increment: 5,
        CommonFields.createdAt: created.toIso8601String(),
      };

      final log = CounterLogModel.fromJson(json);

      expect(log.updatedAt, created);
    });

    test('resolveConflict prefers newer based on updatedAt', () {
      final older = DateTime(2024, 1, 1).toUtc();
      final newer = DateTime(2024, 1, 2).toUtc();

      final local = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: 5,
        updatedAt: newer,
      );

      final remote = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: 3,
        updatedAt: older,
      );

      final result = CounterLogModel.resolveConflict(local, remote);

      expect(result.increment, 5);
      expect(result.updatedAt, newer);
    });

    test('toString formats positive increment correctly', () {
      final log = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: 5,
      );

      expect(log.toString(), 'Increased by 5 by testuser');
    });

    test('toString formats negative increment correctly', () {
      final log = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: -3,
      );

      expect(log.toString(), 'Decreased by 3 by testuser');
    });

    test('toString formats zero increment correctly', () {
      final log = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: 0,
      );

      expect(log.toString(), 'Increased by 0 by testuser');
    });

    test('toFormattedDate formats date correctly', () {
      final created = DateTime(2024, 3, 15, 14, 30, 45, 123).toUtc();

      final log = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: 1,
        createdAt: created,
      );

      final formatted = log.toFormattedDate();

      // Check format pattern (exact values depend on local timezone)
      expect(formatted, matches(r'\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2}\.\d{3}'));
    });

    test('toFormattedDate pads values correctly', () {
      // Create date with single-digit values to test padding
      final created = DateTime(2024, 1, 5, 9, 8, 7, 6).toUtc();

      final log = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: 1,
        createdAt: created,
      );

      final formatted = log.toFormattedDate();

      // Verify padding is applied
      expect(formatted, contains('01/'));  // Month padded
      expect(formatted, contains('/2024')); // Year not padded
    });
  });
}
