import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/models/message_model.dart';
import 'package:chat_app/models/field_names.dart';

void main() {
  group('MessageModel', () {
    test('creates MessageModel with default values', () {
      final message = MessageModel(
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Hello world!',
      );

      expect(message.chatId, 'chat1');
      expect(message.senderId, 'user1');
      expect(message.text, 'Hello world!');
      expect(message.id, isNotEmpty);
      expect(message.createdAt, isNotNull);
      expect(message.updatedAt, isNotNull);
      expect(message.isSystemMessage, false);
    });

    test('creates MessageModel with UUID V7 id', () {
      final message = MessageModel(
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Test',
      );

      // UUID V7 format check (36 chars with hyphens)
      expect(message.id.length, 36);
      expect(message.id.contains('-'), true);
    });

    test('creates MessageModel with custom id', () {
      final message = MessageModel(
        id: 'custom-id',
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Test',
      );

      expect(message.id, 'custom-id');
    });

    test('creates MessageModel with custom timestamps', () {
      final created = DateTime(2024, 1, 1, 12, 0).toUtc();
      final updated = DateTime(2024, 1, 1, 12, 30).toUtc();

      final message = MessageModel(
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Test',
        createdAt: created,
        updatedAt: updated,
      );

      expect(message.createdAt, created);
      expect(message.updatedAt, updated);
    });

    test('uses createdAt as default when not provided', () {
      final before = DateTime.now().toUtc();
      final message = MessageModel(
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Test',
      );
      final after = DateTime.now().toUtc();

      expect(message.createdAt.isAfter(before.subtract(Duration(seconds: 1))), true);
      expect(message.createdAt.isBefore(after.add(Duration(seconds: 1))), true);
    });

    group('system messages', () {
      test('creates system message with factory constructor', () {
        final message = MessageModel.system(
          chatId: 'chat1',
          text: 'Chat closed by admin',
        );

        expect(message.chatId, 'chat1');
        expect(message.text, 'Chat closed by admin');
        expect(message.senderId, MessageModel.systemSenderId);
        expect(message.isSystemMessage, true);
      });

      test('system message uses _system_ as sender id', () {
        final message = MessageModel.system(
          chatId: 'chat1',
          text: 'System message',
        );

        expect(message.senderId, '_system_');
      });

      test('system message with custom timestamp', () {
        final timestamp = DateTime(2024, 1, 1, 12, 0).toUtc();

        final message = MessageModel.system(
          chatId: 'chat1',
          text: 'System message',
          createdAt: timestamp,
        );

        expect(message.createdAt, timestamp);
        expect(message.updatedAt, timestamp);
      });

      test('systemSenderId constant has correct value', () {
        expect(MessageModel.systemSenderId, '_system_');
      });
    });

    test('toJson serializes correctly', () {
      final created = DateTime(2024, 1, 1, 12, 0).toUtc();
      final updated = DateTime(2024, 1, 1, 12, 30).toUtc();

      final message = MessageModel(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Hello world!',
        createdAt: created,
        updatedAt: updated,
        isSystemMessage: false,
      );

      final json = message.toJson();

      expect(json[CommonFields.id], 'msg1');
      expect(json[MessageFields.chatId], 'chat1');
      expect(json[MessageFields.senderId], 'user1');
      expect(json[MessageFields.text], 'Hello world!');
      expect(json[CommonFields.createdAt], created.toIso8601String());
      expect(json[CommonFields.updatedAt], updated.toIso8601String());
    });

    test('toJson includes isSystemMessage only when true', () {
      final regularMessage = MessageModel(
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Hello',
      );

      final systemMessage = MessageModel.system(
        chatId: 'chat1',
        text: 'System message',
      );

      expect(regularMessage.toJson().containsKey(MessageFields.isSystemMessage), false);
      expect(systemMessage.toJson()[MessageFields.isSystemMessage], true);
    });

    test('fromJson deserializes correctly', () {
      final created = DateTime(2024, 1, 1, 12, 0).toUtc();
      final updated = DateTime(2024, 1, 1, 12, 30).toUtc();

      final json = {
        CommonFields.id: 'msg1',
        MessageFields.chatId: 'chat1',
        MessageFields.senderId: 'user1',
        MessageFields.text: 'Hello world!',
        CommonFields.createdAt: created.toIso8601String(),
        CommonFields.updatedAt: updated.toIso8601String(),
        MessageFields.isSystemMessage: false,
      };

      final message = MessageModel.fromJson(json);

      expect(message.id, 'msg1');
      expect(message.chatId, 'chat1');
      expect(message.senderId, 'user1');
      expect(message.text, 'Hello world!');
      expect(message.createdAt, created);
      expect(message.updatedAt, updated);
      expect(message.isSystemMessage, false);
    });

    test('fromJson handles missing isSystemMessage as false', () {
      final json = {
        CommonFields.id: 'msg1',
        MessageFields.chatId: 'chat1',
        MessageFields.senderId: 'user1',
        MessageFields.text: 'Hello',
        CommonFields.createdAt: DateTime.now().toUtc().toIso8601String(),
        CommonFields.updatedAt: DateTime.now().toUtc().toIso8601String(),
      };

      final message = MessageModel.fromJson(json);

      expect(message.isSystemMessage, false);
    });

    test('toJson and fromJson roundtrip works correctly', () {
      final original = MessageModel(
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Hello world!',
      );

      final json = original.toJson();
      final restored = MessageModel.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.chatId, original.chatId);
      expect(restored.senderId, original.senderId);
      expect(restored.text, original.text);
      expect(restored.isSystemMessage, original.isSystemMessage);
    });

    test('toJson and fromJson roundtrip works for system messages', () {
      final original = MessageModel.system(
        chatId: 'chat1',
        text: 'Chat closed',
      );

      final json = original.toJson();
      final restored = MessageModel.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.chatId, original.chatId);
      expect(restored.senderId, original.senderId);
      expect(restored.text, original.text);
      expect(restored.isSystemMessage, true);
    });

    group('resolveConflict', () {
      test('prefers local when local is newer', () {
        final older = DateTime(2024, 1, 1, 12, 0).toUtc();
        final newer = DateTime(2024, 1, 1, 13, 0).toUtc();

        final local = MessageModel(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Local version',
          updatedAt: newer,
        );

        final remote = MessageModel(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Remote version',
          updatedAt: older,
        );

        final result = MessageModel.resolveConflict(local, remote);

        expect(result.text, 'Local version');
        expect(result.updatedAt, newer);
      });

      test('prefers remote when remote is newer', () {
        final older = DateTime(2024, 1, 1, 12, 0).toUtc();
        final newer = DateTime(2024, 1, 1, 13, 0).toUtc();

        final local = MessageModel(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Local version',
          updatedAt: older,
        );

        final remote = MessageModel(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Remote version',
          updatedAt: newer,
        );

        final result = MessageModel.resolveConflict(local, remote);

        expect(result.text, 'Remote version');
        expect(result.updatedAt, newer);
      });

      test('prefers remote when timestamps are equal', () {
        final timestamp = DateTime(2024, 1, 1, 12, 0).toUtc();

        final local = MessageModel(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Local version',
          updatedAt: timestamp,
        );

        final remote = MessageModel(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Remote version',
          updatedAt: timestamp,
        );

        final result = MessageModel.resolveConflict(local, remote);

        expect(result.text, 'Remote version');
      });
    });

    test('toString returns descriptive string', () {
      final message = MessageModel(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Hello world!',
      );

      final str = message.toString();

      expect(str.contains('msg1'), true);
      expect(str.contains('chat1'), true);
      expect(str.contains('user1'), true);
    });

    test('toString truncates long text', () {
      final message = MessageModel(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'user1',
        text: 'This is a very long message that should be truncated in the toString output',
      );

      final str = message.toString();

      expect(str.contains('...'), true);
    });

    test('toString prefixes system messages', () {
      final message = MessageModel.system(
        chatId: 'chat1',
        text: 'System message',
      );

      final str = message.toString();

      expect(str.contains('[SYSTEM]'), true);
    });

    test('equality compares all fields', () {
      final created = DateTime(2024, 1, 1, 12, 0).toUtc();

      final msg1 = MessageModel(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Hello',
        createdAt: created,
        updatedAt: created,
      );

      final msg2 = MessageModel(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Hello',
        createdAt: created,
        updatedAt: created,
      );

      expect(msg1 == msg2, true);
      expect(msg1.hashCode == msg2.hashCode, true);
    });

    test('equality returns false for different messages', () {
      final msg1 = MessageModel(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Hello',
      );

      final msg2 = MessageModel(
        id: 'msg2',
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Hello',
      );

      expect(msg1 == msg2, false);
    });

    test('equality checks isSystemMessage', () {
      final created = DateTime(2024, 1, 1, 12, 0).toUtc();

      final regular = MessageModel(
        id: 'msg1',
        chatId: 'chat1',
        senderId: '_system_',
        text: 'Hello',
        createdAt: created,
        updatedAt: created,
        isSystemMessage: false,
      );

      final system = MessageModel(
        id: 'msg1',
        chatId: 'chat1',
        senderId: '_system_',
        text: 'Hello',
        createdAt: created,
        updatedAt: created,
        isSystemMessage: true,
      );

      expect(regular == system, false);
    });
  });
}
