import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:math';

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
import '../models/counter_log_model.dart';
import '../models/session_counter_model.dart';
import '../repositories/repositories.dart';
import '../services/navigator_service.dart';
import '../services/sync_state_manager.dart';

/// Central orchestrator using WebSocket sync strategy
class RepositoryService {
  static const tag = 'RepositoryService';

  static RepositoryService? _instance;
  factory RepositoryService() => _instance ??= RepositoryService._internal();

  /// For testing only - allows injecting a mock instance
  @visibleForTesting
  static set instance(RepositoryService? testInstance) {
    _instance = testInstance;
  }

  // Test-only constructor for dependency injection
  @visibleForTesting
  factory RepositoryService.test({
    required LocalFirstRepository<UserModel> userRepo,
    required LocalFirstRepository<CounterLogModel> counterLogRepo,
    required LocalFirstRepository<SessionCounterModel> sessionCounterRepo,
    required WebSocketSyncStrategy wsStrategy,
    required PeriodicSyncStrategy periodicStrat,
    http.Client? httpClient,
    LocalFirstStorage? storage,
    NavigatorService? navigator,
  }) {
    final service = RepositoryService._test(
      userRepo: userRepo,
      counterLogRepo: counterLogRepo,
      sessionCounterRepo: sessionCounterRepo,
      wsStrategy: wsStrategy,
      periodicStrat: periodicStrat,
    );
    service._httpClient = httpClient ?? http.Client();
    service._storage = storage;
    service._navigatorService = navigator ?? NavigatorService();
    return service;
  }

  LocalFirstClient? localFirst;
  UserModel? authenticatedUser;
  String _currentNamespace = 'default';
  final _lastUsernameKey = '__last_username__';
  final _sessionIdPrefix = '__session_id__';
  String? _currentSessionId;
  SyncStateManager? _syncStateManager;
  http.Client _httpClient = http.Client();
  LocalFirstStorage? _storage;
  NavigatorService _navigatorService = NavigatorService();

  final LocalFirstRepository<UserModel> userRepository;
  final LocalFirstRepository<CounterLogModel> counterLogRepository;
  final LocalFirstRepository<SessionCounterModel> sessionCounterRepository;
  late final WebSocketSyncStrategy webSocketStrategy;
  late final PeriodicSyncStrategy periodicStrategy;

  RepositoryService._test({
    required LocalFirstRepository<UserModel> userRepo,
    required LocalFirstRepository<CounterLogModel> counterLogRepo,
    required LocalFirstRepository<SessionCounterModel> sessionCounterRepo,
    required WebSocketSyncStrategy wsStrategy,
    required PeriodicSyncStrategy periodicStrat,
  })  : userRepository = userRepo,
        counterLogRepository = counterLogRepo,
        sessionCounterRepository = sessionCounterRepo,
        webSocketStrategy = wsStrategy,
        periodicStrategy = periodicStrat;

