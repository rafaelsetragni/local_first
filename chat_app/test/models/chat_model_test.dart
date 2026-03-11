import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/models/chat_model.dart';
import 'package:chat_app/models/field_names.dart';

void main() {
  group('ChatModel', () {
    test('creates ChatModel with default values', () {
      final chat = ChatModel(
        name: 'Test Chat',
        createdBy: 'testuser',
      );

      expect(chat.name, 'Test Chat');
      expect(chat.createdBy, 'testuser');
      expect(chat.id, isNotEmpty);
      expect(chat.avatarUrl, isNull);
      expect(chat.createdAt, isNotNull);
      expect(chat.updatedAt, isNotNull);
      expect(chat.lastMessageAt, isNull);
      expect(chat.lastMessageText, isNull);
      expect(chat.lastMessageSender, isNull);
      expect(chat.closedBy, isNull);
      expect(chat.isClosed, false);
    });

    test('creates ChatModel with UUID V7 id', () {
      final chat = ChatModel(
        name: 'Test Chat',
        createdBy: 'testuser',
      );

      // UUID V7 format check (36 chars with hyphens)
      expect(chat.id.length, 36);
      expect(chat.id.contains('-'), true);
    });

    test('creates ChatModel with custom id', () {
      final chat = ChatModel(
        id: 'custom-id',
        name: 'Test Chat',
        createdBy: 'testuser',
      );

      expect(chat.id, 'custom-id');
    });

    test('creates ChatModel with all fields', () {
      final created = DateTime(2024, 1, 1).toUtc();
      final updated = DateTime(2024, 1, 2).toUtc();
      final lastMsg = DateTime(2024, 1, 2, 12, 0).toUtc();

      final chat = ChatModel(
        id: 'chat1',
        name: 'Test Chat',
        createdBy: 'testuser',
        avatarUrl: 'https://example.com/avatar.png',
        createdAt: created,
        updatedAt: updated,
        lastMessageAt: lastMsg,
        lastMessageText: 'Hello!',
        lastMessageSender: 'user1',
        closedBy: null,
      );

      expect(chat.id, 'chat1');
      expect(chat.name, 'Test Chat');
      expect(chat.createdBy, 'testuser');
      expect(chat.avatarUrl, 'https://example.com/avatar.png');
      expect(chat.createdAt, created);
      expect(chat.updatedAt, updated);
      expect(chat.lastMessageAt, lastMsg);
      expect(chat.lastMessageText, 'Hello!');
      expect(chat.lastMessageSender, 'user1');
      expect(chat.isClosed, false);
    });

    test('isClosed returns true when closedBy is set', () {
      final chat = ChatModel(
        id: 'chat1',
        name: 'Test Chat',
        createdBy: 'testuser',
        closedBy: 'admin',
      );

      expect(chat.isClosed, true);
      expect(chat.closedBy, 'admin');
    });

    test('toJson serializes correctly', () {
      final created = DateTime(2024, 1, 1).toUtc();
      final updated = DateTime(2024, 1, 2).toUtc();
      final lastMsg = DateTime(2024, 1, 2, 12, 0).toUtc();

      final chat = ChatModel(
        id: 'chat1',
        name: 'Test Chat',
        createdBy: 'testuser',
        avatarUrl: 'https://example.com/avatar.png',
        createdAt: created,
        updatedAt: updated,
        lastMessageAt: lastMsg,
        lastMessageText: 'Hello!',
        lastMessageSender: 'user1',
        closedBy: 'admin',
      );

      final json = chat.toJson();

      expect(json[CommonFields.id], 'chat1');
      expect(json[ChatFields.name], 'Test Chat');
      expect(json[ChatFields.createdBy], 'testuser');
      expect(json[ChatFields.avatarUrl], 'https://example.com/avatar.png');
      expect(json[CommonFields.createdAt], created.toIso8601String());
      expect(json[CommonFields.updatedAt], updated.toIso8601String());
      expect(json[ChatFields.lastMessageAt], lastMsg.toIso8601String());
      expect(json[ChatFields.lastMessageText], 'Hello!');
      expect(json[ChatFields.lastMessageSender], 'user1');
      expect(json[ChatFields.closedBy], 'admin');
    });

    test('toJson does not include null optional fields', () {
      final chat = ChatModel(
        name: 'Test Chat',
        createdBy: 'testuser',
      );

      final json = chat.toJson();

      expect(json.containsKey(ChatFields.avatarUrl), false);
      expect(json.containsKey(ChatFields.lastMessageAt), false);
      expect(json.containsKey(ChatFields.lastMessageText), false);
      expect(json.containsKey(ChatFields.lastMessageSender), false);
      expect(json.containsKey(ChatFields.closedBy), false);
    });

    test('fromJson deserializes correctly', () {
      final created = DateTime(2024, 1, 1).toUtc();
      final updated = DateTime(2024, 1, 2).toUtc();
      final lastMsg = DateTime(2024, 1, 2, 12, 0).toUtc();

      final json = {
        CommonFields.id: 'chat1',
        ChatFields.name: 'Test Chat',
        ChatFields.createdBy: 'testuser',
        ChatFields.avatarUrl: 'https://example.com/avatar.png',
        CommonFields.createdAt: created.toIso8601String(),
        CommonFields.updatedAt: updated.toIso8601String(),
        ChatFields.lastMessageAt: lastMsg.toIso8601String(),
        ChatFields.lastMessageText: 'Hello!',
        ChatFields.lastMessageSender: 'user1',
        ChatFields.closedBy: 'admin',
      };

      final chat = ChatModel.fromJson(json);

      expect(chat.id, 'chat1');
      expect(chat.name, 'Test Chat');
      expect(chat.createdBy, 'testuser');
      expect(chat.avatarUrl, 'https://example.com/avatar.png');
      expect(chat.createdAt, created);
      expect(chat.updatedAt, updated);
      expect(chat.lastMessageAt, lastMsg);
      expect(chat.lastMessageText, 'Hello!');
      expect(chat.lastMessageSender, 'user1');
      expect(chat.closedBy, 'admin');
    });

    test('fromJson uses id as fallback for name', () {
      final json = {
        CommonFields.id: 'chat123',
        CommonFields.createdAt: DateTime.now().toUtc().toIso8601String(),
      };

      final chat = ChatModel.fromJson(json);

      expect(chat.id, 'chat123');
      expect(chat.name, 'chat123');
    });

    test('fromJson uses "unknown" as fallback for createdBy', () {
      final json = {
        CommonFields.id: 'chat123',
        CommonFields.createdAt: DateTime.now().toUtc().toIso8601String(),
      };

      final chat = ChatModel.fromJson(json);

      expect(chat.createdBy, 'unknown');
    });

    test('fromJson handles missing timestamps with current time', () {
      final before = DateTime.now().toUtc();
      final json = {
        CommonFields.id: 'chat123',
        ChatFields.name: 'Test',
        ChatFields.createdBy: 'user',
      };

      final chat = ChatModel.fromJson(json);
      final after = DateTime.now().toUtc();

      expect(chat.createdAt.isAfter(before.subtract(Duration(seconds: 1))), true);
      expect(chat.createdAt.isBefore(after.add(Duration(seconds: 1))), true);
    });

    test('copyWith creates copy with updated fields', () {
      final original = ChatModel(
        id: 'chat1',
        name: 'Original',
        createdBy: 'user1',
      );

      final copy = original.copyWith(
        name: 'Updated',
        closedBy: 'admin',
      );

      expect(copy.id, 'chat1');
      expect(copy.name, 'Updated');
      expect(copy.createdBy, 'user1');
      expect(copy.closedBy, 'admin');
    });

    test('copyWith preserves original fields when not specified', () {
      final original = ChatModel(
        id: 'chat1',
        name: 'Original',
        createdBy: 'user1',
        avatarUrl: 'https://example.com/avatar.png',
      );

      final copy = original.copyWith(name: 'Updated');

      expect(copy.avatarUrl, 'https://example.com/avatar.png');
      expect(copy.createdBy, 'user1');
    });

    group('resolveConflict', () {
      test('prefers remote when timestamps are equal', () {
        final timestamp = DateTime(2024, 1, 1).toUtc();

        final local = ChatModel(
          id: 'chat1',
          name: 'Local',
          createdBy: 'user1',
          updatedAt: timestamp,
        );

        final remote = ChatModel(
          id: 'chat1',
          name: 'Remote',
          createdBy: 'user1',
          updatedAt: timestamp,
        );

        final result = ChatModel.resolveConflict(local, remote);

        expect(result.name, 'Remote');
      });

      test('prefers newer based on updatedAt', () {
        final older = DateTime(2024, 1, 1).toUtc();
        final newer = DateTime(2024, 1, 2).toUtc();

        final local = ChatModel(
          id: 'chat1',
          name: 'Local',
          createdBy: 'user1',
          updatedAt: newer,
        );

        final remote = ChatModel(
          id: 'chat1',
          name: 'Remote',
          createdBy: 'user1',
          updatedAt: older,
        );

        final result = ChatModel.resolveConflict(local, remote);

        expect(result.name, 'Local');
      });

      test('merges lastMessageAt taking later timestamp', () {
        final older = DateTime(2024, 1, 1).toUtc();
        final newer = DateTime(2024, 1, 2).toUtc();
        final laterMsg = DateTime(2024, 1, 3).toUtc();

        final local = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: newer,
          lastMessageAt: older,
          lastMessageText: 'Local message',
        );

        final remote = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: older,
          lastMessageAt: laterMsg,
          lastMessageText: 'Remote message',
        );

        final result = ChatModel.resolveConflict(local, remote);

        expect(result.lastMessageAt, laterMsg);
        expect(result.lastMessageText, 'Remote message');
      });

      test('merges non-null avatar from fallback', () {
        final older = DateTime(2024, 1, 1).toUtc();
        final newer = DateTime(2024, 1, 2).toUtc();

        final local = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: newer,
          avatarUrl: null,
        );

        final remote = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: older,
          avatarUrl: 'https://example.com/avatar.png',
        );

        final result = ChatModel.resolveConflict(local, remote);

        expect(result.avatarUrl, 'https://example.com/avatar.png');
      });

      test('merges closedBy - once closed stays closed', () {
        final older = DateTime(2024, 1, 1).toUtc();
        final newer = DateTime(2024, 1, 2).toUtc();

        final local = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: newer,
          closedBy: null,
        );

        final remote = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: older,
          closedBy: 'admin',
        );

        final result = ChatModel.resolveConflict(local, remote);

        expect(result.closedBy, 'admin');
      });

      test('returns preferred when no merge needed', () {
        final older = DateTime(2024, 1, 1).toUtc();
        final newer = DateTime(2024, 1, 2).toUtc();

        final local = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: newer,
          avatarUrl: 'local.png',
          lastMessageAt: newer,
          lastMessageText: 'Latest',
          lastMessageSender: 'user1',
        );

        final remote = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: older,
          avatarUrl: 'remote.png',
          lastMessageAt: older,
        );

        final result = ChatModel.resolveConflict(local, remote);

        expect(identical(result, local), true);
      });

      test('handles both having null lastMessageAt', () {
        final older = DateTime(2024, 1, 1).toUtc();
        final newer = DateTime(2024, 1, 2).toUtc();

        final local = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: newer,
        );

        final remote = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: older,
        );

        final result = ChatModel.resolveConflict(local, remote);

        expect(result.lastMessageAt, isNull);
      });

      test('handles only preferred having lastMessageAt', () {
        final older = DateTime(2024, 1, 1).toUtc();
        final newer = DateTime(2024, 1, 2).toUtc();

        final local = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: newer,
          lastMessageAt: newer,
          lastMessageText: 'Latest',
        );

        final remote = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: older,
        );

        final result = ChatModel.resolveConflict(local, remote);

        expect(result.lastMessageAt, newer);
        expect(result.lastMessageText, 'Latest');
      });

      test('handles only fallback having lastMessageAt', () {
        final older = DateTime(2024, 1, 1).toUtc();
        final newer = DateTime(2024, 1, 2).toUtc();

        final local = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: newer,
        );

        final remote = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: older,
          lastMessageAt: older,
          lastMessageText: 'Old message',
        );

        final result = ChatModel.resolveConflict(local, remote);

        expect(result.lastMessageAt, older);
        expect(result.lastMessageText, 'Old message');
      });
    });

    test('toString returns descriptive string', () {
      final chat = ChatModel(
        id: 'chat1',
        name: 'Test Chat',
        createdBy: 'testuser',
      );

      final str = chat.toString();

      expect(str.contains('chat1'), true);
      expect(str.contains('Test Chat'), true);
      expect(str.contains('testuser'), true);
    });

    test('equality compares all fields', () {
      final created = DateTime(2024, 1, 1).toUtc();

      final chat1 = ChatModel(
        id: 'chat1',
        name: 'Test',
        createdBy: 'user1',
        createdAt: created,
        updatedAt: created,
      );

      final chat2 = ChatModel(
        id: 'chat1',
        name: 'Test',
        createdBy: 'user1',
        createdAt: created,
        updatedAt: created,
      );

      expect(chat1 == chat2, true);
      expect(chat1.hashCode == chat2.hashCode, true);
    });

    test('equality returns false for different chats', () {
      final chat1 = ChatModel(
        id: 'chat1',
        name: 'Test',
        createdBy: 'user1',
      );

      final chat2 = ChatModel(
        id: 'chat2',
        name: 'Test',
        createdBy: 'user1',
      );

      expect(chat1 == chat2, false);
    });
  });
}
