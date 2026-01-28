import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/repositories/repositories.dart';
import 'package:chat_app/models/user_model.dart';
import 'package:chat_app/models/chat_model.dart';
import 'package:chat_app/models/message_model.dart';
import 'package:chat_app/models/field_names.dart';
import 'package:local_first/local_first.dart';

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

  group('buildChatRepository', () {
    test('creates repository with correct name', () {
      final repo = buildChatRepository();
      expect(repo.name, RepositoryNames.chat);
    });

    test('creates repository with correct id field', () {
      final repo = buildChatRepository();
      expect(repo.idFieldName, 'id');
    });

    test('getId returns correct chat id', () {
      final repo = buildChatRepository();
      final chat = ChatModel(
        name: 'Test Chat',
        createdBy: 'testuser',
      );

      final id = repo.getId(chat);

      expect(id, chat.id);
      expect(id, isNotEmpty);
    });

    test('toJson converts chat to JSON correctly', () {
      final repo = buildChatRepository();
      final chat = ChatModel(
        id: 'chat1',
        name: 'Test Chat',
        createdBy: 'testuser',
        avatarUrl: 'https://example.com',
      );

      final json = repo.toJson(chat);

      expect(json['id'], 'chat1');
      expect(json['name'], 'Test Chat');
      expect(json['created_by'], 'testuser');
      expect(json['avatar_url'], 'https://example.com');
      expect(json['created_at'], isNotNull);
      expect(json['updated_at'], isNotNull);
    });

    test('fromJson converts JSON to chat correctly', () {
      final repo = buildChatRepository();
      final json = {
        'id': 'chat1',
        'name': 'Test Chat',
        'created_by': 'testuser',
        'avatar_url': 'https://example.com',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final chat = repo.fromJson(json);

      expect(chat.id, 'chat1');
      expect(chat.name, 'Test Chat');
      expect(chat.createdBy, 'testuser');
      expect(chat.avatarUrl, 'https://example.com');
    });

    test('toJson and fromJson roundtrip works correctly', () {
      final repo = buildChatRepository();
      final original = ChatModel(
        name: 'Roundtrip Chat',
        createdBy: 'user1',
        avatarUrl: 'https://chat-avatar.com',
      );

      final json = repo.toJson(original);
      final restored = repo.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.createdBy, original.createdBy);
      expect(restored.avatarUrl, original.avatarUrl);
    });

    test('handles chat with all optional fields', () {
      final repo = buildChatRepository();
      final lastMsg = DateTime.now().toUtc();
      final chat = ChatModel(
        name: 'Full Chat',
        createdBy: 'user1',
        lastMessageAt: lastMsg,
        lastMessageText: 'Hello!',
        lastMessageSender: 'user2',
        closedBy: 'admin',
      );

      final json = repo.toJson(chat);
      final restored = repo.fromJson(json);

      expect(restored.lastMessageText, 'Hello!');
      expect(restored.lastMessageSender, 'user2');
      expect(restored.closedBy, 'admin');
    });

    test('handles chat without optional fields', () {
      final repo = buildChatRepository();
      final chat = ChatModel(
        name: 'Simple Chat',
        createdBy: 'user1',
      );

      final json = repo.toJson(chat);
      final restored = repo.fromJson(json);

      expect(restored.avatarUrl, isNull);
      expect(restored.lastMessageAt, isNull);
      expect(restored.lastMessageText, isNull);
      expect(restored.closedBy, isNull);
    });
  });

  group('buildMessageRepository', () {
    test('creates repository with correct name', () {
      final repo = buildMessageRepository();
      expect(repo.name, RepositoryNames.message);
    });

    test('creates repository with correct id field', () {
      final repo = buildMessageRepository();
      expect(repo.idFieldName, 'id');
    });

    test('getId returns correct message id', () {
      final repo = buildMessageRepository();
      final message = MessageModel(
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Hello!',
      );

      final id = repo.getId(message);

      expect(id, message.id);
      expect(id, isNotEmpty);
    });

    test('toJson converts message to JSON correctly', () {
      final repo = buildMessageRepository();
      final message = MessageModel(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Hello world!',
      );

      final json = repo.toJson(message);

      expect(json['id'], 'msg1');
      expect(json['chat_id'], 'chat1');
      expect(json['sender_id'], 'user1');
      expect(json['text'], 'Hello world!');
      expect(json['created_at'], isNotNull);
      expect(json['updated_at'], isNotNull);
    });

    test('fromJson converts JSON to message correctly', () {
      final repo = buildMessageRepository();
      final json = {
        'id': 'msg1',
        'chat_id': 'chat1',
        'sender_id': 'user1',
        'text': 'Hello world!',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final message = repo.fromJson(json);

      expect(message.id, 'msg1');
      expect(message.chatId, 'chat1');
      expect(message.senderId, 'user1');
      expect(message.text, 'Hello world!');
    });

    test('toJson and fromJson roundtrip works correctly', () {
      final repo = buildMessageRepository();
      final original = MessageModel(
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Test message',
      );

      final json = repo.toJson(original);
      final restored = repo.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.chatId, original.chatId);
      expect(restored.senderId, original.senderId);
      expect(restored.text, original.text);
    });

    test('handles system messages', () {
      final repo = buildMessageRepository();
      final message = MessageModel.system(
        chatId: 'chat1',
        text: 'Chat closed by admin',
      );

      final json = repo.toJson(message);
      final restored = repo.fromJson(json);

      expect(restored.isSystemMessage, true);
      expect(restored.senderId, MessageModel.systemSenderId);
    });

    test('handles regular messages without isSystemMessage', () {
      final repo = buildMessageRepository();
      final message = MessageModel(
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Regular message',
      );

      final json = repo.toJson(message);
      final restored = repo.fromJson(json);

      expect(restored.isSystemMessage, false);
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

  group('ChatModel Conflict Resolution', () {
    test('prefers local when local is newer', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);

      final localChat = ChatModel(
        id: 'chat1',
        name: 'Local Chat',
        createdBy: 'user1',
        updatedAt: newTime,
      );

      final remoteChat = ChatModel(
        id: 'chat1',
        name: 'Remote Chat',
        createdBy: 'user1',
        updatedAt: oldTime,
      );

      final result = ChatModel.resolveConflict(localChat, remoteChat);

      expect(result.name, 'Local Chat');
      expect(result.updatedAt, newTime);
    });

    test('prefers remote when remote is newer', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);

      final localChat = ChatModel(
        id: 'chat1',
        name: 'Local Chat',
        createdBy: 'user1',
        updatedAt: oldTime,
      );

      final remoteChat = ChatModel(
        id: 'chat1',
        name: 'Remote Chat',
        createdBy: 'user1',
        updatedAt: newTime,
      );

      final result = ChatModel.resolveConflict(localChat, remoteChat);

      expect(result.name, 'Remote Chat');
      expect(result.updatedAt, newTime);
    });

    test('merges lastMessageAt taking later timestamp', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);
      final laterMsgTime = DateTime.utc(2025, 1, 1, 14, 0);

      final localChat = ChatModel(
        id: 'chat1',
        name: 'Chat',
        createdBy: 'user1',
        updatedAt: newTime,
        lastMessageAt: oldTime,
        lastMessageText: 'Old message',
      );

      final remoteChat = ChatModel(
        id: 'chat1',
        name: 'Chat',
        createdBy: 'user1',
        updatedAt: oldTime,
        lastMessageAt: laterMsgTime,
        lastMessageText: 'New message',
      );

      final result = ChatModel.resolveConflict(localChat, remoteChat);

      expect(result.lastMessageAt, laterMsgTime);
      expect(result.lastMessageText, 'New message');
    });

    test('preserves closedBy once set', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);

      final localChat = ChatModel(
        id: 'chat1',
        name: 'Chat',
        createdBy: 'user1',
        updatedAt: newTime,
        closedBy: null,
      );

      final remoteChat = ChatModel(
        id: 'chat1',
        name: 'Chat',
        createdBy: 'user1',
        updatedAt: oldTime,
        closedBy: 'admin',
      );

      final result = ChatModel.resolveConflict(localChat, remoteChat);

      expect(result.closedBy, 'admin');
    });
  });

  group('MessageModel Conflict Resolution', () {
    test('prefers local when local is newer', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);

      final localMsg = MessageModel(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Local text',
        updatedAt: newTime,
      );

      final remoteMsg = MessageModel(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Remote text',
        updatedAt: oldTime,
      );

      final result = MessageModel.resolveConflict(localMsg, remoteMsg);

      expect(result.text, 'Local text');
      expect(result.updatedAt, newTime);
    });

    test('prefers remote when remote is newer', () {
      final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
      final newTime = DateTime.utc(2025, 1, 1, 13, 0);

      final localMsg = MessageModel(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Local text',
        updatedAt: oldTime,
      );

      final remoteMsg = MessageModel(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Remote text',
        updatedAt: newTime,
      );

      final result = MessageModel.resolveConflict(localMsg, remoteMsg);

      expect(result.text, 'Remote text');
      expect(result.updatedAt, newTime);
    });

    test('prefers remote on timestamp tie', () {
      final sameTime = DateTime.utc(2025, 1, 1, 12, 0);

      final localMsg = MessageModel(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Local text',
        updatedAt: sameTime,
      );

      final remoteMsg = MessageModel(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'user1',
        text: 'Remote text',
        updatedAt: sameTime,
      );

      final result = MessageModel.resolveConflict(localMsg, remoteMsg);

      expect(result.text, 'Remote text');
    });
  });

  group('onConflictEvent callbacks', () {
    group('User repository onConflictEvent', () {
      test('returns local event with SyncStatus.ok when local wins', () {
        final repo = buildUserRepository();
        final newTime = DateTime.utc(2025, 1, 1, 13, 0);
        final oldTime = DateTime.utc(2025, 1, 1, 12, 0);

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

        final localEvent =
            LocalFirstEvent.createNewInsertEvent<UserModel>(
          repository: repo,
          needSync: true,
          data: localUser,
        );

        final remoteEvent =
            LocalFirstEvent.createNewInsertEvent<UserModel>(
          repository: repo,
          needSync: false,
          data: remoteUser,
        );

        final result = repo.resolveConflictEvent(localEvent, remoteEvent);

        expect(result.data.avatarUrl, 'https://local.com');
        expect(result.syncStatus, SyncStatus.ok);
      });

      test('returns remote event with SyncStatus.ok when remote wins', () {
        final repo = buildUserRepository();
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

        final localEvent =
            LocalFirstEvent.createNewInsertEvent<UserModel>(
          repository: repo,
          needSync: true,
          data: localUser,
        );

        final remoteEvent =
            LocalFirstEvent.createNewInsertEvent<UserModel>(
          repository: repo,
          needSync: false,
          data: remoteUser,
        );

        final result = repo.resolveConflictEvent(localEvent, remoteEvent);

        expect(result.data.avatarUrl, 'https://remote.com');
        expect(result.syncStatus, SyncStatus.ok);
      });

      test('returns merged event when avatar needs merging', () {
        final repo = buildUserRepository();
        final newTime = DateTime.utc(2025, 1, 1, 13, 0);
        final oldTime = DateTime.utc(2025, 1, 1, 12, 0);

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

        final localEvent =
            LocalFirstEvent.createNewInsertEvent<UserModel>(
          repository: repo,
          needSync: true,
          data: localUser,
        );

        final remoteEvent =
            LocalFirstEvent.createNewInsertEvent<UserModel>(
          repository: repo,
          needSync: false,
          data: remoteUser,
        );

        final result = repo.resolveConflictEvent(localEvent, remoteEvent);

        // When resolveConflict creates a new merged object (not identical to
        // either local or remote), the identical() check falls through to
        // remote, so the returned event uses remote's data
        expect(result.data.avatarUrl, 'https://remote.com');
        expect(result.syncStatus, SyncStatus.ok);
      });
    });

    group('Chat repository onConflictEvent', () {
      test('returns local event with SyncStatus.ok when local wins', () {
        final repo = buildChatRepository();
        final newTime = DateTime.utc(2025, 1, 1, 13, 0);
        final oldTime = DateTime.utc(2025, 1, 1, 12, 0);

        final localChat = ChatModel(
          id: 'chat1',
          name: 'Local Chat',
          createdBy: 'user1',
          updatedAt: newTime,
        );
        final remoteChat = ChatModel(
          id: 'chat1',
          name: 'Remote Chat',
          createdBy: 'user1',
          updatedAt: oldTime,
        );

        final localEvent =
            LocalFirstEvent.createNewInsertEvent<ChatModel>(
          repository: repo,
          needSync: true,
          data: localChat,
        );

        final remoteEvent =
            LocalFirstEvent.createNewInsertEvent<ChatModel>(
          repository: repo,
          needSync: false,
          data: remoteChat,
        );

        final result = repo.resolveConflictEvent(localEvent, remoteEvent);

        expect(result.data.name, 'Local Chat');
        expect(result.syncStatus, SyncStatus.ok);
      });

      test('returns remote event with SyncStatus.ok when remote wins', () {
        final repo = buildChatRepository();
        final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
        final newTime = DateTime.utc(2025, 1, 1, 13, 0);

        final localChat = ChatModel(
          id: 'chat1',
          name: 'Local Chat',
          createdBy: 'user1',
          updatedAt: oldTime,
        );
        final remoteChat = ChatModel(
          id: 'chat1',
          name: 'Remote Chat',
          createdBy: 'user1',
          updatedAt: newTime,
        );

        final localEvent =
            LocalFirstEvent.createNewInsertEvent<ChatModel>(
          repository: repo,
          needSync: true,
          data: localChat,
        );

        final remoteEvent =
            LocalFirstEvent.createNewInsertEvent<ChatModel>(
          repository: repo,
          needSync: false,
          data: remoteChat,
        );

        final result = repo.resolveConflictEvent(localEvent, remoteEvent);

        expect(result.data.name, 'Remote Chat');
        expect(result.syncStatus, SyncStatus.ok);
      });

      test('returns merged event preserving closedBy and lastMessage', () {
        final repo = buildChatRepository();
        final newTime = DateTime.utc(2025, 1, 1, 13, 0);
        final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
        final laterMsgTime = DateTime.utc(2025, 1, 1, 14, 0);

        final localChat = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: newTime,
          lastMessageAt: oldTime,
          closedBy: null,
        );
        final remoteChat = ChatModel(
          id: 'chat1',
          name: 'Chat',
          createdBy: 'user1',
          updatedAt: oldTime,
          lastMessageAt: laterMsgTime,
          lastMessageText: 'Remote msg',
          closedBy: 'admin',
        );

        final localEvent =
            LocalFirstEvent.createNewInsertEvent<ChatModel>(
          repository: repo,
          needSync: true,
          data: localChat,
        );

        final remoteEvent =
            LocalFirstEvent.createNewInsertEvent<ChatModel>(
          repository: repo,
          needSync: false,
          data: remoteChat,
        );

        final result = repo.resolveConflictEvent(localEvent, remoteEvent);

        expect(result.data.lastMessageAt, laterMsgTime);
        expect(result.data.lastMessageText, 'Remote msg');
        expect(result.data.closedBy, 'admin');
        expect(result.syncStatus, SyncStatus.ok);
      });
    });

    group('Message repository onConflictEvent', () {
      test('returns local event with SyncStatus.ok when local wins', () {
        final repo = buildMessageRepository();
        final newTime = DateTime.utc(2025, 1, 1, 13, 0);
        final oldTime = DateTime.utc(2025, 1, 1, 12, 0);

        final localMsg = MessageModel(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Local',
          updatedAt: newTime,
        );
        final remoteMsg = MessageModel(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Remote',
          updatedAt: oldTime,
        );

        final localEvent =
            LocalFirstEvent.createNewInsertEvent<MessageModel>(
          repository: repo,
          needSync: true,
          data: localMsg,
        );

        final remoteEvent =
            LocalFirstEvent.createNewInsertEvent<MessageModel>(
          repository: repo,
          needSync: false,
          data: remoteMsg,
        );

        final result = repo.resolveConflictEvent(localEvent, remoteEvent);

        expect(result.data.text, 'Local');
        expect(result.syncStatus, SyncStatus.ok);
      });

      test('returns remote event with SyncStatus.ok when remote wins', () {
        final repo = buildMessageRepository();
        final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
        final newTime = DateTime.utc(2025, 1, 1, 13, 0);

        final localMsg = MessageModel(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Local',
          updatedAt: oldTime,
        );
        final remoteMsg = MessageModel(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Remote',
          updatedAt: newTime,
        );

        final localEvent =
            LocalFirstEvent.createNewInsertEvent<MessageModel>(
          repository: repo,
          needSync: true,
          data: localMsg,
        );

        final remoteEvent =
            LocalFirstEvent.createNewInsertEvent<MessageModel>(
          repository: repo,
          needSync: false,
          data: remoteMsg,
        );

        final result = repo.resolveConflictEvent(localEvent, remoteEvent);

        expect(result.data.text, 'Remote');
        expect(result.syncStatus, SyncStatus.ok);
      });

      test('preserves syncOperation from winning event', () {
        final repo = buildMessageRepository();
        final oldTime = DateTime.utc(2025, 1, 1, 12, 0);
        final newTime = DateTime.utc(2025, 1, 1, 13, 0);

        final localMsg = MessageModel(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Local',
          updatedAt: oldTime,
        );
        final remoteMsg = MessageModel(
          id: 'msg1',
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Remote',
          updatedAt: newTime,
        );

        final localEvent =
            LocalFirstEvent.createNewInsertEvent<MessageModel>(
          repository: repo,
          needSync: true,
          data: localMsg,
        );

        final remoteEvent =
            LocalFirstEvent.createNewUpdateEvent<MessageModel>(
          repository: repo,
          needSync: false,
          data: remoteMsg,
        ) as LocalFirstStateEvent<MessageModel>;

        final result = repo.resolveConflictEvent(localEvent, remoteEvent);

        // Remote wins, so syncOperation should come from remote event
        expect(result.syncOperation, SyncOperation.update);
        expect(result.syncStatus, SyncStatus.ok);
      });
    });
  });
}