  RepositoryService._internal()
      : userRepository = buildUserRepository(),
        counterLogRepository = buildCounterLogRepository(),
        sessionCounterRepository = buildSessionCounterRepository() {
    // Initialize WebSocketSyncStrategy for real-time push notifications
    // Pending queue disabled - let periodic strategy handle offline events
    webSocketStrategy = WebSocketSyncStrategy(
      websocketUrl: websocketUrl,
      reconnectDelay: Duration(milliseconds: 1500),
      heartbeatInterval: Duration(seconds: 15),
      enablePendingQueue: false,
      onBuildSyncFilter: (_) async => null, // Don't pull - only receive pushes
      onSyncCompleted: (_, __) async {}, // No-op - periodic handles state
    );

    // Initialize PeriodicSyncStrategy for consistency and offline sync
    // Uses server sequence to fetch missed events
    periodicStrategy = PeriodicSyncStrategy(
      syncInterval: Duration(seconds: 10),
      repositoryNames: [
        RepositoryNames.user,
        RepositoryNames.counterLog,
        RepositoryNames.sessionCounter,
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
      // No previous sync - request all events
      return null;
    }

    // Request events after last known sequence
    return {'afterSequence': lastSequence};
  }

  /// Fetches events from REST API for periodic sync
  Future<List<JsonMap>> _fetchEvents(String repositoryName) async {
    try {
      final filter = await _buildSyncFilter(repositoryName);
      final uri = filter != null && filter.containsKey('afterSequence')
          ? Uri.parse('$baseHttpUrl/api/events/$repositoryName?seq=${filter['afterSequence']}')
          : Uri.parse('$baseHttpUrl/api/events/$repositoryName');

      final response = await _httpClient.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        dev.log('Failed to fetch events: ${response.statusCode}', name: 'RepositoryService');
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final events = (data['events'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

      return events;
    } catch (e, s) {
      dev.log('Error fetching events', name: 'RepositoryService', error: e, stackTrace: s);
      return [];
    }
  }

  /// Pushes local events to REST API for periodic sync
  Future<bool> _pushEvents(String repositoryName, LocalFirstEvents events) async {
    if (events.isEmpty) return true;

    try {
      final eventList = events.map((e) => e.toJson()).toList();

      final response = await _httpClient.post(
        Uri.parse('$baseHttpUrl/api/events/$repositoryName/batch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'events': eventList}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 201) {
        dev.log('Failed to push events: ${response.statusCode}', name: 'RepositoryService');
        return false;
      }

      return true;
    } catch (e, s) {
      dev.log('Error pushing events', name: 'RepositoryService', error: e, stackTrace: s);
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

  /// Initializes the client/storage and restores last logged user if possible.
  Future<UserModel?> initialize() async {
    final localFirst = this.localFirst ??= LocalFirstClient(
      repositories: [
        userRepository,
        counterLogRepository,
        sessionCounterRepository,
      ],
      localStorage: SqliteLocalFirstStorage(
        databaseName: 'websocket_example.db',
      ),
      keyValueStorage: SharedPreferencesConfigStorage(),
      syncStrategies: [webSocketStrategy, periodicStrategy],
    );

    await localFirst.initialize();

    // Initialize sync state manager after client is ready
    // Pass namespace getter to ensure sequences are isolated per user
    _syncStateManager = SyncStateManager(localFirst, () => _currentNamespace);

    return await restoreLastUser();
  }

  List<UserModel> _usersFromEvents(List<LocalFirstEvent<UserModel>> events) =>
      events.whereType<LocalFirstStateEvent<UserModel>>().map((e) => e.data).toList();

  List<CounterLogModel> _logsFromEvents(
    List<LocalFirstEvent<CounterLogModel>> events,
  ) =>
      events
          .whereType<LocalFirstStateEvent<CounterLogModel>>()
          .map((e) => e.data)
          .toList();

  List<SessionCounterModel> _sessionCountersFromEvents(
    List<LocalFirstEvent<SessionCounterModel>> events,
  ) =>
      events
          .whereType<LocalFirstStateEvent<SessionCounterModel>>()
          .map((e) => e.data)
          .toList();

  /// Fetches a user from the remote server by userId.
  /// Returns UserModel if user exists, null if not (404), throws on connection error.
  Future<UserModel?> _fetchRemoteUser(String userId) async {
    try {
      // The API endpoint is GET /api/events/{repository}/byDataId/{dataId}
      // For user repository, we query by dataId which is the userId
      final response = await _httpClient
          .get(Uri.parse('$baseHttpUrl/api/events/user/byDataId/$userId'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 404) {
        // User doesn't exist on server
        return null;
      }

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch user: ${response.statusCode}');
      }

      // Extract user data from response
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final eventData = data['event'] as Map<String, dynamic>;
      final userData = eventData['data'] as Map<String, dynamic>;

      return UserModel.fromJson(userData);
    } catch (e) {
      throw Exception('Failed to fetch remote user: $e');
    }
  }

  /// Signs in a user and starts all sync strategies.
  ///
  /// This method implements a server-first approach:
  /// 1. Create local UserModel (generates correct userId)
  /// 2. Fetch user from server via HTTP GET (fails if no connection)
  /// 3. If exists remotely: discard local model, use remote data
  /// 4. If doesn't exist: use local model and mark for sync
  /// 5. Start all sync strategies (handles data sync independently per namespace)
  Future<void> signIn({required String username}) async {
    localFirst?.stopAllStrategies();

    // Create local UserModel to generate userId using same ID generation logic
    final localUser = UserModel(username: username, avatarUrl: null);
    final userId = localUser.id;

    // Switch to user's namespace database
    await _switchUserDatabase(userId);

    // Fetch user from server via HTTP GET
    try {
      final remoteUser = await _fetchRemoteUser(userId);

      if (remoteUser != null) {
        // User exists on server - use remote data temporarily
        // WebSocket sync will populate local database with server data
        // This ensures data comes from sync process, not HTTP GET
        authenticatedUser = remoteUser;

        // DO NOT upsert remote user here - let WebSocket sync handle it
        // This prevents duplicate events and ensures sync process controls data flow
      } else {
        // User doesn't exist on server - use local model
        authenticatedUser = localUser;

        // Persist new user to local database and mark for sync to server
        await userRepository.upsert(localUser, needSync: true);
      }
    } catch (e) {
      throw Exception('Failed to sign in: $e');
    }

    // Prepare session and persist login state
    await _prepareSession(authenticatedUser!);
    await _persistLastUsername(username);

    // Start all sync strategies - handles synchronization independently per namespace
    await localFirst?.startAllStrategies();

    // Navigate to home screen
    _navigatorService.navigateToHome();
  }

  /// Clears auth/session state and navigates back to sign-in.
  Future<void> signOut() async {
    localFirst?.stopAllStrategies();
    authenticatedUser = null;
    _currentSessionId = null;
    await _switchUserDatabase('');
    await _setGlobalString(_lastUsernameKey, '');
    _navigatorService.navigateToSignIn();
  }

  /// Rehydrates a user by username (used during app restart).
  Future<UserModel?> restoreUser(String username) async {
    final normalizedId = UserModel(username: username, avatarUrl: null).id;
    await _switchUserDatabase(normalizedId);
    final results = await userRepository
        .query()
        .where(userRepository.idFieldName, isEqualTo: normalizedId)
        .getAll();
    if (results.isEmpty) return null;

    final user = (results.first as LocalFirstStateEvent<UserModel>).data;
    authenticatedUser = user;
    await _prepareSession(user);
    await localFirst?.startAllStrategies();
    return user;
  }

  /// Rehydrates the most recently logged-in user, if any.
  Future<UserModel?> restoreLastUser() async {
    final username = await _getGlobalString(_lastUsernameKey);
    if (username == null || username.isEmpty) return null;
    return restoreUser(username);
  }

  Future<void> _persistLastUsername(String username) =>
      _setGlobalString(_lastUsernameKey, username);

  Future<String?> _getGlobalString(String key) async {
    final client = localFirst;
    if (client == null) return null;
    return _withGlobalString(() => client.getConfigValue(key));
  }

  Future<void> _setGlobalString(String key, String value) async {
    final client = localFirst;
    if (client == null) return;
    await _withGlobalString(() => client.setConfigValue(key, value));
  }

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

  String _sessionMetaKey(String username) {
    final sanitized = _sanitizeNamespace(username);
    return '$_sessionIdPrefix$sanitized';
  }

  String _generateSessionId(String username) {
    final random = Random();
    final randomBits = random.nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    return 'sess_${_sanitizeNamespace(username)}_${timestamp}_$randomBits';
  }

  Future<String> _getOrCreateSessionId(String username) async {
    final existing = await _getGlobalString(_sessionMetaKey(username));
    if (existing is String && existing.isNotEmpty) return existing;
    final generated = _generateSessionId(username);
    await _setGlobalString(_sessionMetaKey(username), generated);
    return generated;
  }

  Future<void> _prepareSession(UserModel user) async {
    final sessionId = await _getOrCreateSessionId(user.username);
    _currentSessionId = sessionId;
    await _ensureSessionCounterForSession(
      username: user.username,
      sessionId: sessionId,
    );
  }

  Future<SessionCounterModel> _ensureSessionCounterForSession({
    required String username,
    required String sessionId,
  }) async {
    final results = await sessionCounterRepository
        .query()
        .where(sessionCounterRepository.idFieldName, isEqualTo: sessionId)
        .limitTo(1)
        .getAll();
    if (results.isNotEmpty) {
      return (results.first as LocalFirstStateEvent<SessionCounterModel>).data;
    }
    final counter = SessionCounterModel(
      sessionId: sessionId,
      username: username,
      count: 0,
    );
    await sessionCounterRepository.upsert(counter, needSync: true);
    return counter;
  }

  Future<List<UserModel>> getUsers() async =>
      _usersFromEvents(await userRepository.query().getAll());

  Stream<List<CounterLogModel>> watchLogs({int limit = 5}) => counterLogRepository
      .query()
      .orderBy(CommonFields.createdAt, descending: true)
      .limitTo(min(limit, 5))
      .watch()
      .map(_logsFromEvents);

  Stream<int> watchCounter() => sessionCounterRepository
      .query()
      .watch()
      .map(_sessionCountersFromEvents)
      .map((sessions) => sessions.fold<int>(0, (sum, counter) => sum + counter.count));

  Stream<List<CounterLogModel>> watchRecentLogs({int limit = 5}) =>
      watchLogs(limit: min(limit, 5));

  Stream<List<UserModel>> watchUsers() =>
      userRepository.query().orderBy(CommonFields.username).watch().map(_usersFromEvents);

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

  void incrementCounter() => _createLogRegistry(1);
  void decrementCounter() => _createLogRegistry(-1);

  Future<void> _createLogRegistry(int amount) async {
    final username = authenticatedUser?.username;
    if (username == null) throw Exception('User not authenticated');

    final sessionId = _currentSessionId;
    if (sessionId == null) throw Exception('Session not initialized');

    final sessionCounter = await _ensureSessionCounterForSession(
      username: username,
      sessionId: sessionId,
    );
    final updatedCounter = sessionCounter.copyWith(
      count: sessionCounter.count + amount,
      updatedAt: DateTime.now().toUtc(),
    );

    final log = CounterLogModel(
      username: username,
      increment: amount,
      sessionId: sessionId,
    );

    await Future.wait([
      counterLogRepository.upsert(log, needSync: true),
      sessionCounterRepository.upsert(updatedCounter, needSync: true),
    ]);
  }

  Future<void> _switchUserDatabase(String username) async {
    final db = localFirst;
    if (db == null) return;

    final namespace = _sanitizeNamespace(username);
    if (_currentNamespace == namespace) return;
    _currentNamespace = namespace;

    await db.localStorage.useNamespace(namespace);
  }

  String _sanitizeNamespace(String username) {
    if (username.isEmpty) return 'default';
    final sanitized = username.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9_-]'),
          '_',
        );
    return 'user__$sanitized';
  }
}

/// Test helper class to expose private methods for unit testing
@visibleForTesting
class TestRepositoryServiceHelper {
  final RepositoryService service;

  TestRepositoryServiceHelper(this.service);

  String sanitizeNamespace(String username) => service._sanitizeNamespace(username);

  String generateSessionId(String username) => service._generateSessionId(username);

  String sessionMetaKey(String username) => service._sessionMetaKey(username);

  List<UserModel> usersFromEvents(List<LocalFirstEvent<UserModel>> events) =>
      service._usersFromEvents(events);

  List<CounterLogModel> logsFromEvents(List<LocalFirstEvent<CounterLogModel>> events) =>
      service._logsFromEvents(events);

  List<SessionCounterModel> sessionCountersFromEvents(
    List<LocalFirstEvent<SessionCounterModel>> events,
  ) =>
      service._sessionCountersFromEvents(events);

  Future<JsonMap<dynamic>?> buildSyncFilter(String repositoryName) =>
      service._buildSyncFilter(repositoryName);

  Future<List<JsonMap>> fetchEvents(String repositoryName) =>
      service._fetchEvents(repositoryName);

  Future<bool> pushEvents(String repositoryName, LocalFirstEvents events) =>
      service._pushEvents(repositoryName, events);

  Future<void> onSyncCompleted(String repositoryName, List<JsonMap<dynamic>> events) =>
      service._onSyncCompleted(repositoryName, events);

  Future<UserModel?> fetchRemoteUser(String userId) =>
      service._fetchRemoteUser(userId);

  Future<void> prepareSession(UserModel user) =>
      service._prepareSession(user);

  Future<SessionCounterModel> ensureSessionCounterForSession({
    required String username,
    required String sessionId,
  }) =>
      service._ensureSessionCounterForSession(
        username: username,
        sessionId: sessionId,
      );

  Future<String> getOrCreateSessionId(String username) =>
      service._getOrCreateSessionId(username);

  Future<void> persistLastUsername(String username) =>
      service._persistLastUsername(username);

  Future<String?> getGlobalString(String key) =>
      service._getGlobalString(key);

  Future<void> setGlobalString(String key, String value) =>
      service._setGlobalString(key, value);

  Future<T> withGlobalString<T>(Future<T> Function() action) =>
      service._withGlobalString(action);

  Future<void> switchUserDatabase(String username) =>
      service._switchUserDatabase(username);

  Future<void> createLogRegistry(int amount) =>
      service._createLogRegistry(amount);

  // Getters for accessing private fields
  String? get currentSessionId => service._currentSessionId;

  SyncStateManager? get syncStateManager => service._syncStateManager;

  String get currentNamespace => service._currentNamespace;
}
