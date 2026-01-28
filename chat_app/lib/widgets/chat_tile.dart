import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/chat_model.dart';
import 'avatar_preview.dart';
import 'unread_badge.dart';
import 'unread_counts_provider.dart';

/// A list tile widget that displays a chat room summary
class ChatTile extends StatelessWidget {
  final ChatModel chat;
  final VoidCallback onTap;

  const ChatTile({
    super.key,
    required this.chat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasAvatar = chat.avatarUrl != null && chat.avatarUrl!.isNotEmpty;

    return ListTile(
      leading: hasAvatar
          ? AvatarPreview(
              avatarUrl: chat.avatarUrl!,
              radius: 20,
            )
          : CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                chat.name.isNotEmpty ? chat.name[0].toUpperCase() : '?',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
      title: Text(
        chat.name,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        _buildSubtitle(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          fontSize: 13,
        ),
      ),
      trailing: _buildTrailing(context),
      onTap: onTap,
    );
  }

  /// Builds the trailing widget with timestamp and unread badge
  Widget? _buildTrailing(BuildContext context) {
    final hasTimestamp = chat.lastMessageAt != null;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasTimestamp)
          _TimestampText(chatId: chat.id, timestamp: chat.lastMessageAt!),
        const SizedBox(height: 4),
        UnreadBadge(chatId: chat.id),
      ],
    );
  }

  /// Builds the subtitle text showing last message or creation info
  String _buildSubtitle() {
    if (chat.lastMessageText != null && chat.lastMessageSender != null) {
      return '${chat.lastMessageSender}: ${chat.lastMessageText}';
    }
    return 'Created by ${chat.createdBy}';
  }
}

/// A timestamp text widget that styles itself based on unread count.
///
/// This widget reads from UnreadCountsProvider, so it only rebuilds
/// when the provider's data changes, without managing its own subscription.
class _TimestampText extends StatelessWidget {
  final String chatId;
  final DateTime timestamp;

  const _TimestampText({
    required this.chatId,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = UnreadCountsProvider.getCount(context, chatId) > 0;

    return Text(
      _formatTimestamp(timestamp),
      style: TextStyle(
        color: hasUnread
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        fontSize: 12,
        fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  /// Formats timestamp to show time if today, or date if older
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final localTimestamp = timestamp.toLocal();
    final difference = now.difference(localTimestamp);

    if (difference.inDays == 0) {
      // Today - show time
      return DateFormat.Hm().format(localTimestamp);
    } else if (difference.inDays == 1) {
      // Yesterday
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      // This week - show day name
      return DateFormat.E().format(localTimestamp);
    } else {
      // Older - show date
      return DateFormat.MMMd().format(localTimestamp);
    }
  }
}
