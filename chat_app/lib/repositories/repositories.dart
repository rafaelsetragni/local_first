import 'package:local_first/local_first.dart';
import '../models/field_names.dart';
import '../models/user_model.dart';
import '../models/chat_model.dart';
import '../models/message_model.dart';

/// Builds the user repository with conflict resolution
LocalFirstRepository<UserModel> buildUserRepository() {
  return LocalFirstRepository.create(
    name: RepositoryNames.user,
    getId: (user) => user.id,
    toJson: (user) => user.toJson(),
    fromJson: (json) => UserModel.fromJson(json),
    onConflictEvent: (local, remote) {
      final winner = UserModel.resolveConflict(local.data, remote.data);
      final source = identical(winner, local.data) ? local : remote;
      return source.updateEventState(
        syncStatus: SyncStatus.ok,
        syncOperation: source.syncOperation,
      );
    },
  );
}

/// Builds the chat repository with conflict resolution
LocalFirstRepository<ChatModel> buildChatRepository() {
  return LocalFirstRepository.create(
    name: RepositoryNames.chat,
    getId: (chat) => chat.id,
    toJson: (chat) => chat.toJson(),
    fromJson: (json) => ChatModel.fromJson(json),
    onConflictEvent: (local, remote) {
      final winner = ChatModel.resolveConflict(local.data, remote.data);
      final source = identical(winner, local.data) ? local : remote;
      return source.updateEventState(
        syncStatus: SyncStatus.ok,
        syncOperation: source.syncOperation,
      );
    },
  );
}

/// Builds the message repository with conflict resolution
LocalFirstRepository<MessageModel> buildMessageRepository() {
  return LocalFirstRepository.create(
    name: RepositoryNames.message,
    getId: (message) => message.id,
    toJson: (message) => message.toJson(),
    fromJson: (json) => MessageModel.fromJson(json),
    onConflictEvent: (local, remote) {
      final winner = MessageModel.resolveConflict(local.data, remote.data);
      final source = identical(winner, local.data) ? local : remote;
      return source.updateEventState(
        syncStatus: SyncStatus.ok,
        syncOperation: source.syncOperation,
      );
    },
  );
}
