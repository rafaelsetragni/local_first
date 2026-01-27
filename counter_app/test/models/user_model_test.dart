import 'package:flutter_test/flutter_test.dart';
import 'package:counter_app/models/user_model.dart';
import 'package:counter_app/models/field_names.dart';

void main() {
  group('UserModel', () {
    test('creates UserModel with default values', () {
      final user = UserModel(
        username: 'testuser',
        avatarUrl: null,
      );

      expect(user.username, 'testuser');
      expect(user.avatarUrl, null);
      expect(user.id, 'testuser');
      expect(user.createdAt, isNotNull);
      expect(user.updatedAt, isNotNull);
    });

    test('creates UserModel with custom id', () {
      final user = UserModel(
        id: 'custom_id',
        username: 'testuser',
        avatarUrl: 'https://example.com/avatar.png',
      );

      expect(user.id, 'custom_id');
      expect(user.username, 'testuser');
      expect(user.avatarUrl, 'https://example.com/avatar.png');
    });

    test('normalizes id to lowercase and trimmed', () {
      final user = UserModel(
        id: '  TestUser  ',
        username: 'testuser',
        avatarUrl: null,
      );

      expect(user.id, 'testuser');
    });

    test('uses username as id when id is null', () {
      final user = UserModel(
        username: '  TestUser  ',
        avatarUrl: null,
      );

      expect(user.id, 'testuser');
    });

    test('creates UserModel with custom timestamps', () {
      final created = DateTime(2024, 1, 1).toUtc();
      final updated = DateTime(2024, 1, 2).toUtc();

      final user = UserModel(
        username: 'testuser',
        avatarUrl: null,
        createdAt: created,
        updatedAt: updated,
      );

      expect(user.createdAt, created);
      expect(user.updatedAt, updated);
    });

    test('uses createdAt for updatedAt when updatedAt is null', () {
      final created = DateTime(2024, 1, 1).toUtc();

      final user = UserModel(
        username: 'testuser',
        avatarUrl: null,
        createdAt: created,
      );

      expect(user.updatedAt, created);
    });

    test('toJson serializes correctly', () {
      final created = DateTime(2024, 1, 1).toUtc();
      final updated = DateTime(2024, 1, 2).toUtc();

      final user = UserModel(
        id: 'testuser',
        username: 'Test User',
        avatarUrl: 'https://example.com/avatar.png',
        createdAt: created,
        updatedAt: updated,
      );

      final json = user.toJson();

      expect(json[CommonFields.id], 'testuser');
      expect(json[CommonFields.username], 'Test User');
      expect(json[UserFields.avatarUrl], 'https://example.com/avatar.png');
      expect(json[CommonFields.createdAt], created.toIso8601String());
      expect(json[CommonFields.updatedAt], updated.toIso8601String());
    });

    test('fromJson deserializes correctly', () {
      final created = DateTime(2024, 1, 1).toUtc();
      final updated = DateTime(2024, 1, 2).toUtc();

      final json = {
        CommonFields.id: 'testuser',
        CommonFields.username: 'Test User',
        UserFields.avatarUrl: 'https://example.com/avatar.png',
        CommonFields.createdAt: created.toIso8601String(),
        CommonFields.updatedAt: updated.toIso8601String(),
      };

      final user = UserModel.fromJson(json);

      expect(user.id, 'testuser');
      expect(user.username, 'Test User');
      expect(user.avatarUrl, 'https://example.com/avatar.png');
      expect(user.createdAt, created);
      expect(user.updatedAt, updated);
    });

    test('fromJson uses username as fallback for id', () {
      final json = {
        CommonFields.username: 'Test User',
        CommonFields.createdAt: DateTime.now().toUtc().toIso8601String(),
      };

      final user = UserModel.fromJson(json);

      expect(user.username, 'Test User');
      expect(user.id, 'test user');
    });

    test('fromJson uses createdAt for updatedAt when updatedAt is null', () {
      final created = DateTime(2024, 1, 1).toUtc();

      final json = {
        CommonFields.id: 'testuser',
        CommonFields.username: 'Test User',
        CommonFields.createdAt: created.toIso8601String(),
      };

      final user = UserModel.fromJson(json);

      expect(user.updatedAt, created);
    });

    test('resolveConflict prefers remote when timestamps are equal', () {
      final timestamp = DateTime(2024, 1, 1).toUtc();

      final local = UserModel(
        username: 'local',
        avatarUrl: 'local.png',
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      final remote = UserModel(
        username: 'remote',
        avatarUrl: 'remote.png',
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      final result = UserModel.resolveConflict(local, remote);

      expect(result.username, 'remote');
      expect(result.avatarUrl, 'remote.png');
    });

    test('resolveConflict prefers newer based on updatedAt', () {
      final older = DateTime(2024, 1, 1).toUtc();
      final newer = DateTime(2024, 1, 2).toUtc();

      final local = UserModel(
        username: 'local',
        avatarUrl: 'local.png',
        updatedAt: newer,
      );

      final remote = UserModel(
        username: 'remote',
        avatarUrl: 'remote.png',
        updatedAt: older,
      );

      final result = UserModel.resolveConflict(local, remote);

      expect(result.username, 'local');
      expect(result.avatarUrl, 'local.png');
    });

    test('resolveConflict merges avatar from fallback if preferred is null', () {
      final older = DateTime(2024, 1, 1).toUtc();
      final newer = DateTime(2024, 1, 2).toUtc();

      final local = UserModel(
        username: 'local',
        avatarUrl: null,
        updatedAt: newer,
      );

      final remote = UserModel(
        username: 'remote',
        avatarUrl: 'remote.png',
        updatedAt: older,
      );

      final result = UserModel.resolveConflict(local, remote);

      expect(result.username, 'local');
      expect(result.avatarUrl, 'remote.png');
    });

    test('resolveConflict returns preferred as-is if no merge needed', () {
      final older = DateTime(2024, 1, 1).toUtc();
      final newer = DateTime(2024, 1, 2).toUtc();

      final local = UserModel(
        username: 'local',
        avatarUrl: 'local.png',
        updatedAt: newer,
      );

      final remote = UserModel(
        username: 'remote',
        avatarUrl: 'remote.png',
        updatedAt: older,
      );

      final result = UserModel.resolveConflict(local, remote);

      expect(identical(result, local), true);
    });
  });
}
