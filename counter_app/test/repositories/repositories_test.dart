import 'package:flutter_test/flutter_test.dart';
import 'package:counter_app/repositories/repositories.dart';
import 'package:counter_app/models/user_model.dart';
import 'package:counter_app/models/counter_log_model.dart';
import 'package:counter_app/models/session_counter_model.dart';
import 'package:counter_app/models/field_names.dart';

void main() {
  group('buildUserRepository', () {
    test('creates repository with correct name', () {
      final repo = buildUserRepository();
      expect(repo.name, RepositoryNames.user);
    });

    test('creates repository with correct id field', () {
      final repo = buildUserRepository();
      expect(repo.idFieldName, 'id');
    });

    test('getId returns correct user id', () {
      final repo = buildUserRepository();
      final user = UserModel(username: 'testuser', avatarUrl: null);

      final id = repo.getId(user);

      expect(id, user.id);
      expect(id, 'testuser');
    });

    test('toJson converts user to JSON correctly', () {
      final repo = buildUserRepository();
      final user = UserModel(username: 'testuser', avatarUrl: 'https://example.com');

      final json = repo.toJson(user);

      expect(json['id'], user.id);
      expect(json['username'], 'testuser');
      expect(json['avatar_url'], 'https://example.com');
      expect(json['created_at'], isNotNull);
      expect(json['updated_at'], isNotNull);
    });

    test('fromJson converts JSON to user correctly', () {
      final repo = buildUserRepository();
      final json = {
        'id': 'testuser',
        'username': 'testuser',
        'avatar_url': 'https://example.com',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final user = repo.fromJson(json);

      expect(user.id, 'testuser');
      expect(user.username, 'testuser');
      expect(user.avatarUrl, 'https://example.com');
    });

    test('toJson and fromJson roundtrip works correctly', () {
      final repo = buildUserRepository();
      final original = UserModel(
        username: 'roundtripuser',
        avatarUrl: 'https://avatar.com',
      );

      final json = repo.toJson(original);
      final restored = repo.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.username, original.username);
      expect(restored.avatarUrl, original.avatarUrl);
    });

    test('handles user with null avatar', () {
      final repo = buildUserRepository();
      final user = UserModel(username: 'noavatar', avatarUrl: null);

      final json = repo.toJson(user);
      final restored = repo.fromJson(json);

      expect(restored.avatarUrl, isNull);
    });
  });

  group('buildCounterLogRepository', () {
    test('creates repository with correct name', () {
      final repo = buildCounterLogRepository();
      expect(repo.name, RepositoryNames.counterLog);
    });

    test('creates repository with correct id field', () {
      final repo = buildCounterLogRepository();
      expect(repo.idFieldName, 'id');
    });

    test('getId returns correct log id', () {
      final repo = buildCounterLogRepository();
      final log = CounterLogModel(
        username: 'testuser',
        increment: 1,
        sessionId: 'session1',
      );

      final id = repo.getId(log);

      expect(id, log.id);
      expect(id, isNotEmpty);
    });

    test('toJson converts log to JSON correctly', () {
      final repo = buildCounterLogRepository();
      final log = CounterLogModel(
        username: 'testuser',
        increment: 5,
        sessionId: 'session1',
      );

      final json = repo.toJson(log);

      expect(json['id'], log.id);
      expect(json['username'], 'testuser');
      expect(json['increment'], 5);
      expect(json['session_id'], 'session1');
      expect(json['created_at'], isNotNull);
      expect(json['updated_at'], isNotNull);
    });

    test('fromJson converts JSON to log correctly', () {
      final repo = buildCounterLogRepository();
      final json = {
        'id': 'log1',
        'username': 'testuser',
        'increment': 3,
        'session_id': 'session1',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final log = repo.fromJson(json);

      expect(log.id, 'log1');
      expect(log.username, 'testuser');
      expect(log.increment, 3);
      expect(log.sessionId, 'session1');
    });

    test('toJson and fromJson roundtrip works correctly', () {
      final repo = buildCounterLogRepository();
      final original = CounterLogModel(
        id: 'logtest',
        username: 'user1',
        increment: -2,
        sessionId: 'sess1',
      );

      final json = repo.toJson(original);
      final restored = repo.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.username, original.username);
      expect(restored.increment, original.increment);
      expect(restored.sessionId, original.sessionId);
    });

    test('handles negative increment', () {
      final repo = buildCounterLogRepository();
      final log = CounterLogModel(
        username: 'testuser',
        increment: -5,
        sessionId: 'session1',
      );

      final json = repo.toJson(log);
      final restored = repo.fromJson(json);

      expect(restored.increment, -5);
    });
  });

  group('buildSessionCounterRepository', () {
    test('creates repository with correct name', () {
      final repo = buildSessionCounterRepository();
      expect(repo.name, RepositoryNames.sessionCounter);
    });

    test('creates repository with correct id field', () {
      final repo = buildSessionCounterRepository();
      expect(repo.idFieldName, 'id');
    });

    test('getId returns correct session id', () {
      final repo = buildSessionCounterRepository();
      final session = SessionCounterModel(
        sessionId: 'session1',
        username: 'testuser',
        count: 10,
      );

      final id = repo.getId(session);

      expect(id, 'session1');
    });

    test('toJson converts session to JSON correctly', () {
      final repo = buildSessionCounterRepository();
      final session = SessionCounterModel(
        sessionId: 'session1',
        username: 'testuser',
        count: 15,
      );

      final json = repo.toJson(session);

      expect(json['session_id'], 'session1');
      expect(json['id'], 'session1');
      expect(json['username'], 'testuser');
      expect(json['count'], 15);
      expect(json['created_at'], isNotNull);
      expect(json['updated_at'], isNotNull);
    });

    test('fromJson converts JSON to session correctly', () {
      final repo = buildSessionCounterRepository();
      final json = {
        'id': 'session1',
        'session_id': 'session1',
        'username': 'testuser',
        'count': 20,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final session = repo.fromJson(json);

      expect(session.sessionId, 'session1');
      expect(session.username, 'testuser');
      expect(session.count, 20);
    });

    test('toJson and fromJson roundtrip works correctly', () {
      final repo = buildSessionCounterRepository();
      final original = SessionCounterModel(
        sessionId: 'sess_test_123',
        username: 'testuser',
        count: 42,
      );

      final json = repo.toJson(original);
      final restored = repo.fromJson(json);

      expect(restored.sessionId, original.sessionId);
      expect(restored.username, original.username);
      expect(restored.count, original.count);
    });

    test('handles zero count', () {
      final repo = buildSessionCounterRepository();
      final session = SessionCounterModel(
        sessionId: 'session1',
        username: 'testuser',
        count: 0,
      );

      final json = repo.toJson(session);
      final restored = repo.fromJson(json);

      expect(restored.count, 0);
    });
  });

  group('UserModel Conflict Resolution', () {
    test('prefers local when local is newer', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);

      final localUser = UserModel(
        username: 'testuser',
        avatarUrl: 'https://local.com',
        updatedAt: newTime,
      );

      final remoteUser = UserModel(
        username: 'testuser',
        avatarUrl: 'https://remote.com',
        updatedAt: oldTime,
      );

      final result = UserModel.resolveConflict(localUser, remoteUser);

      expect(result.username, 'testuser');
      expect(result.avatarUrl, 'https://local.com');
      expect(result.updatedAt, newTime);
    });

    test('prefers remote when remote is newer', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);

      final localUser = UserModel(
        username: 'testuser',
        avatarUrl: 'https://local.com',
        updatedAt: oldTime,
      );

      final remoteUser = UserModel(
        username: 'testuser',
        avatarUrl: 'https://remote.com',
        updatedAt: newTime,
      );

      final result = UserModel.resolveConflict(localUser, remoteUser);

      expect(result.username, 'testuser');
      expect(result.avatarUrl, 'https://remote.com');
      expect(result.updatedAt, newTime);
    });

    test('prefers remote when timestamps are equal', () {
      final sameTime = DateTime.utc(2025, 1, 1, 12, 0);

      final localUser = UserModel(
        username: 'testuser',
        avatarUrl: 'https://local.com',
        updatedAt: sameTime,
      );

      final remoteUser = UserModel(
        username: 'testuser',
        avatarUrl: 'https://remote.com',
        updatedAt: sameTime,
      );

      final result = UserModel.resolveConflict(localUser, remoteUser);

      expect(result.avatarUrl, 'https://remote.com');
      expect(result.updatedAt, sameTime);
    });

    test('merges non-null avatar from older version', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);

      final localUser = UserModel(
        username: 'testuser',
        avatarUrl: null,
        updatedAt: newTime,
      );

      final remoteUser = UserModel(
        username: 'testuser',
        avatarUrl: 'https://remote.com',
        updatedAt: oldTime,
      );

      final result = UserModel.resolveConflict(localUser, remoteUser);

      expect(result.username, 'testuser');
      expect(result.avatarUrl, 'https://remote.com');
      expect(result.updatedAt, newTime);
    });

    test('returns preferred object when no merge needed', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);

      final localUser = UserModel(
        username: 'testuser',
        avatarUrl: 'https://local.com',
        updatedAt: newTime,
      );

      final remoteUser = UserModel(
        username: 'testuser',
        avatarUrl: 'https://remote.com',
        updatedAt: oldTime,
      );

      final result = UserModel.resolveConflict(localUser, remoteUser);

      // Should return the exact same instance when no merging is needed
      expect(identical(result, localUser), isTrue);
    });
  });

  group('CounterLogModel Conflict Resolution', () {
    test('prefers local when local is newer', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);

      final localLog = CounterLogModel(
        id: 'log1',
        username: 'testuser',
        sessionId: 'session1',
        increment: 5,
        updatedAt: newTime,
      );

      final remoteLog = CounterLogModel(
        id: 'log1',
        username: 'testuser',
        sessionId: 'session1',
        increment: 3,
        updatedAt: oldTime,
      );

      final result = CounterLogModel.resolveConflict(localLog, remoteLog);

      expect(result.id, 'log1');
      expect(result.increment, 5);
      expect(result.updatedAt, newTime);
    });

    test('prefers remote when remote is newer', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);

      final localLog = CounterLogModel(
        id: 'log1',
        username: 'testuser',
        sessionId: 'session1',
        increment: 5,
        updatedAt: oldTime,
      );

      final remoteLog = CounterLogModel(
        id: 'log1',
        username: 'testuser',
        sessionId: 'session1',
        increment: 3,
        updatedAt: newTime,
      );

      final result = CounterLogModel.resolveConflict(localLog, remoteLog);

      expect(result.id, 'log1');
      expect(result.increment, 3);
      expect(result.updatedAt, newTime);
    });

    test('handles negative increments in conflict', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);

      final localLog = CounterLogModel(
        id: 'log1',
        username: 'testuser',
        sessionId: 'session1',
        increment: -5,
        updatedAt: newTime,
      );

      final remoteLog = CounterLogModel(
        id: 'log1',
        username: 'testuser',
        sessionId: 'session1',
        increment: 3,
        updatedAt: oldTime,
      );

      final result = CounterLogModel.resolveConflict(localLog, remoteLog);

      expect(result.increment, -5);
      expect(result.updatedAt, newTime);
    });

    test('returns exact instance when local is newer', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);

      final localLog = CounterLogModel(
        id: 'log1',
        username: 'testuser',
        sessionId: 'session1',
        increment: 5,
        updatedAt: newTime,
      );

      final remoteLog = CounterLogModel(
        id: 'log1',
        username: 'testuser',
        sessionId: 'session1',
        increment: 3,
        updatedAt: oldTime,
      );

      final result = CounterLogModel.resolveConflict(localLog, remoteLog);

      expect(identical(result, localLog), isTrue);
    });
  });

  group('SessionCounterModel Conflict Resolution', () {
    test('prefers local when local is newer', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);

      final localSession = SessionCounterModel(
        sessionId: 'session1',
        username: 'testuser',
        count: 10,
        updatedAt: newTime,
      );

      final remoteSession = SessionCounterModel(
        sessionId: 'session1',
        username: 'testuser',
        count: 5,
        updatedAt: oldTime,
      );

      final result = SessionCounterModel.resolveConflict(localSession, remoteSession);

      expect(result.sessionId, 'session1');
      expect(result.count, 10);
      expect(result.updatedAt, newTime);
    });

    test('prefers remote when remote is newer', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);

      final localSession = SessionCounterModel(
        sessionId: 'session1',
        username: 'testuser',
        count: 10,
        updatedAt: oldTime,
      );

      final remoteSession = SessionCounterModel(
        sessionId: 'session1',
        username: 'testuser',
        count: 5,
        updatedAt: newTime,
      );

      final result = SessionCounterModel.resolveConflict(localSession, remoteSession);

      expect(result.sessionId, 'session1');
      expect(result.count, 5);
      expect(result.updatedAt, newTime);
    });

    test('handles zero count in conflict', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);

      final localSession = SessionCounterModel(
        sessionId: 'session1',
        username: 'testuser',
        count: 0,
        updatedAt: newTime,
      );

      final remoteSession = SessionCounterModel(
        sessionId: 'session1',
        username: 'testuser',
        count: 5,
        updatedAt: oldTime,
      );

      final result = SessionCounterModel.resolveConflict(localSession, remoteSession);

      expect(result.count, 0);
      expect(result.updatedAt, newTime);
    });

    test('returns exact instance when local is newer', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);

      final localSession = SessionCounterModel(
        sessionId: 'session1',
        username: 'testuser',
        count: 10,
        updatedAt: newTime,
      );

      final remoteSession = SessionCounterModel(
        sessionId: 'session1',
        username: 'testuser',
        count: 5,
        updatedAt: oldTime,
      );

      final result = SessionCounterModel.resolveConflict(localSession, remoteSession);

      expect(identical(result, localSession), isTrue);
    });
  });
}

