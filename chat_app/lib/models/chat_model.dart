import 'field_names.dart';

/// Represents a chat room/conversation in the application
class ChatModel {
  final String id;
  final String name;
  final String createdBy;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastMessageAt;
  final String? lastMessageText;
  final String? lastMessageSender;

  ChatModel._({
    required this.id,
    required this.name,
    required this.createdBy,
    this.avatarUrl,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessageAt,
    this.lastMessageText,
    this.lastMessageSender,
  });

  /// Factory constructor with optional ID generation from sanitized name
  factory ChatModel({
    String? id,
    required String name,
    required String createdBy,
    String? avatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastMessageAt,
    String? lastMessageText,
    String? lastMessageSender,
  }) {
    final now = DateTime.now().toUtc();
    final sanitizedId = id ?? _sanitizeId(name);

    return ChatModel._(
      id: sanitizedId,
      name: name,
      createdBy: createdBy,
      avatarUrl: avatarUrl,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
      lastMessageAt: lastMessageAt,
      lastMessageText: lastMessageText,
      lastMessageSender: lastMessageSender,
    );
  }

  /// Sanitize string to be used as ID (lowercase, trim, replace spaces with underscores)
  static String _sanitizeId(String text) {
    return text.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_');
  }

  /// Convert model to JSON map
  Map<String, dynamic> toJson() {
    return {
      CommonFields.id: id,
      ChatFields.name: name,
      ChatFields.createdBy: createdBy,
      if (avatarUrl != null) ChatFields.avatarUrl: avatarUrl,
      CommonFields.createdAt: createdAt.toIso8601String(),
      CommonFields.updatedAt: updatedAt.toIso8601String(),
      if (lastMessageAt != null)
        ChatFields.lastMessageAt: lastMessageAt!.toIso8601String(),
      if (lastMessageText != null) ChatFields.lastMessageText: lastMessageText,
      if (lastMessageSender != null)
        ChatFields.lastMessageSender: lastMessageSender,
    };
  }

  /// Create model from JSON map
  factory ChatModel.fromJson(Map<String, dynamic> json) {
    return ChatModel._(
      id: json[CommonFields.id] as String,
      name: json[ChatFields.name] as String,
      createdBy: json[ChatFields.createdBy] as String,
      avatarUrl: json[ChatFields.avatarUrl] as String?,
      createdAt: DateTime.parse(json[CommonFields.createdAt] as String),
      updatedAt: DateTime.parse(json[CommonFields.updatedAt] as String),
      lastMessageAt: json[ChatFields.lastMessageAt] != null
          ? DateTime.parse(json[ChatFields.lastMessageAt] as String)
          : null,
      lastMessageText: json[ChatFields.lastMessageText] as String?,
      lastMessageSender: json[ChatFields.lastMessageSender] as String?,
    );
  }

  /// Resolve conflicts between local and remote versions using Last-Write-Wins (LWW)
  /// with lastMessageAt merge strategy
  static ChatModel resolveConflict(ChatModel local, ChatModel remote) {
    // LWW: If timestamps are equal, prefer remote (server wins tie)
    if (local.updatedAt == remote.updatedAt) {
      return remote;
    }

    // Choose the version with the most recent updatedAt
    final preferred = local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
    final fallback = identical(preferred, local) ? remote : local;

    // Merge lastMessageAt: take the later timestamp and its associated text/sender
    DateTime? mergedLastMessageAt;
    String? mergedLastMessageText;
    String? mergedLastMessageSender;

    if (preferred.lastMessageAt != null && fallback.lastMessageAt != null) {
      if (preferred.lastMessageAt!.isAfter(fallback.lastMessageAt!)) {
        mergedLastMessageAt = preferred.lastMessageAt;
        mergedLastMessageText = preferred.lastMessageText;
        mergedLastMessageSender = preferred.lastMessageSender;
      } else {
        mergedLastMessageAt = fallback.lastMessageAt;
        mergedLastMessageText = fallback.lastMessageText;
        mergedLastMessageSender = fallback.lastMessageSender;
      }
    } else if (preferred.lastMessageAt != null) {
      mergedLastMessageAt = preferred.lastMessageAt;
      mergedLastMessageText = preferred.lastMessageText;
      mergedLastMessageSender = preferred.lastMessageSender;
    } else if (fallback.lastMessageAt != null) {
      mergedLastMessageAt = fallback.lastMessageAt;
      mergedLastMessageText = fallback.lastMessageText;
      mergedLastMessageSender = fallback.lastMessageSender;
    }

    // Merge avatarUrl: prefer non-null value, or use preferred
    final mergedAvatarUrl = preferred.avatarUrl ?? fallback.avatarUrl;

    // Only create new object if merge changed something
    if (mergedLastMessageAt == preferred.lastMessageAt &&
        mergedLastMessageText == preferred.lastMessageText &&
        mergedLastMessageSender == preferred.lastMessageSender &&
        mergedAvatarUrl == preferred.avatarUrl) {
      return preferred;
    }

    // Create merged version
    return ChatModel._(
      id: preferred.id,
      name: preferred.name,
      createdBy: preferred.createdBy,
      avatarUrl: mergedAvatarUrl,
      createdAt: preferred.createdAt,
      updatedAt: preferred.updatedAt,
      lastMessageAt: mergedLastMessageAt,
      lastMessageText: mergedLastMessageText,
      lastMessageSender: mergedLastMessageSender,
    );
  }

  @override
  String toString() {
    return 'ChatModel(id: $id, name: $name, createdBy: $createdBy, '
        'avatarUrl: $avatarUrl, lastMessageAt: $lastMessageAt, '
        'lastMessageText: $lastMessageText, lastMessageSender: $lastMessageSender)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatModel &&
        other.id == id &&
        other.name == name &&
        other.createdBy == createdBy &&
        other.avatarUrl == avatarUrl &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.lastMessageAt == lastMessageAt &&
        other.lastMessageText == lastMessageText &&
        other.lastMessageSender == lastMessageSender;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      createdBy,
      avatarUrl,
      createdAt,
      updatedAt,
      lastMessageAt,
      lastMessageText,
      lastMessageSender,
    );
  }
}
