import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:local_first/local_first.dart';
import 'package:local_first_websocket/local_first_websocket.dart';
import 'package:local_first_periodic_strategy/local_first_periodic_strategy.dart';
import 'package:local_first_sqlite_storage/local_first_sqlite_storage.dart';
import 'package:local_first_shared_preferences/local_first_shared_preferences.dart';

import '../config/app_config.dart';
import '../models/field_names.dart';
import '../models/user_model.dart';
import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../repositories/repositories.dart';
import '../services/navigator_service.dart';
import '../services/read_state_manager.dart';
import '../services/sync_state_manager.dart';

/// Central orchestrator for chat app using WebSocket and Periodic sync
class RepositoryService {
  static const tag = 'RepositoryService';

  static RepositoryService? _instance;
  factory RepositoryService() => _instance ??= RepositoryService._internal();

  /// For testing only - allows injecting a mock instance
  @visibleForTesting
  static set instance(RepositoryService? testInstance) {
    _instance = testInstance;
  }

  LocalFirstClient? localFirst;
  UserModel? authenticatedUser;
  String _currentNamespace = 'default';
  final _lastUsernameKey = '__last_username__';
  final _hiddenChatsKey = '__hidden_chats__';
  SyncStateManager? _syncStateManager;
  ReadStateManager? _readStateManager;
  String? _currentOpenChatId;
  Set<String> _hiddenChatIds = {};
  final _readStateChangedController = StreamController<void>.broadcast();
  final http.Client _httpClient = http.Client();
  final NavigatorService _navigatorService = NavigatorService();

  final LocalFirstRepository<UserModel> userRepository;
  final LocalFirstRepository<ChatModel> chatRepository;
  final LocalFirstRepository<MessageModel> messageRepository;
  late final WebSocketSyncStrategy webSocketStrategy;
  late final PeriodicSyncStrategy periodicStrategy;

  RepositoryService._internal()
      : userRepository = buildUserRepository(),
        chatRepository = buildChatRepository(),
        messageRepository = buildMessageRepository() {
    // Initialize WebSocketSyncStrategy for real-time push notifications
    // Pending queue disabled - let periodic strategy handle offline events
    webSocketStrategy = WebSocketSyncStrategy(
      websocketUrl: websocketUrl,
      reconnectDelay: Duration(milliseconds: 1500),
      heartbeatInterval: Duration(seconds: 60),
      enablePendingQueue: false,
      onBuildSyncFilter: (_) async => null, // Don't pull - only receive pushes
      onSyncCompleted: (filter, events) async {}, // No-op - periodic handles state
    );

    // Initialize PeriodicSyncStrategy for consistency and offline sync
    // Uses server sequence to fetch missed events
    periodicStrategy = PeriodicSyncStrategy(
      syncInterval: Duration(seconds: 30),
      repositoryNames: [
        RepositoryNames.user,
        RepositoryNames.chat,
        RepositoryNames.message,
      ],
      onFetchEvents: _fetchEvents,
      onPushEvents: _pushEvents,
      onBuildSyncFilter: _buildSyncFilter,
      onSaveSyncState: _onSyncCompleted,
    );
  }

  String get namespace => _currentNamespace;
  Stream<bool> get connectionState => webSocketStrategy.connectionChanges;
  bool get isConnected => webSocketStrategy.latestConnectionState ?? false;

  /// Builds sync filter using server sequence numbers
  Future<JsonMap<dynamic>?> _buildSyncFilter(String repositoryName) async {
    final manager = _syncStateManager;
    if (manager == null) return null;

    final lastSequence = await manager.getLastSequence(repositoryName);
    if (lastSequence == null) {
      return null; // No previous sync - request all events
    }

    return {'afterSequence': lastSequence};
  }

