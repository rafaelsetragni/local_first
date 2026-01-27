import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/message_model.dart';
import 'avatar_preview.dart';

/// A chat bubble widget that displays a message with sender and timestamp
class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isOwnMessage;
  final String avatarUrl;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isOwnMessage,
    required this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: AvatarPreview(avatarUrl: avatarUrl, radius: 16),
    );

    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      padding: const EdgeInsets.all(12),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.65,
      ),
      decoration: BoxDecoration(
        color: isOwnMessage
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sender username
          Text(
            message.senderId,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: isOwnMessage
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          // Message text
          Text(
            message.text,
            style: TextStyle(
              fontSize: 15,
              color: isOwnMessage
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          // Timestamp
          Text(
            _formatTimestamp(message.createdAt),
            style: TextStyle(
              fontSize: 10,
              color: isOwnMessage
                  ? Theme.of(
                      context,
                    ).colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                  : Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment: isOwnMessage
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: isOwnMessage ? [bubble, avatar] : [avatar, bubble],
      ),
    );
  }

  /// Formats timestamp to show time
  String _formatTimestamp(DateTime timestamp) {
    final localTimestamp = timestamp.toLocal();
    return DateFormat.Hm().format(localTimestamp);
  }
}
