import 'package:flutter/material.dart';

import 'unread_counts_provider.dart';

/// A widget that displays an unread message count badge.
///
/// This widget reads from UnreadCountsProvider, so it only rebuilds
/// when the provider's data changes, without managing its own subscription.
class UnreadBadge extends StatelessWidget {
  final String chatId;

  const UnreadBadge({
    super.key,
    required this.chatId,
  });

  @override
  Widget build(BuildContext context) {
    final unreadCount = UnreadCountsProvider.getCount(context, chatId);

    if (unreadCount <= 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        unreadCount > 99 ? '99+' : unreadCount.toString(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
