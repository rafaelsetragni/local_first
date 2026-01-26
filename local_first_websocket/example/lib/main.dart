import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_websocket/local_first_websocket.dart';
import 'package:local_first_sqlite_storage/local_first_sqlite_storage.dart';
import 'package:local_first_shared_preferences/local_first_shared_preferences.dart';

// WebSocket server URL
// Make sure to start the server first (from the monorepo root):
// melos websocket:server
const websocketUrl = 'ws://localhost:8080/sync';

/// Centralized string keys to avoid magic field names.
class RepositoryNames {
  static const user = 'user';
  static const counterLog = 'counter_log';
  static const sessionCounter = 'session_counter';
}

class CommonFields {
  static const id = 'id';
  static const username = 'username';
  static const createdAt = 'created_at';
  static const updatedAt = 'updated_at';
}

class UserFields {
  static const avatarUrl = 'avatar_url';
}

class CounterLogFields {
  static const sessionId = 'session_id';
  static const increment = 'increment';
}

/// Field keys used by session counter events/records.
class SessionCounterFields {
  static const sessionId = 'session_id';
  static const count = 'count';
}

/// Entry point that initializes the local-first stack then opens the right page.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  RepositoryService().initialize().then((signedUser) {
    runApp(
      MyApp(home: signedUser != null ? const MyHomePage() : const SignInPage()),
    );
  });
}

/// Root widget configuring theme and navigation key.
class MyApp extends StatelessWidget {
  final Widget home;

  const MyApp({super.key, required this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebSocket Real-Time Counter',
      navigatorKey: NavigatorService().navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: home,
    );
  }
}

