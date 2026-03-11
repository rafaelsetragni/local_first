import 'package:local_first/local_first.dart';

import 'field_names.dart';

/// Represents a message within a chat room
class MessageModel {
  final String id;
  final String chatId;
  final String senderId;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSystemMessage;

  /// Sender ID used for system messages
  static const systemSenderId = '_system_';

  MessageModel._({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    this.isSystemMessage = false,
  });

  /// Factory constructor with optional ID generation using UUID V7
  factory MessageModel({
    String? id,
    required String chatId,
    required String senderId,
    required String text,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool isSystemMessage = false,
  }) {
    final now = DateTime.now().toUtc();
    final timestamp = createdAt ?? now;

    return MessageModel._(
      id: id ?? IdUtil.uuidV7(),
      chatId: chatId,
      senderId: senderId,
      text: text,
      createdAt: timestamp,
      updatedAt: updatedAt ?? now,
      isSystemMessage: isSystemMessage,
    );
  }

  /// Creates a system message for the chat
  factory MessageModel.system({
    required String chatId,
    required String text,
    DateTime? createdAt,
  }) {
    final now = DateTime.now().toUtc();
    final timestamp = createdAt ?? now;

    return MessageModel._(
      id: IdUtil.uuidV7(),
      chatId: chatId,
      senderId: systemSenderId,
      text: text,
      createdAt: timestamp,
      updatedAt: timestamp,
      isSystemMessage: true,
    );
  }

  /// Convert model to JSON map
  Map<String, dynamic> toJson() {
    return {
      CommonFields.id: id,
      MessageFields.chatId: chatId,
      MessageFields.senderId: senderId,
      MessageFields.text: text,
      CommonFields.createdAt: createdAt.toIso8601String(),
      CommonFields.updatedAt: updatedAt.toIso8601String(),
      if (isSystemMessage) MessageFields.isSystemMessage: isSystemMessage,
    };
  }

  /// Create model from JSON map
  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel._(
      id: json[CommonFields.id] as String,
      chatId: json[MessageFields.chatId] as String,
      senderId: json[MessageFields.senderId] as String,
      text: json[MessageFields.text] as String,
      createdAt: DateTime.parse(json[CommonFields.createdAt] as String),
      updatedAt: DateTime.parse(json[CommonFields.updatedAt] as String),
      isSystemMessage: json[MessageFields.isSystemMessage] as bool? ?? false,
    );
  }

  /// Resolve conflicts between local and remote versions using Last-Write-Wins (LWW)
  /// Messages are typically append-only, so conflicts are rare
  static MessageModel resolveConflict(MessageModel local, MessageModel remote) {
    // Simple LWW: Most recent updatedAt wins
    // On tie, prefer remote (server wins)
    if (local.updatedAt == remote.updatedAt) {
      return remote;
    }

    return local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
  }

  @override
  String toString() {
    final prefix = isSystemMessage ? '[SYSTEM] ' : '';
    return 'MessageModel(id: $id, chatId: $chatId, senderId: $senderId, '
        'text: "$prefix${text.length > 20 ? '${text.substring(0, 20)}...' : text}")';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MessageModel &&
        other.id == id &&
        other.chatId == chatId &&
        other.senderId == senderId &&
        other.text == text &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.isSystemMessage == isSystemMessage;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      chatId,
      senderId,
      text,
      createdAt,
      updatedAt,
      isSystemMessage,
    );
  }
}