  /// Fetches events from REST API for periodic sync
  Future<List<JsonMap>> _fetchEvents(String repositoryName) async {
    try {
      final filter = await _buildSyncFilter(repositoryName);
      final uri = filter != null && filter.containsKey('afterSequence')
          ? Uri.parse(
              '$baseHttpUrl/api/events/$repositoryName?seq=${filter['afterSequence']}',
            )
          : Uri.parse('$baseHttpUrl/api/events/$repositoryName');

      final response = await _httpClient.get(uri).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch events: ${response.statusCode}');
      }

      // Decode with allowMalformed to handle invalid UTF-8 sequences
      final responseBody = utf8.decode(response.bodyBytes, allowMalformed: true);
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final events = (data['events'] as List).cast<Map<String, dynamic>>();

      return events;
    } catch (e, s) {
      dev.log(
        'Error fetching events',
        name: 'RepositoryService',
        error: e,
        stackTrace: s,
      );
      return [];
    }
  }

  /// Pushes events to REST API for periodic sync
  Future<bool> _pushEvents(
    String repositoryName,
    LocalFirstEvents events,
  ) async {
    if (events.isEmpty) return true;

    try {
      final eventList = events.map((e) => e.toJson()).toList();

      final jsonBody = jsonEncode(
        {'events': eventList},
        toEncodable: (obj) => obj is DateTime ? obj.toIso8601String() : obj,
      );

      final response = await _httpClient.post(
        Uri.parse('$baseHttpUrl/api/events/$repositoryName/batch'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: utf8.encode(jsonBody),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 201) {
        dev.log(
          'Failed to push events: ${response.statusCode}',
          name: 'RepositoryService',
        );
        return false;
      }

      return true;
    } catch (e, s) {
      dev.log(
        'Error pushing events',
        name: 'RepositoryService',
        error: e,
        stackTrace: s,
      );
      return false;
    }
  }

  /// Called when sync is completed - saves the latest sequence
  Future<void> _onSyncCompleted(
    String repositoryName,
    List<JsonMap<dynamic>> events,
  ) async {
    final manager = _syncStateManager;
    if (manager == null || events.isEmpty) return;

    final maxSequence = manager.extractMaxSequence(events);
    if (maxSequence != null) {
      await manager.saveLastSequence(repositoryName, maxSequence);
    }
  }

  /// Initializes the client/storage and restores last logged user if possible
  Future<UserModel?> initialize() async {
    final localFirst = this.localFirst ??= LocalFirstClient(
      repositories: [
        userRepository,
        chatRepository,
        messageRepository,
      ],
      localStorage: SqliteLocalFirstStorage(
        databaseName: 'chat_app.db',
      ),
      keyValueStorage: SharedPreferencesConfigStorage(),
      syncStrategies: [webSocketStrategy, periodicStrategy],
    );

    await localFirst.initialize();

    // Initialize sync state manager after client is ready
    _syncStateManager = SyncStateManager(localFirst, () => _currentNamespace);
    _readStateManager = ReadStateManager(localFirst, () => _currentNamespace);

    return await restoreLastUser();
  }

  /// Extract models from events
  List<UserModel> _usersFromEvents(List<LocalFirstEvent<UserModel>> events) =>
      events.whereType<LocalFirstStateEvent<UserModel>>()
          .map((e) => e.data)
          .toList();

  List<ChatModel> _chatsFromEvents(List<LocalFirstEvent<ChatModel>> events) =>
      events.whereType<LocalFirstStateEvent<ChatModel>>()
          .map((e) => e.data)
          .toList();

  List<MessageModel> _messagesFromEvents(
      List<LocalFirstEvent<MessageModel>> events) =>
      events.whereType<LocalFirstStateEvent<MessageModel>>()
          .map((e) => e.data)
          .toList();

  /// Fetches a user from the remote server by userId
  Future<UserModel?> _fetchRemoteUser(String userId) async {
    try {
      final response = await _httpClient
          .get(Uri.parse('$baseHttpUrl/api/events/user/byDataId/$userId'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 404) {
        return null; // User doesn't exist on server
      }

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch user: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final eventData = data['event'] as Map<String, dynamic>;
      final userData = eventData['data'] as Map<String, dynamic>;

      return UserModel.fromJson(userData);
    } catch (e) {
      throw Exception('Failed to fetch remote user: $e');
    }
  }

  /// Signs in a user and starts all sync strategies
  Future<void> signIn({required String username}) async {
    localFirst?.stopAllStrategies();

    // Create local UserModel to generate userId
    final localUser = UserModel(username: username, avatarUrl: null);
    final userId = localUser.id;

    // Switch to user's namespace database
    await _switchUserDatabase(userId);

    // Fetch user from server via HTTP GET
    try {
      final remoteUser = await _fetchRemoteUser(userId);

      if (remoteUser != null) {
        // User exists on server - use remote data
        authenticatedUser = remoteUser;
      } else {
        // User doesn't exist on server - use local model
        authenticatedUser = localUser;
        await userRepository.upsert(localUser, needSync: true);
      }
    } catch (e) {
      throw Exception('Failed to sign in: $e');
    }

    // Persist login state
    await _persistLastUsername(username);

    // Start all sync strategies
    await localFirst?.startAllStrategies();

    // Navigate to home
    _navigatorService.navigateToHome();
  }

  /// Signs out the current user
  Future<void> signOut() async {
    localFirst?.stopAllStrategies();
    authenticatedUser = null;
    await _switchUserDatabase('');
    await _setGlobalString(_lastUsernameKey, '');

    // Navigate to sign in
    _navigatorService.navigateToSignIn();
  }

  /// Restores the last logged user if available
  Future<UserModel?> restoreLastUser() async {
    final username = await _getGlobalString(_lastUsernameKey);
    if (username == null || username.isEmpty) return null;

    try {
      final normalizedId = UserModel(username: username, avatarUrl: null).id;
      await _switchUserDatabase(normalizedId);

      final results = await userRepository.query()
          .where(userRepository.idFieldName, isEqualTo: normalizedId)
          .getAll();

      if (results.isEmpty) return null;

      final user = (results.first as LocalFirstStateEvent<UserModel>).data;
      authenticatedUser = user;
      await localFirst?.startAllStrategies();
      return user;
    } catch (e) {
      dev.log('Failed to restore last user: $e', name: tag);
      return null;
    }
  }

  /// Persists the last username for auto-login
  Future<void> _persistLastUsername(String username) =>
      _setGlobalString(_lastUsernameKey, username);

  /// Gets a global string value (from default namespace)
  Future<String?> _getGlobalString(String key) async {
    final client = localFirst;
    if (client == null) return null;
    return _withGlobalString(() => client.getConfigValue(key));
  }

  /// Sets a global string value (in default namespace)
  Future<void> _setGlobalString(String key, String value) async {
    final client = localFirst;
    if (client == null) return;
    await _withGlobalString(() => client.setConfigValue(key, value));
  }

  /// Temporarily switches to default namespace, executes action, then restores
  Future<T> _withGlobalString<T>(Future<T> Function() action) async {
    final storage = localFirst?.localStorage;
    if (storage == null) return await action();

    final previous = _currentNamespace;
    await storage.useNamespace('default');
    try {
      return await action();
    } finally {
      await storage.useNamespace(previous);
    }
  }

  /// Switches to a user-specific database namespace
  Future<void> _switchUserDatabase(String userId) async {
    final db = localFirst;
    if (db == null) return;

    final namespace = _sanitizeNamespace(userId);
    if (_currentNamespace == namespace) return;

    _currentNamespace = namespace;
    await db.localStorage.useNamespace(namespace);

    // Load hidden chat IDs for this user
    await _loadHiddenChatIds();
  }

  /// Sanitizes username for use as database namespace
  String _sanitizeNamespace(String username) {
    if (username.isEmpty) return 'default';
    final sanitized = username.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_]'),
      '_',
    );
    return 'user_$sanitized';
  }

  // ========== HIDDEN CHATS MANAGEMENT ==========

  /// Loads hidden chat IDs from persistent storage
  Future<void> _loadHiddenChatIds() async {
    final client = localFirst;
    if (client == null) return;

    final json = await client.getConfigValue(_hiddenChatsKey);
    if (json == null || json.isEmpty) {
      _hiddenChatIds = {};
      return;
    }

    try {
      final List<dynamic> ids = jsonDecode(json);
      _hiddenChatIds = ids.cast<String>().toSet();
    } catch (e) {
      dev.log('Failed to load hidden chat IDs: $e', name: tag);
      _hiddenChatIds = {};
    }
  }

  /// Saves hidden chat IDs to persistent storage
  Future<void> _saveHiddenChatIds() async {
    final client = localFirst;
    if (client == null) return;

    final json = jsonEncode(_hiddenChatIds.toList());
    await client.setConfigValue(_hiddenChatsKey, json);
  }

  /// Adds a chat ID to the hidden list and persists it
  Future<void> _hideChat(String chatId) async {
    _hiddenChatIds.add(chatId);
    await _saveHiddenChatIds();
  }

  /// Checks if a chat is hidden
  bool _isChatHidden(String chatId) => _hiddenChatIds.contains(chatId);

  // ========== CHAT OPERATIONS ==========

  /// Gets all chats ordered by most recent activity (updatedAt)
  /// Filters out hidden chats that the user has removed locally
  Future<List<ChatModel>> getChats() async {
    final events = await chatRepository.query()
        .orderBy(CommonFields.updatedAt, descending: true)
        .getAll();
    final chats = _chatsFromEvents(events);
    return chats.where((chat) => !_isChatHidden(chat.id)).toList();
  }

  /// Watches all chats ordered by most recent activity (updatedAt)
  /// Filters out hidden chats that the user has removed locally
  Stream<List<ChatModel>> watchChats() {
    return chatRepository.query()
        .orderBy(CommonFields.updatedAt, descending: true)
        .watch()
        .map(_chatsFromEvents)
        .map((chats) => chats.where((chat) => !_isChatHidden(chat.id)).toList());
  }

  /// Watches a specific chat by ID
  Stream<ChatModel?> watchChat(String chatId) {
    return chatRepository.query()
        .where(chatRepository.idFieldName, isEqualTo: chatId)
        .watch()
        .map((events) {
      final chats = _chatsFromEvents(events);
      return chats.isNotEmpty ? chats.first : null;
    });
  }

  /// Creates a new chat
  Future<void> createChat({required String chatName}) async {
    final user = authenticatedUser;
    if (user == null) throw Exception('User not authenticated');

    final chat = ChatModel(
      name: chatName,
      createdBy: user.username,
    );

    await chatRepository.upsert(chat, needSync: true);
  }

  /// Closes a chat by marking it as closed and sending a system message.
  /// The chat is removed from the closing user's device but synced to others.
  /// Other users will see a system message and can delete their local copy.
  Future<void> closeChat(String chatId) async {
    final user = authenticatedUser;
    if (user == null) throw Exception('User not authenticated');

    // Get the current chat
    final chatResults = await chatRepository.query()
        .where(chatRepository.idFieldName, isEqualTo: chatId)
        .getAll();

    if (chatResults.isEmpty) {
      throw Exception('Chat not found');
    }

    final chatEvent = chatResults.first as LocalFirstStateEvent<ChatModel>;
    final chat = chatEvent.data;

    // Don't close an already closed chat
    if (chat.isClosed) {
      throw Exception('Chat is already closed');
    }

    final now = DateTime.now().toUtc();

    // Send a system message about the closure
    final systemMessage = MessageModel.system(
      chatId: chatId,
      text: 'Chat closed by ${user.username}',
      createdAt: now,
    );
    await messageRepository.upsert(systemMessage, needSync: true);

    // Update the chat to mark it as closed (synced to all users)
    final closedChat = chat.copyWith(
      closedBy: user.username,
      updatedAt: now,
      lastMessageAt: now,
      lastMessageText: systemMessage.text,
      lastMessageSender: systemMessage.senderId,
    );
    await chatRepository.upsert(closedChat, needSync: true);

    // Remove the chat from this user's local device (not synced)
    await deleteLocalChat(chatId);
  }

  /// Deletes a chat locally without syncing.
  /// Used for removing closed chats from local storage.
  /// Also adds the chat to the hidden list to prevent it from reappearing on sync.
  /// Cleans up read state for the chat.
  Future<void> deleteLocalChat(String chatId) async {
    await _hideChat(chatId);
    await _readStateManager?.deleteReadState(chatId);
    await chatRepository.delete(chatId, needSync: false);
  }

  /// Updates chat avatar
  Future<ChatModel> updateChatAvatar(String chatId, String avatarUrl) async {
    final chatResults = await chatRepository.query()
        .where(chatRepository.idFieldName, isEqualTo: chatId)
        .getAll();

    if (chatResults.isEmpty) {
      throw Exception('Chat not found');
    }

    final chatEvent = chatResults.first as LocalFirstStateEvent<ChatModel>;
    final chat = chatEvent.data;

    final updated = ChatModel(
      id: chat.id,
      name: chat.name,
      createdBy: chat.createdBy,
      avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
      createdAt: chat.createdAt,
      updatedAt: DateTime.now().toUtc(),
      lastMessageAt: chat.lastMessageAt,
      lastMessageText: chat.lastMessageText,
      lastMessageSender: chat.lastMessageSender,
    );

    await chatRepository.upsert(updated, needSync: true);
    return updated;
  }

  // ========== MESSAGE OPERATIONS ==========

  /// Gets messages in a specific chat with pagination
  /// Returns messages ordered by createdAt descending (newest first)
  Future<List<MessageModel>> getMessages(
    String chatId, {
    int limit = 25,
    int offset = 0,
  }) async {
    final events = await messageRepository.query()
        .where(MessageFields.chatId, isEqualTo: chatId)
        .orderBy(CommonFields.createdAt, descending: true)
        .startAfter(offset)
        .limitTo(limit)
        .getAll();
    return _messagesFromEvents(events);
  }

  /// Watches for new messages in a specific chat (real-time updates)
  /// Only returns messages created after the given timestamp
  Stream<List<MessageModel>> watchNewMessages(String chatId, DateTime after) {
    return messageRepository.query()
        .where(MessageFields.chatId, isEqualTo: chatId)
        .orderBy(CommonFields.createdAt, descending: false)
        .watch()
        .map((events) {
          final messages = _messagesFromEvents(events);
          return messages.where((m) => m.createdAt.isAfter(after)).toList();
        });
  }

  /// Watches messages in a specific chat (legacy - returns all)
  Stream<List<MessageModel>> watchMessages(String chatId) {
    return messageRepository.query()
        .where(MessageFields.chatId, isEqualTo: chatId)
        .orderBy(CommonFields.createdAt, descending: false)
        .watch()
        .map(_messagesFromEvents);
  }

  /// Sends a message in a chat and updates the chat's lastMessageAt
  Future<void> sendMessage({
    required String chatId,
    required String text,
  }) async {
    final user = authenticatedUser;
    if (user == null) throw Exception('User not authenticated');

    if (text.trim().isEmpty) return;

    final message = MessageModel(
      chatId: chatId,
      senderId: user.username,
      text: text.trim(),
    );

    // Save the message
    await messageRepository.upsert(message, needSync: true);

    // Update the chat's lastMessageAt
    final chatResults = await chatRepository.query()
        .where(chatRepository.idFieldName, isEqualTo: chatId)
        .getAll();

    if (chatResults.isNotEmpty) {
      final chatEvent = chatResults.first as LocalFirstStateEvent<ChatModel>;
      final chat = chatEvent.data;

      final updatedChat = ChatModel(
        id: chat.id,
        name: chat.name,
        createdBy: chat.createdBy,
        avatarUrl: chat.avatarUrl,
        createdAt: chat.createdAt,
        updatedAt: DateTime.now().toUtc(),
        lastMessageAt: message.createdAt,
        lastMessageText: message.text,
        lastMessageSender: message.senderId,
      );

      await chatRepository.upsert(updatedChat, needSync: true);
    }

    // Mark chat as read after sending to prevent own message from counting as unread
    await markChatAsRead(chatId);
  }

  /// Watches all users
  Stream<List<UserModel>> watchUsers() {
    return userRepository.query()
        .orderBy(CommonFields.username)
        .watch()
        .map(_usersFromEvents);
  }

  /// Updates user avatar
  Future<UserModel> updateAvatarUrl(String avatarUrl) async {
    final user = authenticatedUser;
    if (user == null) throw Exception('User not authenticated');

    final updated = UserModel(
      username: user.username,
      avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
      createdAt: user.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );

    await userRepository.upsert(updated, needSync: true);
    authenticatedUser = updated;
    return updated;
  }

  // ========== UNREAD COUNT OPERATIONS ==========

  /// Sets the currently open chat ID (to exclude from unread counts)
  void setCurrentOpenChat(String? chatId) {
    _currentOpenChatId = chatId;
  }

  /// Marks a chat as read by setting lastReadAt to now
  Future<void> markChatAsRead(String chatId) async {
    final manager = _readStateManager;
    if (manager == null) return;
    await manager.markChatAsRead(chatId);
    _readStateChangedController.add(null);
  }

  /// Gets the unread message count for a specific chat
  Future<int> getUnreadCount(String chatId) async {
    final manager = _readStateManager;
    if (manager == null) return 0;

    final lastReadAt = await manager.getLastReadAt(chatId);

    final events = await messageRepository
        .query()
        .where(MessageFields.chatId, isEqualTo: chatId)
        .getAll();

    final messages = _messagesFromEvents(events);

    if (lastReadAt == null) {
      // Never read - all messages are unread
      return messages.length;
    }

    // Count messages created after lastReadAt
    return messages.where((m) => m.createdAt.isAfter(lastReadAt)).length;
  }

  /// Gets total unread count across all chats, optionally excluding a chat
  /// Processes all chats in parallel for better performance
  /// Excludes hidden chats from the count
  Future<int> getTotalUnreadCount({String? excludeChatId}) async {
    final chats = await chatRepository.query().getAll();
    final chatModels = _chatsFromEvents(chats);

    // Filter out excluded chat, hidden chats, and process in parallel
    final chatsToCount = chatModels.where((chat) {
      if (_isChatHidden(chat.id)) return false;
      if (excludeChatId != null && chat.id == excludeChatId) return false;
      return true;
    });

    final futures = chatsToCount.map((chat) => getUnreadCount(chat.id));
    final counts = await Future.wait(futures);

    return counts.fold<int>(0, (sum, count) => sum + count);
  }

  /// Gets unread counts for all chats as a map
  /// Processes all chats in parallel for better performance
  /// Excludes hidden chats from the count
  Future<Map<String, int>> getUnreadCountsMap() async {
    final chats = await chatRepository.query().getAll();
    final chatModels = _chatsFromEvents(chats);

    // Filter out hidden chats and process in parallel
    final visibleChats = chatModels.where((chat) => !_isChatHidden(chat.id));

    final futures = visibleChats.map((chat) async {
      final count = await getUnreadCount(chat.id);
      return MapEntry(chat.id, count);
    });

    final entries = await Future.wait(futures);
    return Map.fromEntries(entries);
  }

  /// Watches unread counts for all chats
  /// Returns a stream that emits whenever messages change or read state changes
  /// Uses debouncing to coalesce rapid updates into a single emission
  Stream<Map<String, int>> watchUnreadCounts() {
    final controller = StreamController<Map<String, int>>();
    Timer? debounceTimer;
    bool isRefreshing = false;

    void refreshCounts() async {
      // Cancel any pending debounce
      debounceTimer?.cancel();

      // Debounce: wait 50ms before actually refreshing
      debounceTimer = Timer(const Duration(milliseconds: 50), () async {
        if (controller.isClosed || isRefreshing) return;

        isRefreshing = true;
        try {
          final counts = await getUnreadCountsMap();
          if (!controller.isClosed) {
            controller.add(counts);
          }
        } finally {
          isRefreshing = false;
        }
      });
    }

    final messageSub = messageRepository.query().watch().listen((_) => refreshCounts());
    final readStateSub = _readStateChangedController.stream.listen((_) => refreshCounts());

    controller.onCancel = () {
      debounceTimer?.cancel();
      messageSub.cancel();
      readStateSub.cancel();
    };

    // Initial emit (immediate, no debounce)
    getUnreadCountsMap().then((counts) {
      if (!controller.isClosed) {
        controller.add(counts);
      }
    });

    return controller.stream;
  }

  /// Watches total unread count excluding current open chat
  /// Uses debouncing to coalesce rapid updates into a single emission
  Stream<int> watchTotalUnreadCount() {
    final controller = StreamController<int>();
    Timer? debounceTimer;
    bool isRefreshing = false;

    void refreshCount() async {
      // Cancel any pending debounce
      debounceTimer?.cancel();

      // Debounce: wait 50ms before actually refreshing
      debounceTimer = Timer(const Duration(milliseconds: 50), () async {
        if (controller.isClosed || isRefreshing) return;

        isRefreshing = true;
        try {
          final count = await getTotalUnreadCount(excludeChatId: _currentOpenChatId);
          if (!controller.isClosed) {
            controller.add(count);
          }
        } finally {
          isRefreshing = false;
        }
      });
    }

    final messageSub = messageRepository.query().watch().listen((_) => refreshCount());
    final readStateSub = _readStateChangedController.stream.listen((_) => refreshCount());

    controller.onCancel = () {
      debounceTimer?.cancel();
      messageSub.cancel();
      readStateSub.cancel();
    };

    // Initial emit (immediate, no debounce)
    getTotalUnreadCount(excludeChatId: _currentOpenChatId).then((count) {
      if (!controller.isClosed) {
        controller.add(count);
      }
    });

    return controller.stream;
  }
}
