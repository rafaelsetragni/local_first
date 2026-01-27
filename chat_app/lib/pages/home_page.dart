import 'package:flutter/material.dart';

import '../models/chat_model.dart';
import '../services/repository_service.dart';
import '../widgets/avatar_preview.dart';
import '../widgets/chat_tile.dart';
import 'chat_page.dart';

/// Home page displaying a list of all available chats
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _repositoryService = RepositoryService();

  /// Opens dialog to update the current user's avatar URL.
  Future<void> _onAvatarTap(BuildContext context, String currentAvatar) async {
    final url = await _promptAvatarDialog(context, currentAvatar);
    if (url == null) return;
    await _repositoryService.updateAvatarUrl(url);
    setState(() {}); // Refresh UI with new avatar
  }

  @override
  Widget build(BuildContext context) {
    final user = _repositoryService.authenticatedUser;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (user != null) ...[
              GestureDetector(
                onTap: () => _onAvatarTap(context, user.avatarUrl ?? ''),
                child: AvatarPreview(
                  avatarUrl: user.avatarUrl ?? '',
                  radius: 16,
                ),
              ),
              const SizedBox(width: 12),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Local First Chat'),
                if (user != null)
                  Text(
                    user.username,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ],
        ),
        actions: [
          // WebSocket connection indicator
          StreamBuilder<bool>(
            stream: _repositoryService.connectionState,
            initialData: _repositoryService.isConnected,
            builder: (context, snapshot) {
              final isConnected = snapshot.data ?? false;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: isConnected ? Colors.green : Colors.grey,
                  size: 20,
                ),
              );
            },
          ),
          // Logout button
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final confirmed = await _showConfirmDialog(
                context,
                'Sign Out',
                'Are you sure you want to sign out?',
              );
              if (confirmed == true && context.mounted) {
                await _repositoryService.signOut();
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<List<ChatModel>>(
        stream: _repositoryService.watchChats(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }

          final chats = snapshot.data ?? [];

          if (chats.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No chats yet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the + button to create a chat',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index];
              return Dismissible(
                key: Key(chat.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (direction) async {
                  return await _showConfirmDialog(
                    context,
                    'Delete Chat',
                    'Are you sure you want to delete "${chat.name}"?',
                  );
                },
                onDismissed: (direction) async {
                  await _repositoryService.deleteChat(chat.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${chat.name} deleted'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
                background: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(
                    Icons.delete,
                    color: Colors.white,
                  ),
                ),
                child: ChatTile(
                  chat: chat,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ChatPage(chat: chat),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateChatDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Shows a dialog to create a new chat
  Future<void> _showCreateChatDialog(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Chat name',
            hintText: 'Enter chat name',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(context).pop(value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.of(context).pop(controller.text.trim());
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        await _repositoryService.createChat(chatName: result);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Chat "$result" created'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    }
  }

  /// Shows a confirmation dialog and returns true if confirmed
  Future<bool?> _showConfirmDialog(
    BuildContext context,
    String title,
    String message,
  ) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  /// Shows a dialog to update the user's avatar URL with live preview
  Future<String?> _promptAvatarDialog(
    BuildContext context,
    String currentAvatar,
  ) {
    final controller = TextEditingController(text: currentAvatar);
    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final previewUrl = controller.text.trim();
            return AlertDialog(
              title: const Text('Update avatar URL'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AvatarPreview(radius: 36, avatarUrl: previewUrl),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Avatar URL',
                      hintText: 'paste your url here',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(previewUrl),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
