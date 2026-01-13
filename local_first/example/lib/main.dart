import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_hive_storage/local_first_hive_storage.dart';
import 'package:mongo_dart/mongo_dart.dart' hide State, Center;

typedef JsonMap<T> = Map<String, T>;

// To use this example, first you need to start a MongoDB service, and
// you can do it easily creating an container instance using Docker.
// First, install docker desktop on your machine, then copy and
// paste the command bellow at your terminal:
//
// docker run -d --name mongo_local -p 27017:27017 \
//   -e MONGO_INITDB_ROOT_USERNAME=admin \
//   -e MONGO_INITDB_ROOT_PASSWORD=admin mongo:7
//
// You can check the service status using the command bellow:
//
// docker stats mongo_local
//
// The URI below authenticates against the admin database and targets
// the "remote_counter_db" database for reads/writes.
const mongoConnectionString =
    'mongodb://admin:admin@127.0.0.1:27017/remote_counter_db?authSource=admin';

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
      title: 'Offline Counter',
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

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final username = _usernameController.text;
    await RepositoryService().signIn(username: username);
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
                      'Offline Counter',
                      style: TextTheme.of(context).headlineMedium,
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
                      onFieldSubmitted: (_) => _signIn(),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Please enter a username.'
                          : null,
                    ),
                    SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _signIn,
                      child: const Text('Sign In'),
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
  late final Stream<bool> _connectionStream;
  final GlobalKey<AnimatedListState> _logsListKey =
      GlobalKey<AnimatedListState>();
  late final StreamSubscription<List<CounterLogModel>> _logsSubscription;
  final List<CounterLogModel> _logs = [];
  Map<String, String?> _avatarMap = {};

  @override
  void initState() {
    super.initState();
    final service = RepositoryService();
    _usersStream = service.watchUsers();
    _counterStream = service.watchCounter();
    _recentLogsStream = service.watchRecentLogs(limit: 5);
    _connectionStream = service.connectionState.stream;
    _logsSubscription = _recentLogsStream.listen(_onLogsUpdate);
  }

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

  StreamBuilder<List<UserModel>> _buildAvatarAndGlobalCounter(UserModel user) {
    return StreamBuilder(
      stream: _usersStream,
      builder: (context, snapshot) {
        final users = snapshot.data ?? const [];
        final avatarMap = {for (final u in users) u.username: u.avatarUrl};
        final currentUserAvatar =
            avatarMap[user.username] ?? user.avatarUrl ?? '';

        return StreamBuilder<bool>(
          stream: _connectionStream,
          initialData: RepositoryService().connectionState.latestOrNull,
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
                      style: Theme.of(context).textTheme.headlineMedium
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
                        if (counterSnapshot.connectionState ==
                            ConnectionState.waiting) {
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
              for (final u in usersSnapshot.data ?? const [])
                u.username: u.avatarUrl,
            };
            _avatarMap = Map<String, String?>.from(avatarMap);
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
                  child:
                      usersSnapshot.connectionState == ConnectionState.waiting
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
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
    final indicatorColor = connectionStatus == null
        ? null
        : (connectionStatus! ? Colors.green : Colors.red);
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

/// Handles navigation concerns with a shared navigator key.
class NavigatorService {
  NavigatorService._internal();
  static NavigatorService? _instance;
  factory NavigatorService() => _instance ??= NavigatorService._internal();

  final navigatorKey = GlobalKey<NavigatorState>();

  Future<T?> push<T extends Object?>(Widget page) async => navigatorKey
      .currentState
      ?.push<T>(MaterialPageRoute(builder: (_) => page));

  Future<T?> pushReplacement<T extends Object?, TO extends Object?>(
    Widget page, {
    TO? result,
  }) async => navigatorKey.currentState?.pushReplacement<T, TO>(
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

/// Small helper to expose connection state as a stream with the last value cached.
class ConnectionSignal {
  ConnectionSignal() : _controller = StreamController<bool>.broadcast();

  final StreamController<bool> _controller;
  bool? _latest;

  Stream<bool> get stream => _controller.stream;
  bool? get latestOrNull => _latest;

  void add(bool value) {
    _latest = value;
    if (!_controller.isClosed) {
      _controller.add(value);
    }
  }
}

/// Central orchestrator for auth, persistence, and sync.
/// Coordinates repositories, storage, sync strategy, and session/namespace handling.
class RepositoryService {
  static const tag = 'RepositoryService';

  static RepositoryService? _instance;
  factory RepositoryService() => _instance ??= RepositoryService._internal();

  LocalFirstClient? localFirst;
  UserModel? authenticatedUser;
  String _currentNamespace = 'default';
  final _lastUsernameKey = '__last_username__';

  final LocalFirstRepository<UserModel> userRepository;
  final LocalFirstRepository<CounterLogModel> counterLogRepository;
  final MongoPeriodicSyncStrategy syncStrategy;
  final ConnectionSignal connectionState;

  // Central orchestrator for the demo: wires repositories, storage, sync
  // strategy and handles auth/session (namespace) switching.
  RepositoryService._internal()
    : connectionState = ConnectionSignal(),
      userRepository = _buildUserRepository(),
      counterLogRepository = _buildCounterLogRepository(),
      syncStrategy = MongoPeriodicSyncStrategy() {
    syncStrategy.setConnectionListener(connectionState.add);
  }

  Future<UserModel?> initialize() async {
    final localFirst = this.localFirst ??= LocalFirstClient(
      repositories: [userRepository, counterLogRepository],
      localStorage: HiveLocalFirstStorage(),
      syncStrategies: [syncStrategy],
    );

    await localFirst.initialize();
    return await restoreLastUser();
  }

  List<UserModel> _usersFromEvents(List<LocalFirstEvent<UserModel>> events) =>
      events.map((e) => e.state).toList();

  List<CounterLogModel> _logsFromEvents(
    List<LocalFirstEvent<CounterLogModel>> events,
  ) => events.map((e) => e.state).toList();

  Future<void> signIn({required String username}) async {
    // On sign in, swap namespace, prefetch users from remote, and persist the new user.
    syncStrategy.stop();
    await _switchUserDatabase('');
    await _syncRemoteUsersToLocal();
    final existing = await userRepository
        .query()
        .where('username', isEqualTo: username)
        .getAll();
    final preservedAvatar = existing.isNotEmpty
        ? existing.first.state.avatarUrl
        : null;
    final user = authenticatedUser = UserModel(
      username: username,
      avatarUrl: preservedAvatar,
    );
    await userRepository.upsert(user, needSync: existing.isEmpty);
    await _persistLastUsername(username);
    syncStrategy.start();
    NavigatorService().navigateToHome();
  }

  Future<void> _syncRemoteUsersToLocal() async {
    final remote = await syncStrategy.fetchUsers();
    for (final data in remote) {
      try {
        final user = userRepository.fromJson(data);
        await userRepository.upsert(user, needSync: false);
      } catch (_) {
        // ignore malformed user entries
      }
    }
  }

  Future<void> signOut() async {
    // Stops sync and resets session-specific state.
    syncStrategy.stop();
    authenticatedUser = null;
    await _switchUserDatabase('');
    await localFirst?.setKeyValue(_lastUsernameKey, '');
    NavigatorService().navigateToSignIn();
  }

  Future<UserModel?> restoreUser(String username) async {
    await _switchUserDatabase('');
    final results = await userRepository
        .query()
        .where('username', isEqualTo: username)
        .getAll();
    final payloads = _usersFromEvents(results);
    if (payloads.isEmpty) return null;
    authenticatedUser = payloads.first;
    syncStrategy.start();
    return authenticatedUser;
  }

  Future<UserModel?> restoreLastUser() async {
    final username = await localFirst?.getMeta(_lastUsernameKey);
    if (username == null || username.isEmpty) return null;
    return restoreUser(username);
  }

  Future<void> _persistLastUsername(String username) =>
      localFirst?.setKeyValue(_lastUsernameKey, username) ?? Future.value();

  Future<List<UserModel>> getUsers() async =>
      _usersFromEvents(await userRepository.query().getAll());

  Future<List<CounterLogModel>> getLogs() async => _logsFromEvents(
    await counterLogRepository
        .query()
        .orderBy('created_at', descending: true)
        .getAll(),
  );

  Stream<List<CounterLogModel>> watchLogs() => counterLogRepository
      .query()
      .orderBy('created_at', descending: true)
      .watch()
      .map(_logsFromEvents);

  Stream<int> watchCounter() => watchLogs().map(
    (logs) => logs.fold<int>(0, (sum, log) => sum + log.increment),
  );

  Stream<List<CounterLogModel>> watchRecentLogs({int limit = 5}) =>
      watchLogs().map((logs) => logs.take(limit).toList());

  Stream<List<UserModel>> watchUsers() =>
      userRepository.query().orderBy('username').watch().map(_usersFromEvents);

  Future<JsonMap<String?>> getAvatarsForUsers(Set<String> usernames) async {
    if (usernames.isEmpty) return {};
    final results = await userRepository
        .query()
        .where('username', whereIn: usernames.toList())
        .getAll();

    final map = <String, String?>{
      for (final user in _usersFromEvents(results))
        user.username: user.avatarUrl,
    };

    for (final username in usernames) {
      map.putIfAbsent(username, () => null);
    }

    return map;
  }

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
    if (username == null) {
      throw Exception('User not authenticated');
    }

    final log = CounterLogModel(username: username, increment: amount);
    await counterLogRepository.upsert(log, needSync: true);
  }

  Future<void> _switchUserDatabase(String username) async {
    final db = localFirst;
    if (db == null) return;

    final namespace = _sanitizeNamespace(username);
    if (_currentNamespace == namespace) return;
    _currentNamespace = namespace;

    final storage = db.localStorage;
    if (storage is HiveLocalFirstStorage) {
      await storage.useNamespace(namespace);
    }
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

/// Domain model for a user with avatar metadata.
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
    final normalizedId = (id ?? username).trim().toLowerCase();
    return UserModel._(
      id: normalizedId,
      username: username,
      avatarUrl: avatarUrl,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
    );
  }

  JsonMap<dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'avatar_url': avatarUrl,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory UserModel.fromJson(JsonMap<dynamic> json) {
    final username = json['username'] ?? json['id'];
    return UserModel(
      id: (json['id'] ?? username).toString().trim().toLowerCase(),
      username: username,
      avatarUrl: json['avatar_url'],
      createdAt: DateTime.parse(json['created_at']).toUtc(),
      updatedAt: DateTime.parse(json['updated_at']).toUtc(),
    );
  }

  static UserModel resolveConflict(UserModel local, UserModel remote) {
    // Last write wins, but avatar value is preserved
    if (local.updatedAt == remote.updatedAt) return remote;
    final preferred = local.updatedAt.isAfter(remote.updatedAt)
        ? local
        : remote;
    final fallback = identical(preferred, local) ? remote : local;
    final avatar = preferred.avatarUrl ?? fallback.avatarUrl;
    return UserModel(
      id: preferred.id,
      username: preferred.username,
      avatarUrl: avatar,
      createdAt: preferred.createdAt,
      updatedAt: preferred.updatedAt,
    );
  }
}

class CounterLogModel {
  final String id;
  final String username;
  final int increment;
  final DateTime createdAt;
  final DateTime updatedAt;

  CounterLogModel._({
    required this.id,
    required this.username,
    required this.increment,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CounterLogModel({
    String? id,
    required String username,
    required int increment,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now().toUtc();
    return CounterLogModel._(
      id: id ?? '${username}_${now.millisecondsSinceEpoch}',
      username: username,
      increment: increment,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
    );
  }

  JsonMap<dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'increment': increment,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory CounterLogModel.fromJson(JsonMap<dynamic> json) {
    return CounterLogModel(
      id: json['id'],
      username: json['username'],
      increment: json['increment'],
      createdAt: DateTime.parse(json['created_at']).toUtc(),
      updatedAt: DateTime.parse(json['updated_at']).toUtc(),
    );
  }

  static CounterLogModel resolveConflict(
    CounterLogModel local,
    CounterLogModel remote,
  ) => local.updatedAt.isAfter(remote.updatedAt) ? local : remote;

  @override
  String toString() {
    final change = increment.abs();
    final verb = increment >= 0 ? 'Increased' : 'Decreased';
    return '$verb by $change by $username';
  }

  String toFormattedDate() => () {
    final local = createdAt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }();
}

LocalFirstRepository<UserModel> _buildUserRepository() {
  return LocalFirstRepository.create(
    name: 'user',
    getId: (user) => user.id,
    toJson: (user) => user.toJson(),
    fromJson: (json) => UserModel.fromJson(json),
    onConflict: UserModel.resolveConflict,
  );
}

LocalFirstRepository<CounterLogModel> _buildCounterLogRepository() {
  return LocalFirstRepository.create(
    name: 'counter_log',
    getId: (log) => log.id,
    toJson: (log) => log.toJson(),
    fromJson: (json) => CounterLogModel.fromJson(json),
    onConflict: CounterLogModel.resolveConflict,
  );
}

/// Periodic sync strategy: batches pending events to MongoDB and pulls remote events.
/// Demonstrates the classic local-first loop (push pending, pull remote, merge).
class MongoPeriodicSyncStrategy extends DataSyncStrategy {
  static const logTag = 'MongoPeriodicSyncStrategy';
  final Duration period = const Duration(milliseconds: 500);
  final MongoApi mongoApi = MongoApi(
    uri: mongoConnectionString,
    repositoryNames: const ['counter_log', 'user'],
  );
  void Function(bool) _onConnectionChange = _noopConnection;
  bool _isSyncing = false;
  bool _connected = true;

  Timer? _timer;
  final JsonMap<DateTime?> lastSyncedAt = {};
  final JsonMap<List<LocalFirstEvent>> pendingChanges = {};

  void setConnectionListener(void Function(bool) listener) {
    _onConnectionChange = listener;
  }

  void start() {
    stop();
    client.awaitInitialization.then((_) async {
      final initialConnected = await _quickPing();
      reportConnectionState(initialConnected);
      dev.log('Starting periodic sync', name: logTag);
      final pendingEvents = await getPendingEvents();
      for (final event in pendingEvents) {
        _addPending(event);
      }
      for (final repository in mongoApi.repositoryNames) {
        final value = await client.getMeta('__last_sync__$repository');
        lastSyncedAt[repository] = value != null
            ? DateTime.tryParse(value)
            : null;
      }
      _timer = Timer.periodic(period, _onTimerTick);
      // Trigger immediate sync on start (and on reconnection).
      unawaited(_onTimerTick(null));
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    pendingChanges.clear();
    lastSyncedAt.clear();
  }

  void dispose() {
    stop();
  }

  void _addPending(LocalFirstEvent event) {
    pendingChanges.putIfAbsent(event.repositoryName, () => []).add(event);
  }

  @override
  Future<SyncStatus> onPushToRemote(LocalFirstEvent event) async {
    _addPending(event);
    return SyncStatus.pending;
  }

  Future<void> _onTimerTick(_) async {
    if (_isSyncing) return;
    _isSyncing = true;
    final drained = <String, List<LocalFirstEvent>>{};
    try {
      if (pendingChanges.isNotEmpty) {
        drained.addAll(pendingChanges);
        pendingChanges.clear();

        await _pushToRemote(drained).timeout(period * 2);
      }
      final remoteChanges = await mongoApi
          .pull(lastSyncedAt)
          .timeout(period * 2);
      if (remoteChanges['changes']?.isNotEmpty) {
        await pullChangesToLocal(remoteChanges);

        // Use the latest updated_at seen in this pull as the new lastSyncedAt
        final latest = mongoApi.latestUpdatedAt(remoteChanges);
        if (latest != null) {
          for (final repo in mongoApi.repositoryNames) {
            lastSyncedAt[repo] = latest;
            await client.setKeyValue(
              '__last_sync__$repo',
              latest.toIso8601String(),
            );
          }
        }
      }
      _setConnected(true);
    } on TimeoutException catch (e, s) {
      dev.log('Sync timeout: $e', name: logTag, error: e, stackTrace: s);
      _setConnected(false);
    } catch (e, s) {
      dev.log('Sync error: $e', name: logTag, error: e, stackTrace: s);
      // Re-queue drained changes so they retry on next tick.
      if (drained.isNotEmpty) {
        for (final entry in drained.entries) {
          pendingChanges.putIfAbsent(entry.key, () => []).addAll(entry.value);
        }
      }
      _setConnected(false);
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> _quickPing() async {
    try {
      await mongoApi.ping().timeout(period * 2);
      return true;
    } on TimeoutException catch (e, s) {
      dev.log('Ping timeout: $e', name: logTag, error: e, stackTrace: s);
      return false;
    } catch (e, s) {
      dev.log('Ping failed: $e', name: logTag, error: e, stackTrace: s);
      return false;
    }
  }

  Future<void> _pushToRemote(JsonMap<List<LocalFirstEvent>> changes) async {
    if (changes.isEmpty) return;
    dev.log(
      'Pushing changes for ${changes.length} repository(ies)',
      name: logTag,
    );
    await mongoApi.push(_buildUploadPayload(changes));
  }

  JsonMap<dynamic> _buildUploadPayload(JsonMap<List<LocalFirstEvent>> changes) {
    return {
      'lastSyncedAt': DateTime.now().toUtc().toIso8601String(),
      'changes': {
        for (final entry in changes.entries)
          entry.key: entry.value.toJson(
            (payload) => client.getRepositoryByName(entry.key).toJson(payload),
          ),
      },
    };
  }

  Future<List<JsonMap<dynamic>>> fetchUsers() {
    return mongoApi.fetchUsers();
  }

  void _emitConnection(bool connected) {
    try {
      _onConnectionChange(connected);
      reportConnectionState(connected);
      dev.log(
        'Connection state: ${connected ? 'connected' : 'disconnected'}',
        name: logTag,
      );
    } catch (_) {}
  }

  void _setConnected(bool connected) {
    if (_connected == connected) return;
    _connected = connected;
    _emitConnection(connected);
    if (connected && _timer != null && !_isSyncing) {
      // Trigger an immediate sync when coming back online.
      unawaited(_onTimerTick(null));
    }
  }

  static void _noopConnection(bool _) {}
}

/// Low-level helper to push/pull changes against MongoDB.
/// Minimal MongoDB adapter used by the demo sync strategy (push/pull events).
class MongoApi {
  static const logTag = 'MongoApi';
  final String uri;
  final List<String> repositoryNames;
  final String collectionPrefix;

  Db? _db;

  MongoApi({
    required this.uri,
    required this.repositoryNames,
    this.collectionPrefix = 'offline_',
  });

  Future<Db> _getDb() async {
    final current = _db;
    if (current != null && current.isConnected) return current;

    final db = await Db.create(uri);
    await db.open();
    dev.log('Connected to MongoDB at $uri', name: logTag);
    _db = db;
    return db;
  }

  Future<DbCollection> _collection(String repositoryName) async {
    final db = await _getDb();
    final collection = db.collection('$collectionPrefix$repositoryName');

    try {
      await collection.createIndex(keys: {'updated_at': 1});
    } catch (_) {
      // Ignora erros de índice existente
    }

    return collection;
  }

  Future<void> push(JsonMap<dynamic> payload) async {
    // Uploads batched events grouped by repository.
    final operationsByNode = payload['changes'];
    if (operationsByNode is! JsonMap<dynamic>) return;

    final now = DateTime.now().toUtc();
    final hasChanges = operationsByNode.values.any((op) {
      if (op is! JsonMap) return false;
      return (op['insert'] as List?)?.isNotEmpty == true ||
          (op['update'] as List?)?.isNotEmpty == true ||
          (op['delete'] as List?)?.isNotEmpty == true;
    });
    if (!hasChanges) return;

    dev.log('Uploading changes to Mongo', name: logTag);
    for (final entry in operationsByNode.entries) {
      final repositoryName = entry.key;
      final operations = entry.value;
      if (operations is! JsonMap<dynamic>) continue;
      final collection = await _collection(repositoryName);

      final insertItems = operations['insert'];
      if (insertItems is List) {
        for (final item in insertItems) {
          if (item is! JsonMap<dynamic>) continue;
          final id = item['id']?.toString();
          if (id == null) continue;
          await collection.insertOne({
            ..._toMongoDateFields(item),
            'operation': 'insert',
            'event_id': item['event_id'],
            'updated_at': now,
          });
        }
      }

      final updateItems = operations['update'];
      if (updateItems is List) {
        for (final item in updateItems) {
          if (item is! JsonMap<dynamic>) continue;
          final id = item['id']?.toString();
          if (id == null) continue;
          await collection.insertOne({
            ..._toMongoDateFields(item),
            'operation': 'update',
            'event_id': item['event_id'],
            'updated_at': now,
          });
        }
      }

      final deleteItems = operations['delete'];
      if (deleteItems is List) {
        for (final item in deleteItems) {
          if (item is! Map) continue;
          final id = item['id']?.toString();
          if (id == null) continue;
          await collection.insertOne({
            'id': id,
            'operation': 'delete',
            'event_id': item['event_id'],
            'updated_at': now,
          });
        }
      }
    }
  }

  Future<JsonMap<dynamic>> pull(JsonMap<DateTime?> lastSyncByNode) async {
    // Pulls new events since the last sync timestamp per repository.
    final timestamp = DateTime.now().toUtc();

    final changes = <String, JsonMap<List<dynamic>>>{};

    for (final repositoryName in repositoryNames) {
      final cutoff =
          lastSyncByNode[repositoryName] ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final collection = await _collection(repositoryName);
      final cursor = collection.find(
        where.gt('updated_at', cutoff).sortBy('updated_at'),
      );

      final inserts = <dynamic>[];
      final updates = <dynamic>[];
      final deletes = <dynamic>[];

      await cursor.forEach((doc) {
        final op = doc['operation'];
        if (op == 'delete') {
          if (doc['id'] != null) {
            deletes.add({'id': doc['id'], 'event_id': doc['event_id']});
          }
          return;
        }
        final item = Map<String, dynamic>.from(doc)
          ..remove('operation')
          ..remove('_id');
        if (op == 'insert') {
          inserts.add(_fromMongoDateFields(item));
        } else {
          updates.add(_fromMongoDateFields(item));
        }
      });

      final finalChanges = {
        if (inserts.isNotEmpty) 'insert': inserts,
        if (updates.isNotEmpty) 'update': updates,
        if (deletes.isNotEmpty) 'delete': deletes,
      };
      if (finalChanges.isNotEmpty) {
        dev.log(
          'Pulling changes for $repositoryName since ${lastSyncByNode[repositoryName]}',
          name: logTag,
        );
        changes[repositoryName] = finalChanges;
      }
    }

    return {'timestamp': timestamp.toIso8601String(), 'changes': changes};
  }

  Future<List<JsonMap<dynamic>>> fetchUsers() async {
    dev.log('Fetching users snapshot', name: logTag);
    final collection = await _collection('user');
    final cursor = collection.find(where.ne('operation', 'delete'));

    final users = <String, JsonMap<dynamic>>{};

    await cursor.forEach((doc) {
      final id = doc['id'];
      if (id is! String) return;
      final data = Map<String, dynamic>.from(doc)
        ..remove('_id')
        ..remove('operation');
      users[id] = _fromMongoDateFields(data);
    });

    return users.values.toList();
  }

  Future<void> ping() async {
    final collection = await _collection(repositoryNames.first);
    // Lightweight query to check connectivity.
    await collection.count();
  }

  DateTime? latestUpdatedAt(JsonMap<dynamic> pullResult) {
    final changes = pullResult['changes'];
    if (changes is! JsonMap) return null;
    DateTime? latest;

    for (final repositoryEntry in changes.entries) {
      final repositoryChanges = repositoryEntry.value;
      if (repositoryChanges is! JsonMap) continue;

      for (final key in ['insert', 'update']) {
        final list = repositoryChanges[key];
        if (list is! List) continue;
        for (final item in list) {
          if (item is! Map<String, dynamic>) continue;
          final updatedValue = item['updated_at'];
          DateTime? candidate;
          if (updatedValue is DateTime) {
            candidate = updatedValue;
          } else if (updatedValue is String) {
            candidate = DateTime.tryParse(updatedValue);
          }
          if (candidate != null &&
              (latest == null || candidate.isAfter(latest))) {
            latest = candidate;
          }
        }
      }
    }
    return latest;
  }

  JsonMap<dynamic> _toMongoDateFields(JsonMap<dynamic> item) {
    final map = Map<String, dynamic>.from(item);
    for (final key in ['created_at', 'updated_at']) {
      final value = map[key];
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          map[key] = parsed;
        }
      }
    }
    return map;
  }

  JsonMap<dynamic> _fromMongoDateFields(JsonMap<dynamic> item) {
    final map = Map<String, dynamic>.from(item);
    for (final key in ['created_at', 'updated_at']) {
      final value = map[key];
      if (value is DateTime) {
        map[key] = value.toIso8601String();
      }
    }
    return map;
  }
}