/// Simple sign-in form to capture the username.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  bool _isSigningIn = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  /// Handles sign-in by persisting the user and navigating to home.
  Future<void> _signIn(BuildContext context) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final errorColor = Theme.of(context).colorScheme.error;
    final scafold = ScaffoldMessenger.of(context);
    final username = _usernameController.text;

    setState(() => _isSigningIn = true);
    try {
      await RepositoryService().signIn(username: username);
    } catch (e) {
      scafold.showSnackBar(
        SnackBar(
          backgroundColor: errorColor,
          content: Text('No connection to the server. Error: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSigningIn = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'WebSocket Real-Time Counter',
                      style: TextTheme.of(context).headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Sign In',
                      style: TextTheme.of(context).labelLarge?.copyWith(
                            color: ColorScheme.of(context).primary,
                          ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                      ),
                      onFieldSubmitted: (_) => _signIn(context),
                      validator: (value) => (value == null || value.trim().isEmpty)
                          ? 'Please enter a username.'
                          : null,
                    ),
                    SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isSigningIn ? null : () => _signIn(context),
                      child: _isSigningIn
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign In'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Main screen showing counter, users, logs, and avatar editing.
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late final Stream<int> _counterStream;
  late final Stream<List<UserModel>> _usersStream;
  late final Stream<List<CounterLogModel>> _recentLogsStream;
  final GlobalKey<AnimatedListState> _logsListKey = GlobalKey<AnimatedListState>();
  late final StreamSubscription<List<CounterLogModel>> _logsSubscription;
  final List<CounterLogModel> _logs = [];
  JsonMap<String?> _avatarMap = {};

  @override
  void initState() {
    super.initState();
    final service = RepositoryService();
    _usersStream = service.watchUsers();
    _counterStream = service.watchCounter();
    _recentLogsStream = service.watchRecentLogs(limit: 5);
    _logsSubscription = _recentLogsStream.listen(_onLogsUpdate);
  }

  /// Opens dialog to update the current user's avatar URL.
  Future<void> _onAvatarTap(BuildContext context, String currentAvatar) async {
    final url = await _promptAvatarDialog(context, currentAvatar);
    if (url == null) return;
    await RepositoryService().updateAvatarUrl(url);
  }

  @override
  void dispose() {
    _logsSubscription.cancel();
    super.dispose();
  }

  /// Reconciles AnimatedList items with the latest logs to animate inserts/removes.
  void _onLogsUpdate(List<CounterLogModel> newLogs) {
    final listState = _logsListKey.currentState;

    if (listState == null) {
      _logs
        ..clear()
        ..addAll(newLogs);
      if (mounted) setState(() {});
      return;
    }

    // Remove items no longer present (fade out).
    for (int i = _logs.length - 1; i >= 0; i--) {
      final log = _logs[i];
      final stillPresent = newLogs.any((l) => l.id == log.id);
      if (!stillPresent) {
        final removed = _logs.removeAt(i);
        listState.removeItem(
          i,
          (context, animation) =>
              _buildAnimatedLogTile(removed, animation, appearing: false),
          duration: const Duration(milliseconds: 250),
        );
      }
    }

    // Insert new items and adjust order to match new list.
    for (int targetIndex = 0; targetIndex < newLogs.length; targetIndex++) {
      final incoming = newLogs[targetIndex];
      final currentIndex = _logs.indexWhere((l) => l.id == incoming.id);

      if (currentIndex == -1) {
        _logs.insert(targetIndex, incoming);
        listState.insertItem(
          targetIndex,
          duration: const Duration(milliseconds: 250),
        );
      } else if (currentIndex != targetIndex) {
        final item = _logs.removeAt(currentIndex);
        _logs.insert(targetIndex, item);
      }
    }

    // Trim extras if new list is shorter.
    while (_logs.length > newLogs.length) {
      final lastIndex = _logs.length - 1;
      final removed = _logs.removeAt(lastIndex);
      listState.removeItem(
        lastIndex,
        (context, animation) =>
            _buildAnimatedLogTile(removed, animation, appearing: false),
        duration: const Duration(milliseconds: 250),
      );
    }
    if (mounted) setState(() {});
  }

  /// Builds a single log tile with fade/slide animations for list changes.
  Widget _buildAnimatedLogTile(
    CounterLogModel log,
    Animation<double> animation, {
    required bool appearing,
  }) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    final avatar = _avatarMap[log.username] ?? '';
    return FadeTransition(
      opacity: appearing ? curved : animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: appearing ? const Offset(0.15, 0) : Offset.zero,
          end: appearing ? Offset.zero : const Offset(-0.05, 0),
        ).animate(curved),
        child: CounterLogTile(
          key: ValueKey('tile-${log.id}'),
          log: log,
          avatarUrl: avatar,
        ),
      ),
    );
  }

  /// Prompts the user to type a new avatar URL and returns it.
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
                  onPressed: () => NavigatorService().pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => NavigatorService().pop(previewUrl),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = RepositoryService().authenticatedUser;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: _buildSignOutAppBar(),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: _buildAvatarAndGlobalCounter(user)),
            Column(
              children: [
                _buildUserList(context),
                _buildRecentActivities(context),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            onPressed: RepositoryService().incrementCounter,
            tooltip: 'Increment',
            heroTag: 'increment_button',
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            onPressed: RepositoryService().decrementCounter,
            tooltip: 'Decrement',
            heroTag: 'decrement_button',
            child: const Icon(Icons.remove),
          ),
        ],
      ),
    );
  }

  /// Renders connection badge, avatar, greeting, and aggregate counters.
  StreamBuilder<List<UserModel>> _buildAvatarAndGlobalCounter(UserModel user) {
    return StreamBuilder(
      stream: _usersStream,
      builder: (context, snapshot) {
        final users = snapshot.data ?? const [];
        final avatarMap = {for (final u in users) u.username: u.avatarUrl};
        final currentUserAvatar = avatarMap[user.username] ?? user.avatarUrl ?? '';

        return StreamBuilder<bool>(
          stream: RepositoryService().connectionState,
          initialData: RepositoryService().isConnected,
          builder: (context, connectionSnapshot) {
            final isConnected = connectionSnapshot.data ?? false;
            return Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isConnected
                            ? Colors.green.shade100
                            : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isConnected ? 'Connected' : 'Disconnected',
                        style: TextStyle(
                          color: isConnected
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _onAvatarTap(context, currentUserAvatar),
                      child: AvatarPreview(
                        avatarUrl: currentUserAvatar,
                        showEditIndicator: true,
                        connectionStatus: isConnected,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Hello, ${user.username}!',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text('Global counter updated by all users:'),
                    StreamBuilder<int>(
                      stream: _counterStream,
                      builder: (context, counterSnapshot) {
                        final total = counterSnapshot.data ?? 0;
                        if (counterSnapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(),
                          );
                        }
                        return Text(
                          '$total',
                          style: Theme.of(context).textTheme.headlineLarge,
                        );
                      },
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// App bar with logout action.
  AppBar _buildSignOutAppBar() {
    return AppBar(
      actions: [
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Logout',
          onPressed: RepositoryService().signOut,
        ),
      ],
    );
  }

  /// Shows the animated list of recent counter logs.
  Column _buildRecentActivities(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Text(
            'Recent activities:',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        StreamBuilder(
          stream: _usersStream,
          builder: (context, usersSnapshot) {
            final avatarMap = {
              for (final u in usersSnapshot.data ?? const []) u.username: u.avatarUrl,
            };
            _avatarMap = JsonMap<String?>.from(avatarMap);
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.35,
              child: Container(
                color: ColorScheme.of(context).surfaceContainerLow,
                padding: const EdgeInsets.all(24.0),
                child: AnimatedList(
                  key: _logsListKey,
                  initialItemCount: _logs.length,
                  itemBuilder: (context, index, animation) {
                    if (index >= _logs.length) return const SizedBox.shrink();
                    final log = _logs[index];
                    return _buildAnimatedLogTile(
                      log,
                      animation,
                      appearing: true,
                    );
                  },
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// Displays all known users horizontally with their avatars.
  SizedBox _buildUserList(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.15,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
        child: StreamBuilder(
          stream: _usersStream,
          builder: (context, usersSnapshot) {
            final users = usersSnapshot.data ?? const [];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Users:', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Expanded(
                  child: usersSnapshot.connectionState == ConnectionState.waiting
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: users.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final item = users[index];
                            final avatar = item.avatarUrl ?? '';
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AvatarPreview(
                                  radius: 22,
                                  avatarUrl: avatar,
                                  showEditIndicator: false,
                                ),
                                const SizedBox(height: 6),
                                Text(item.username),
                              ],
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Visualizes a single counter log entry with avatar and timestamp.
class CounterLogTile extends StatelessWidget {
  final CounterLogModel log;
  final String avatarUrl;
  const CounterLogTile({super.key, required this.log, required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarPreview(radius: 14, avatarUrl: avatarUrl),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  log.toString(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  log.toFormattedDate(),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Displays a user avatar with an optional edit badge overlay.
class AvatarPreview extends StatelessWidget {
  final String avatarUrl;
  final double radius;
  final bool showEditIndicator;
  final bool? connectionStatus;
  const AvatarPreview({
    super.key,
    required this.avatarUrl,
    this.showEditIndicator = false,
    this.radius = 50,
    this.connectionStatus,
  });

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl.isNotEmpty;
    final status = connectionStatus;
    final indicatorColor = status == null
        ? null
        : (status ? Colors.green : Colors.red);
    final ringDiameter = radius * 2 + 8; // 4px gap each side
    return SizedBox(
      width: ringDiameter,
      height: ringDiameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (indicatorColor != null)
            IgnorePointer(
              child: Container(
                width: ringDiameter,
                height: ringDiameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: indicatorColor, width: 4),
                ),
              ),
            ),
          CircleAvatar(
            radius: radius - (indicatorColor != null ? 4 : 0),
            backgroundColor: ColorScheme.of(context).surfaceContainerHighest,
            backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
            child: hasAvatar ? null : Icon(Icons.person, size: radius),
          ),
          if (showEditIndicator)
            Positioned(
              bottom: 0,
              right: 0,
              child: PhysicalModel(
                color: Colors.transparent,
                elevation: 4,
                shadowColor: ColorScheme.of(context).shadow,
                shape: BoxShape.circle,
                child: CircleAvatar(
                  radius: radius / 2.5,
                  backgroundColor: ColorScheme.of(context).primaryFixed,
                  child: Icon(
                    Icons.edit,
                    size: radius / 2.5,
                    color: ColorScheme.of(context).onPrimaryFixed,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Centralized navigation helper
class NavigatorService {
  NavigatorService._internal();
  static NavigatorService? _instance;
  factory NavigatorService() => _instance ??= NavigatorService._internal();

  final navigatorKey = GlobalKey<NavigatorState>();

  Future<T?> push<T extends Object?>(Widget page) async =>
      navigatorKey.currentState?.push<T>(MaterialPageRoute(builder: (_) => page));

  Future<T?> pushReplacement<T extends Object?, TO extends Object?>(
    Widget page, {
    TO? result,
  }) async =>
      navigatorKey.currentState?.pushReplacement<T, TO>(
        MaterialPageRoute(builder: (_) => page),
        result: result,
      );

  void pop<T extends Object?>([T? result]) =>
      navigatorKey.currentState?.pop<T>(result);

  Future<bool> maybePop<T extends Object?>([T? result]) =>
      navigatorKey.currentState?.maybePop<T>(result) ?? Future.value(false);

  void navigateToHome() => pushReplacement(const MyHomePage());
  void navigateToSignIn() => pushReplacement(const SignInPage());
}

/// Manages sync state using server sequences per repository
///
/// IMPORTANT: Sequences are stored per namespace to ensure proper isolation
/// between different users. Each user has their own set of lastSequence values.
class SyncStateManager {
  final LocalFirstClient client;
  final String Function() getNamespace;
  final _sequenceKeyPrefix = '__last_sequence__';

  SyncStateManager(this.client, this.getNamespace);

  /// Builds a namespace-aware key for storing sequence numbers
  /// Format: `{namespace}__last_sequence__{repositoryName}`
  String _buildSequenceKey(String repositoryName) {
    final namespace = getNamespace();
    return '${namespace}_$_sequenceKeyPrefix$repositoryName';
  }

  /// Gets the last synced sequence for a repository in the current namespace
  Future<int?> getLastSequence(String repositoryName) async {
    final key = _buildSequenceKey(repositoryName);
    final value = await client.getConfigValue(key);
    return value != null ? int.tryParse(value) : null;
  }

  /// Saves the last synced sequence for a repository in the current namespace
  Future<void> saveLastSequence(String repositoryName, int sequence) async {
    final key = _buildSequenceKey(repositoryName);
    await client.setConfigValue(key, sequence.toString());
  }

  /// Extracts the maximum server sequence from a list of events
  int? extractMaxSequence(List<JsonMap<dynamic>> events) {
    if (events.isEmpty) return null;

    int? maxSequence;
    for (final event in events) {
      final seq = event['serverSequence'];
      if (seq is int) {
        maxSequence = maxSequence == null ? seq : (seq > maxSequence ? seq : maxSequence);
      }
    }
    return maxSequence;
  }
}

/// Central orchestrator using WebSocket sync strategy
class RepositoryService {
  static const tag = 'RepositoryService';

  static RepositoryService? _instance;
  factory RepositoryService() => _instance ??= RepositoryService._internal();

  LocalFirstClient? localFirst;
  UserModel? authenticatedUser;
  String _currentNamespace = 'default';
  final _lastUsernameKey = '__last_username__';
  final _sessionIdPrefix = '__session_id__';
  String? _currentSessionId;
  SyncStateManager? _syncStateManager;

  final LocalFirstRepository<UserModel> userRepository;
  final LocalFirstRepository<CounterLogModel> counterLogRepository;
  final LocalFirstRepository<SessionCounterModel> sessionCounterRepository;
  late final WebSocketSyncStrategy syncStrategy;

  RepositoryService._internal()
      : userRepository = _buildUserRepository(),
        counterLogRepository = _buildCounterLogRepository(),
        sessionCounterRepository = _buildSessionCounterRepository() {
    // Initialize WebSocketSyncStrategy with callbacks
    syncStrategy = WebSocketSyncStrategy(
      websocketUrl: websocketUrl,
      reconnectDelay: Duration(seconds: 3),
      heartbeatInterval: Duration(seconds: 30),
      onBuildSyncFilter: _buildSyncFilter,
      onSyncCompleted: _onSyncCompleted,
    );
  }

  String get namespace => _currentNamespace;
  Stream<bool> get connectionState => syncStrategy.connectionChanges;
  bool get isConnected => syncStrategy.latestConnectionState ?? false;

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
      syncStrategies: [syncStrategy],
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

  /// Signs in a user and starts WebSocket sync.
  Future<void> signIn({required String username}) async {
    syncStrategy.stop();
    final localUser = UserModel(username: username, avatarUrl: null);
    await _switchUserDatabase(localUser.id);

    final existing = await userRepository
        .query()
        .where(userRepository.idFieldName, isEqualTo: localUser.id)
        .getAll();

    final UserModel user;
    if (existing.isNotEmpty) {
      final firstEvent = existing.first as LocalFirstStateEvent<UserModel>;
      user = firstEvent.data;
      authenticatedUser = user;
    } else {
      user = localUser;
      authenticatedUser = user;
      await userRepository.upsert(localUser, needSync: true);
    }

    await _prepareSession(user);
    await _persistLastUsername(username);

    // Start WebSocket connection
    await syncStrategy.start();
    NavigatorService().navigateToHome();
  }

  /// Clears auth/session state and navigates back to sign-in.
  Future<void> signOut() async {
    syncStrategy.stop();
    authenticatedUser = null;
    _currentSessionId = null;
    await _switchUserDatabase('');
    await _setGlobalString(_lastUsernameKey, '');
    NavigatorService().navigateToSignIn();
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
    await syncStrategy.start();
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

/// Domain models (same as in the original example)
class UserModel {
  final String id;
  final String username;
  final String? avatarUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserModel._({
    required this.id,
    required this.username,
    required this.avatarUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel({
    String? id,
    required String username,
    required String? avatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now().toUtc();
    final created = createdAt ?? now;
    final updated = updatedAt ?? created;
    final normalizedId = (id ?? username).trim().toLowerCase();
    return UserModel._(
      id: normalizedId,
      username: username,
      avatarUrl: avatarUrl,
      createdAt: created,
      updatedAt: updated,
    );
  }

  JsonMap toJson() {
    return {
      CommonFields.id: id,
      CommonFields.username: username,
      UserFields.avatarUrl: avatarUrl,
      CommonFields.createdAt: createdAt.toUtc().toIso8601String(),
      CommonFields.updatedAt: updatedAt.toUtc().toIso8601String(),
    };
  }

  factory UserModel.fromJson(JsonMap json) {
    final username = json[CommonFields.username] ?? json[CommonFields.id];
    final created = DateTime.parse(json[CommonFields.createdAt]).toUtc();
    final updated = json[CommonFields.updatedAt] != null
        ? DateTime.parse(json[CommonFields.updatedAt]).toUtc()
        : created;
    return UserModel(
      id: (json[CommonFields.id] ?? username).toString().trim().toLowerCase(),
      username: username,
      avatarUrl: json[UserFields.avatarUrl],
      createdAt: created,
      updatedAt: updated,
    );
  }

  static UserModel resolveConflict(UserModel local, UserModel remote) {
    // Always prefer remote if timestamps are equal
    if (local.updatedAt == remote.updatedAt) return remote;

    // Determine which version is newer based on updatedAt
    final preferred = local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
    final fallback = identical(preferred, local) ? remote : local;

    // Merge avatar: prefer non-null value
    final avatar = preferred.avatarUrl ?? fallback.avatarUrl;

    // If merged avatar equals preferred's avatar, return preferred as-is
    // This avoids creating unnecessary new objects that trigger sync
    if (avatar == preferred.avatarUrl) {
      return preferred;
    }

    // Only create new object if merge actually changed something
    return UserModel(
      id: preferred.id,
      username: preferred.username,
      avatarUrl: avatar,
      createdAt: preferred.createdAt,
      updatedAt: preferred.updatedAt,
    );
  }
}

class SessionCounterModel {
  final String id;
  final String username;
  final String sessionId;
  final int count;
  final DateTime createdAt;
  final DateTime updatedAt;

  SessionCounterModel._({
    required this.id,
    required this.username,
    required this.sessionId,
    required this.count,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SessionCounterModel({
    String? id,
    required String username,
    required String sessionId,
    int count = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now().toUtc();
    final created = createdAt ?? now;
    final updated = updatedAt ?? created;
    final normalizedId = id ?? sessionId;
    return SessionCounterModel._(
      id: normalizedId,
      username: username,
      sessionId: sessionId,
      count: count,
      createdAt: created,
      updatedAt: updated,
    );
  }

  SessionCounterModel copyWith({
    String? id,
    String? username,
    String? sessionId,
    int? count,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SessionCounterModel(
      id: id ?? this.id,
      username: username ?? this.username,
      sessionId: sessionId ?? this.sessionId,
      count: count ?? this.count,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  JsonMap toJson() {
    return {
      CommonFields.id: id,
      CommonFields.username: username,
      SessionCounterFields.sessionId: sessionId,
      SessionCounterFields.count: count,
      CommonFields.createdAt: createdAt.toUtc().toIso8601String(),
      CommonFields.updatedAt: updatedAt.toUtc().toIso8601String(),
    };
  }

  factory SessionCounterModel.fromJson(JsonMap json) {
    final created = DateTime.parse(json[CommonFields.createdAt]).toUtc();
    final updated = json[CommonFields.updatedAt] != null
        ? DateTime.parse(json[CommonFields.updatedAt]).toUtc()
        : created;
    final sessionId = json[SessionCounterFields.sessionId] ?? json[CommonFields.id];
    return SessionCounterModel(
      id: json[CommonFields.id] ?? sessionId,
      username: json[CommonFields.username],
      sessionId: sessionId,
      count: json[SessionCounterFields.count] ?? 0,
      createdAt: created,
      updatedAt: updated,
    );
  }

  static SessionCounterModel resolveConflict(
    SessionCounterModel local,
    SessionCounterModel remote,
  ) =>
      local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
}

class CounterLogModel {
  final String id;
  final String username;
  final String? sessionId;
  final int increment;
  final DateTime createdAt;
  final DateTime updatedAt;

  CounterLogModel._({
    required this.id,
    required this.username,
    required this.sessionId,
    required this.increment,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CounterLogModel({
    String? id,
    required String username,
    required String? sessionId,
    required int increment,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now().toUtc();
    final created = createdAt ?? now;
    final updated = updatedAt ?? created;
    return CounterLogModel._(
      id: id ?? '${username}_${now.millisecondsSinceEpoch}',
      username: username,
      sessionId: sessionId,
      increment: increment,
      createdAt: created,
      updatedAt: updated,
    );
  }

  JsonMap toJson() {
    return {
      CommonFields.id: id,
      CommonFields.username: username,
      CounterLogFields.sessionId: sessionId,
      CounterLogFields.increment: increment,
      CommonFields.createdAt: createdAt.toUtc().toIso8601String(),
      CommonFields.updatedAt: updatedAt.toUtc().toIso8601String(),
    };
  }

  factory CounterLogModel.fromJson(JsonMap json) {
    final created = DateTime.parse(json[CommonFields.createdAt]).toUtc();
    final updated = json[CommonFields.updatedAt] != null
        ? DateTime.parse(json[CommonFields.updatedAt]).toUtc()
        : created;
    return CounterLogModel(
      id: json[CommonFields.id],
      username: json[CommonFields.username],
      sessionId: json[CounterLogFields.sessionId],
      increment: json[CounterLogFields.increment],
      createdAt: created,
      updatedAt: updated,
    );
  }

  static CounterLogModel resolveConflict(
    CounterLogModel local,
    CounterLogModel remote,
  ) =>
      local.updatedAt.isAfter(remote.updatedAt) ? local : remote;

  @override
  String toString() {
    final change = increment.abs();
    final verb = increment >= 0 ? 'Increased' : 'Decreased';
    return '$verb by $change by $username';
  }

  String toFormattedDate() => () {
        final local = createdAt.toLocal();
        String two(int v) => v.toString().padLeft(2, '0');
        String three(int v) => v.toString().padLeft(3, '0');
        return '${two(local.day)}/${two(local.month)}/${local.year} '
            '${two(local.hour)}:${two(local.minute)}:${two(local.second)}.${three(local.millisecond)}';
      }();
}

LocalFirstRepository<UserModel> _buildUserRepository() {
  return LocalFirstRepository.create(
    name: RepositoryNames.user,
    getId: (user) => user.id,
    toJson: (user) => user.toJson(),
    fromJson: (json) => UserModel.fromJson(json),
    onConflictEvent: (local, remote) {
      final winner = UserModel.resolveConflict(local.data, remote.data);
      final source = identical(winner, local.data) ? local : remote;
      return source.updateEventState(
        syncStatus: SyncStatus.ok,
        syncOperation: source.syncOperation,
      );
    },
  );
}

LocalFirstRepository<CounterLogModel> _buildCounterLogRepository() {
  return LocalFirstRepository.create(
    name: RepositoryNames.counterLog,
    getId: (log) => log.id,
    toJson: (log) => log.toJson(),
    fromJson: (json) => CounterLogModel.fromJson(json),
    onConflictEvent: (local, remote) {
      final winner = CounterLogModel.resolveConflict(local.data, remote.data);
      final source = identical(winner, local.data) ? local : remote;
      return source.updateEventState(
        syncStatus: SyncStatus.ok,
        syncOperation: source.syncOperation,
      );
    },
  );
}

LocalFirstRepository<SessionCounterModel> _buildSessionCounterRepository() {
  return LocalFirstRepository.create(
    name: RepositoryNames.sessionCounter,
    getId: (session) => session.id,
    toJson: (session) => session.toJson(),
    fromJson: (json) => SessionCounterModel.fromJson(json),
    onConflictEvent: (local, remote) {
      final winner = SessionCounterModel.resolveConflict(
        local.data,
        remote.data,
      );
      final source = identical(winner, local.data) ? local : remote;
      return source.updateEventState(
        syncStatus: SyncStatus.ok,
        syncOperation: source.syncOperation,
      );
    },
  );
}
