/// Repository names used in the chat application
class RepositoryNames {
  static const user = 'user';
  static const chat = 'chat';
  static const message = 'message';
}

/// Common field names shared across multiple models
class CommonFields {
  static const id = 'id';
  static const username = 'username';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';
}

/// Fields specific to UserModel
class UserFields {
  static const avatarUrl = 'avatar_url';
}

/// Fields specific to ChatModel
class ChatFields {
  static const name = 'name';
  static const createdBy = 'created_by';
  static const avatarUrl = 'avatar_url';
  static const lastMessageAt = 'last_message_at';
  static const lastMessageText = 'last_message_text';
  static const lastMessageSender = 'last_message_sender';
}

/// Fields specific to MessageModel
class MessageFields {
  static const chatId = 'chat_id';
  static const senderId = 'sender_id';
  static const text = 'text';
}
