import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/repository_service.dart';
import '../widgets/avatar_preview.dart';
import '../widgets/connection_status_bar.dart';
import '../widgets/message_bubble.dart';

/// Chat page displaying messages and input for a specific chat
class ChatPage extends StatefulWidget {
  final ChatModel chat;

  const ChatPage({
    super.key,
    required this.chat,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const _pageSize = 25;
  static const _loadMoreThreshold = 0.8;

  final _repositoryService = RepositoryService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _messageFocusNode = FocusNode();

  // Stream subscriptions
  StreamSubscription<ChatModel?>? _chatSubscription;
  StreamSubscription<List<MessageModel>>? _newMessagesSubscription;
  StreamSubscription<List<UserModel>>? _usersSubscription;

  // State data
  late ChatModel _currentChat;
  List<MessageModel> _messages = [];
  Map<String, String> _avatarMap = {};
  bool _isLoading = true;

  // Pagination state
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _currentChat = widget.chat;
    _scrollController.addListener(_onScroll);
    _setupSubscriptions();
  }

  void _setupSubscriptions() {
    // Chat subscription
    _chatSubscription = _repositoryService
        .watchChat(widget.chat.id)
        .listen((chat) {
      if (chat != null && mounted) {
        setState(() => _currentChat = chat);
      }
    });

    // Users subscription for avatars
    _usersSubscription = _repositoryService.watchUsers().listen((users) {
      if (mounted) {
        final avatarMap = <String, String>{};
        for (final user in users) {
          avatarMap[user.username] = user.avatarUrl ?? '';
        }
        setState(() => _avatarMap = avatarMap);
      }
    });

    // Load initial messages
    _loadInitialMessages();
  }

  Future<void> _loadInitialMessages() async {
    try {
      final messages = await _repositoryService.getMessages(
        widget.chat.id,
        limit: _pageSize,
      );

      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
          _hasMore = messages.length >= _pageSize;
        });

        // Start watching for new messages after loading initial ones
        _setupNewMessagesSubscription();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setupNewMessagesSubscription() {
    // Watch for new messages (created after the newest one we have)
    final newestTime = _messages.isNotEmpty
        ? _messages.first.createdAt
        : DateTime.now().toUtc();

    _newMessagesSubscription?.cancel();
    _newMessagesSubscription = _repositoryService
        .watchNewMessages(widget.chat.id, newestTime)
        .listen((newMessages) {
      if (mounted && newMessages.isNotEmpty) {
        setState(() {
          // Add new messages to the beginning (they are newest)
          for (final msg in newMessages) {
            if (!_messages.any((m) => m.id == msg.id)) {
              _messages.insert(0, msg);
            }
          }
        });
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // Since list is reversed, we check when user scrolls UP (towards older messages)
    // In a reversed list, maxScrollExtent is at the TOP (oldest messages)
    if (currentScroll >= maxScroll * _loadMoreThreshold) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final moreMessages = await _repositoryService.getMessages(
        widget.chat.id,
        limit: _pageSize,
        offset: _messages.length,
      );

      if (mounted) {
        setState(() {
          // Filter out duplicates and add to the end (older messages)
          for (final msg in moreMessages) {
            if (!_messages.any((m) => m.id == msg.id)) {
              _messages.add(msg);
            }
          }
          _hasMore = moreMessages.length >= _pageSize;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _chatSubscription?.cancel();
    _newMessagesSubscription?.cancel();
    _usersSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  /// Opens dialog to update the chat's avatar URL.
  Future<void> _onChatAvatarTap(BuildContext context, String currentAvatar) async {
    final url = await _promptChatAvatarDialog(context, currentAvatar);
    if (url == null) return;
    await _repositoryService.updateChatAvatar(widget.chat.id, url);
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar = _currentChat.avatarUrl != null && _currentChat.avatarUrl!.isNotEmpty;

    return ConnectionStatusBar(
      child: Scaffold(
        appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => _onChatAvatarTap(context, _currentChat.avatarUrl ?? ''),
              child: hasAvatar
                  ? AvatarPreview(
                      avatarUrl: _currentChat.avatarUrl!,
                      radius: 16,
                    )
                  : CircleAvatar(
                      radius: 16,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        _currentChat.name.isNotEmpty ? _currentChat.name[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _currentChat.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
        body: Column(
          children: [
            // Messages list
            Expanded(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: _buildMessagesList(context),
              ),
            ),
            // Message input
            _buildMessageInput(context),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.message_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to send a message',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
            ),
          ],
        ),
      );
    }

    final authenticatedUser = _repositoryService.authenticatedUser;

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      // Add 1 for loading indicator when loading more
      itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        // Show loading indicator at the end (top in reversed list)
        if (_isLoadingMore && index == _messages.length) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        // Messages are already sorted newest first from getMessages
        final message = _messages[index];
        final isOwnMessage = authenticatedUser != null &&
            message.senderId == authenticatedUser.username;
        final avatarUrl = _avatarMap[message.senderId] ?? '';

        return MessageBubble(
          message: message,
          isOwnMessage: isOwnMessage,
          avatarUrl: avatarUrl,
        );
      },
    );
  }

  Widget _buildMessageInput(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.viewPaddingOf(context).bottom + 8,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              focusNode: _messageFocusNode,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _sendMessage,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  /// Sends the message and clears the input field
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    // Clear input immediately for better UX
    _messageController.clear();

    try {
      await _repositoryService.sendMessage(
        chatId: widget.chat.id,
        text: text,
      );

      // Scroll to bottom after sending
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }

      // Return focus to message field
      _messageFocusNode.requestFocus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending message: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        // Restore the message text on error
        _messageController.text = text;
      }
    }
  }

  /// Shows a dialog to update the chat's avatar URL with live preview
  Future<String?> _promptChatAvatarDialog(
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
              title: const Text('Update chat avatar URL'),
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
