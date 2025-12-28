import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_sqlite_storage/local_first_sqlite_storage.dart';
import 'package:mongo_dart/mongo_dart.dart' hide State, Center;

typedef JsonMap<T> = Map<String, T>;

const luidAlphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
final luidRandom = math.Random.secure();

String generateLuid([int length = 12]) {
  final buffer = StringBuffer();
  for (var i = 0; i < length; i += 1) {
    buffer.write(luidAlphabet[luidRandom.nextInt(luidAlphabet.length)]);
  }
  return buffer.toString();
}

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
  State<SignInPage> createState() => SignInPageState();
}

class SignInPageState extends State<SignInPage> {
  final formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();

  @override
  void dispose() {
    usernameController.dispose();
    super.dispose();
  }

  Future<void> signIn() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    final username = usernameController.text;
    await RepositoryService().signIn(username: username);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SafeArea(
          child: Form(
            key: formKey,
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
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                      ),
                      onFieldSubmitted: (_) => signIn(),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Please enter a username.'
                          : null,
                    ),
                    SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: signIn,
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
  State<MyHomePage> createState() => MyHomePageState();
}

class MyHomePageState extends State<MyHomePage> {
  late final Stream<int> counterStream;
  late final Stream<List<UserModel>> usersStream;
  late final Stream<List<CounterLogModel>> recentLogsStream;
  late final Stream<bool> remoteConnectionStream;

  @override
  void initState() {
    super.initState();
    final service = RepositoryService();
    usersStream = service.watchUsers();
    counterStream = service.watchCounter();
    recentLogsStream = service.watchRecentLogs(limit: 5);
    remoteConnectionStream = service.watchRemoteConnection();
  }

  Future<void> onAvatarTap(BuildContext context, String currentAvatar) async {
    final url = await promptAvatarDialog(context, currentAvatar);
    if (url == null) return;
    await RepositoryService().updateAvatarUrl(url);
  }

  Future<String?> promptAvatarDialog(
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
      extendBodyBehindAppBar: true,
      appBar: buildSignOutAppBar(),
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: StreamBuilder<List<UserModel>>(
              stream: usersStream,
              builder: (context, snapshot) {
                final users = snapshot.data ?? const <UserModel>[];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Center(
                        child: buildAvatarAndGlobalCounter(user, users),
                      ),
                    ),
                    Column(
                      children: [
                        buildUserList(context, users),
                        buildRecentActivities(context, users),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: StreamBuilder<bool>(
              stream: remoteConnectionStream,
              initialData: true,
              builder: (context, snapshot) {
                final connected = snapshot.data ?? true;
                final color = connected
                    ? Colors.green.shade600
                    : Colors.red.shade700;
                final message = connected
                    ? 'Remote connection stablished'
                    : 'Without remote connection';
                return Container(
                  padding: EdgeInsets.only(
                    top: MediaQuery.paddingOf(context).top - 64,
                    bottom: 4,
                  ),
                  color: color,
                  alignment: Alignment.center,
                  child: Text(
                    message,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          ),
        ],
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

  Column buildAvatarAndGlobalCounter(UserModel user, List<UserModel> users) {
    final avatarMap = {for (final u in users) u.username: u.avatarUrl};
    final currentUserAvatar = avatarMap[user.username] ?? user.avatarUrl ?? '';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => onAvatarTap(context, currentUserAvatar),
          child: AvatarPreview(
            avatarUrl: currentUserAvatar,
            showEditIndicator: true,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Hello, ${user.username}!',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('Global counter updated by all users:'),
        StreamBuilder<int>(
          stream: counterStream,
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
    );
  }

  AppBar buildSignOutAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      actions: [
        IconButton(
          icon: const Icon(Icons.logout),
          tooltip: 'Logout',
          onPressed: RepositoryService().signOut,
        ),
      ],
    );
  }

  Column buildRecentActivities(BuildContext context, List<UserModel> users) {
    final avatarMap = {for (final u in users) u.username: u.avatarUrl};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Text(
            'Recent activities:',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Container(
          color: ColorScheme.of(context).surfaceContainerLow,
          padding: const EdgeInsets.all(24.0),
          child: StreamBuilder(
            stream: recentLogsStream,
            builder: (context, logsSnapshot) {
              final recentLogs = logsSnapshot.data ?? const [];
              if (logsSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recentLogs.length,
                itemBuilder: (context, index) {
                  final log = recentLogs[index];
                  final avatar = avatarMap[log.username] ?? '';
                  return CounterLogTile(log: log, avatarUrl: avatar);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget buildUserList(BuildContext context, List<UserModel> users) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Users:', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < users.length; i += 1) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AvatarPreview(
                        radius: 22,
                        avatarUrl: users[i].avatarUrl ?? '',
                        showEditIndicator: false,
                      ),
                      const SizedBox(height: 6),
                      Text(users[i].username),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
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
  const AvatarPreview({
    super.key,
    required this.avatarUrl,
    this.showEditIndicator = false,
    this.radius = 50,
  });

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl.isNotEmpty;
    return Stack(
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: ColorScheme.of(context).surfaceContainerHighest,
          backgroundImage: hasAvatar ? NetworkImage(avatarUrl) : null,
          child: hasAvatar ? null : Icon(Icons.person, size: radius),
        ),
        if (showEditIndicator)
          Positioned(
            bottom: 4,
            right: 4,
            child: PhysicalModel(
              color: Colors.transparent,
              elevation: 4,
              shadowColor: ColorScheme.of(context).shadow,
              shape: BoxShape.circle,
              child: CircleAvatar(
                radius: 14,
                backgroundColor: ColorScheme.of(context).primaryFixed,
                child: Icon(
                  Icons.edit,
                  size: 16,
                  color: ColorScheme.of(context).onPrimaryFixed,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Handles navigation concerns with a shared navigator key.
class NavigatorService {
  NavigatorService.internal();
  static NavigatorService? instance;
  factory NavigatorService() => instance ??= NavigatorService.internal();

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

/// Central orchestrator for auth, persistence, and sync.
class RepositoryService {
  static const tag = 'RepositoryService';

  static RepositoryService? instance;
  factory RepositoryService() => instance ??= RepositoryService.internal();

  LocalFirstClient? localFirst;
  UserModel? authenticatedUser;
  String currentNamespace = 'default';
  final lastUsernameKey = '__last_username__';
  final deviceIdKey = '__device_id__';
  final StreamController<int> counterTotalController = StreamController<int>();
  int counterTotal = 0;
  final StreamController<bool> remoteConnectionController =
      StreamController<bool>();
  bool isRemoteConnected = true;

  final LocalFirstRepository<UserModel> userRepository;
  final LocalFirstRepository<CounterLogModel> counterLogRepository;
  final LocalFirstRepository<CounterDeviceModel> counterDeviceRepository;
  final MongoPeriodicSyncStrategy syncStrategy;
  String? deviceId;

  RepositoryService.internal()
    : userRepository = buildUserRepository(),
      counterLogRepository = buildCounterLogRepository(),
      counterDeviceRepository = buildCounterDeviceRepository(),
      syncStrategy = MongoPeriodicSyncStrategy() {
    syncStrategy.onCounterDelta = applyCounterDelta;
    syncStrategy.onConnectionStatus = setRemoteConnection;
  }

  Future<UserModel?> initialize() async {
    final localFirst = this.localFirst ??= LocalFirstClient(
      repositories: [
        userRepository,
        counterLogRepository,
        counterDeviceRepository,
      ],
      localStorage: SqliteLocalFirstStorage(),
      syncStrategies: [syncStrategy],
    );
    await localFirst.initialize();
    return await restoreLastUser();
  }

  Future<void> signIn({required String username}) async {
    await openDatabaseForUser(username);
    await syncRemoteUsersToLocal();
    final existing = await userRepository
        .query()
        .where('username', isEqualTo: username)
        .getAll();
    final preservedAvatar = existing.isNotEmpty
        ? existing.first.avatarUrl
        : null;
    final user = authenticatedUser = UserModel(
      username: username,
      avatarUrl: preservedAvatar,
    );
    await userRepository.upsert(user);
    await persistLastUsername(username);
    NavigatorService().navigateToHome();
  }

  Future<void> syncRemoteUsersToLocal() async {
    final remote = await syncStrategy.fetchUsers();
    for (final data in remote) {
      try {
        final user = userRepository.fromJson(data);
        await userRepository.upsert(user);
      } catch (_) {
        // ignore malformed user entries
      }
    }
  }

  Future<void> signOut() async {
    authenticatedUser = null;
    await localFirst?.setKeyValue(lastUsernameKey, '');
    await closeDatabase();
    NavigatorService().navigateToSignIn();
  }

  Future<UserModel?> restoreUser(String username) async {
    await openDatabaseForUser(username);
    final results = await userRepository
        .query()
        .where('username', isEqualTo: username)
        .getAll();
    if (results.isEmpty) return null;
    authenticatedUser = results.first;
    return authenticatedUser;
  }

  Future<UserModel?> restoreLastUser() async {
    final username = await localFirst?.getMeta(lastUsernameKey);
    if (username == null || username.isEmpty) return null;
    return restoreUser(username);
  }

  Future<void> persistLastUsername(String username) =>
      localFirst?.setKeyValue(lastUsernameKey, username) ?? Future.value();

  Future<List<UserModel>> getUsers() => userRepository.query().getAll();

  Future<List<CounterLogModel>> getLogs() => counterLogRepository
      .query()
      .orderBy('created_at', descending: true)
      .getAll();

  Stream<List<CounterLogModel>> watchLogs() => counterLogRepository
      .query()
      .orderBy('created_at', descending: true)
      .watch();

  Stream<int> watchCounter() => counterDeviceRepository.query().watch().map((
    counters,
  ) {
    final total = counters.fold(0, (sum, counter) => sum + counter.count);
    counterTotal = total;
    return total;
  });

  Stream<bool> watchRemoteConnection() => (() async* {
    yield isRemoteConnected;
    yield* remoteConnectionController.stream;
  })();

  Stream<List<CounterLogModel>> watchRecentLogs({int limit = 5}) =>
      watchLogs().map((logs) => logs.take(limit).toList());

  Stream<List<UserModel>> watchUsers() =>
      userRepository.query().orderBy('username').watch();

  Future<JsonMap<String?>> getAvatarsForUsers(Set<String> usernames) async {
    if (usernames.isEmpty) return {};
    final results = await userRepository
        .query()
        .where('username', whereIn: usernames.toList())
        .getAll();

    final map = <String, String?>{
      for (final user in results) user.username: user.avatarUrl,
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
      updatedAt: DateTime.now(),
    );

    await userRepository.upsert(updated);
    authenticatedUser = updated;
    return updated;
  }

  void incrementCounter() => createLogRegistry(1);
  void decrementCounter() => createLogRegistry(-1);

  Future<void> createLogRegistry(int amount) async {
    final username = authenticatedUser?.username;
    if (username == null) {
      throw Exception('User not authenticated');
    }

    final log = CounterLogModel(username: username, increment: amount);
    await counterLogRepository.upsert(log);
    await updateDeviceCounter(username, amount);
    await refreshCounterTotalFromLocal();
  }

  Future<void> openDatabaseForUser(String username) async {
    final db = localFirst;
    if (db == null) return;

    syncStrategy.stop();
    final namespace = sanitizeNamespace(username);
    final shouldReset = currentNamespace != namespace;
    if (shouldReset) {
      userRepository.reset();
      counterLogRepository.reset();
      counterDeviceRepository.reset();
    }

    await db.localStorage.close();
    await db.openStorage(namespace: namespace);
    currentNamespace = namespace;
    syncStrategy.setNamespace(namespace);
    deviceId = null;
    await ensureDeviceId();
    await loadCounterTotal();
    await syncStrategy.syncNow();
    syncStrategy.start();
  }

  Future<void> closeDatabase() async {
    syncStrategy.stop();
    await localFirst?.closeStorage();
    counterTotal = 0;
    deviceId = null;
    counterTotalController.add(counterTotal);
  }

  String sanitizeNamespace(String username) {
    if (username.isEmpty) return 'default';
    final sanitized = username.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_-]'),
      '_',
    );
    return 'user__$sanitized';
  }

  Future<void> loadCounterTotal() async {
    await refreshCounterTotalFromLocal();
  }

  Future<void> applyCounterDelta(int delta) async {
    await refreshCounterTotalFromLocal();
  }

  Future<void> refreshCounterTotalFromLocal() async {
    final counters = await counterDeviceRepository.query().getAll();
    counterTotal = counters.fold(0, (sum, counter) => sum + counter.count);
    counterTotalController.add(counterTotal);
  }

  void setRemoteConnection(bool connected) {
    if (isRemoteConnected == connected) return;
    isRemoteConnected = connected;
    remoteConnectionController.add(connected);
  }

  Future<void> ensureDeviceId() async {
    if (deviceId != null) return;
    final stored = await localFirst?.getMeta(deviceIdKey);
    if (stored != null && stored.isNotEmpty) {
      deviceId = stored;
      return;
    }
    final generated = generateLuid();
    deviceId = generated;
    await localFirst?.setKeyValue(deviceIdKey, generated);
  }

  Future<void> updateDeviceCounter(String username, int delta) async {
    await ensureDeviceId();
    final deviceId = this.deviceId;
    if (deviceId == null) return;
    final id = CounterDeviceModel.composeId(username, deviceId);
    final existing = await counterDeviceRepository
        .query()
        .where('id', isEqualTo: id)
        .getAll();
    final current = existing.isNotEmpty ? existing.first : null;
    final updated = CounterDeviceModel(
      id: id,
      username: username,
      deviceId: deviceId,
      count: (current?.count ?? 0) + delta,
      createdAt: current?.createdAt,
    );
    await counterDeviceRepository.upsert(updated);
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
    final now = DateTime.now();
    return UserModel._(
      id: id ?? username,
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
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory UserModel.fromJson(JsonMap<dynamic> json) {
    final username = json['username'] ?? json['id'];
    return UserModel(
      id: json['id'] ?? username,
      username: username,
      avatarUrl: json['avatar_url'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
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
    final now = DateTime.now();
    return CounterLogModel._(
      id: id ?? '${username}_${generateLuid()}',
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
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory CounterLogModel.fromJson(JsonMap<dynamic> json) {
    return CounterLogModel(
      id: json['id'],
      username: json['username'],
      increment: json['increment'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
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

  String toFormattedDate() =>
      '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year} '
      '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
}

class CounterDeviceModel {
  final String id;
  final String username;
  final String deviceId;
  final int count;
  final DateTime createdAt;
  final DateTime updatedAt;

  CounterDeviceModel._({
    required this.id,
    required this.username,
    required this.deviceId,
    required this.count,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CounterDeviceModel({
    String? id,
    required String username,
    required String deviceId,
    required int count,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now();
    return CounterDeviceModel._(
      id: id ?? composeId(username, deviceId),
      username: username,
      deviceId: deviceId,
      count: count,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
    );
  }

  static String composeId(String username, String deviceId) =>
      '${username}__$deviceId';

  JsonMap<dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'device_id': deviceId,
      'count': count,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory CounterDeviceModel.fromJson(JsonMap<dynamic> json) {
    return CounterDeviceModel(
      id: json['id'],
      username: json['username'],
      deviceId: json['device_id'],
      count: json['count'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  static CounterDeviceModel resolveConflict(
    CounterDeviceModel local,
    CounterDeviceModel remote,
  ) => local.updatedAt.isAfter(remote.updatedAt) ? local : remote;
}

LocalFirstRepository<UserModel> buildUserRepository() {
  return LocalFirstRepository.create(
    name: 'user',
    getId: (user) => user.id,
    toJson: (user) => user.toJson(),
    fromJson: (json) => UserModel.fromJson(json),
    onConflict: UserModel.resolveConflict,
    schema: const {
      'username': LocalFieldType.text,
      'avatar_url': LocalFieldType.text,
      'created_at': LocalFieldType.datetime,
      'updated_at': LocalFieldType.datetime,
    },
  );
}

LocalFirstRepository<CounterLogModel> buildCounterLogRepository() {
  return LocalFirstRepository.create(
    name: 'counter_log',
    getId: (log) => log.id,
    toJson: (log) => log.toJson(),
    fromJson: (json) => CounterLogModel.fromJson(json),
    onConflict: CounterLogModel.resolveConflict,
    schema: const {
      'username': LocalFieldType.text,
      'increment': LocalFieldType.integer,
      'created_at': LocalFieldType.datetime,
      'updated_at': LocalFieldType.datetime,
    },
  );
}

LocalFirstRepository<CounterDeviceModel> buildCounterDeviceRepository() {
  return LocalFirstRepository.create(
    name: 'counter_device',
    getId: (counter) => counter.id,
    toJson: (counter) => counter.toJson(),
    fromJson: (json) => CounterDeviceModel.fromJson(json),
    onConflict: CounterDeviceModel.resolveConflict,
    schema: const {
      'username': LocalFieldType.text,
      'device_id': LocalFieldType.text,
      'count': LocalFieldType.integer,
      'created_at': LocalFieldType.datetime,
      'updated_at': LocalFieldType.datetime,
    },
  );
}

/// Periodically syncs pending changes with MongoDB and pulls updates.
class MongoPeriodicSyncStrategy extends DataSyncStrategy {
  static const logTag = 'MongoPeriodicSyncStrategy';
  final Duration period = const Duration(milliseconds: 500);
  final MongoApi mongoApi = MongoApi(
    uri: mongoConnectionString,
    repositoryNames: const ['counter_device', 'counter_log', 'user'],
  );

  Timer? timer;
  String namespace = 'default';
  final JsonMap<DateTime?> lastSyncedAt = {};
  final JsonMap<List<LocalFirstEvent>> pendingChanges = {};
  Future<void> Function(int delta)? onCounterDelta;
  void Function(bool connected)? onConnectionStatus;
  bool isConnected = true;

  void setNamespace(String namespace) {
    this.namespace = namespace;
  }

  String lastSyncKey(String repository) {
    return '__last_sync__${namespace}__$repository';
  }

  void start() {
    stop();
    client.awaitInitialization.then((_) async {
      dev.log('Starting periodic sync', name: logTag);
      final pendingObjects = await getPendingObjects();
      for (final object in pendingObjects) {
        addPending(object);
      }
      for (final repository in mongoApi.repositoryNames) {
        final value = await client.getMeta(lastSyncKey(repository));
        lastSyncedAt[repository] = value != null
            ? DateTime.tryParse(value)
            : null;
      }
      timer = Timer.periodic(period, onTimerTick);
    });
  }

  void stop() {
    timer?.cancel();
    timer = null;
    pendingChanges.clear();
    lastSyncedAt.clear();
  }

  Future<void> syncNow() async {
    await client.awaitInitialization;
    if (lastSyncedAt.isEmpty) {
      for (final repository in mongoApi.repositoryNames) {
        final value = await client.getMeta(lastSyncKey(repository));
        lastSyncedAt[repository] = value != null
            ? DateTime.tryParse(value)
            : null;
      }
    }
    await onTimerTick(null);
  }

  void dispose() {
    stop();
  }

  void addPending(LocalFirstEvent object) {
    pendingChanges.putIfAbsent(object.repositoryName, () => []).add(object);
  }

  @override
  Future<SyncStatus> onPushToRemote(LocalFirstEvent object) async {
    addPending(object);
    return SyncStatus.pending;
  }

  Future<void> onTimerTick(_) async {
    try {
      if (pendingChanges.isNotEmpty) {
        final changes = JsonMap<List<LocalFirstEvent>>.from(pendingChanges);
        pendingChanges.clear();
        final pushed = await pushToRemote(changes);
        if (!pushed) {
          setConnectionStatus(false);
          requeueChanges(changes);
          return;
        }
      }
      JsonMap<dynamic> remoteChanges;
      try {
        remoteChanges = await mongoApi.pull(lastSyncedAt);
      } catch (e) {
        setConnectionStatus(false);
        dev.log('Pull failed, keeping local state', name: logTag, error: e);
        return;
      }
      setConnectionStatus(true);
      if (remoteChanges['changes']?.isNotEmpty) {
        final hasCounterChanges = this.hasCounterChanges(remoteChanges);
        await pullChangesToLocal(remoteChanges);
        if (hasCounterChanges) {
          await onCounterDelta?.call(0);
        }

        // Use the latest updated_at seen in this pull as the new lastSyncedAt
        final latest = mongoApi.latestUpdatedAt(remoteChanges);
        if (latest != null) {
          for (final repo in mongoApi.repositoryNames) {
            lastSyncedAt[repo] = latest;
            await client.setKeyValue(
              lastSyncKey(repo),
              latest.toIso8601String(),
            );
          }
        }
      }
    } catch (e) {
      setConnectionStatus(false);
      dev.log('Sync tick failed', name: logTag, error: e);
    }
  }

  bool hasCounterChanges(JsonMap<dynamic> remoteChanges) {
    final changes = remoteChanges['changes'];
    if (changes is! Map) return false;
    final counterChanges = changes['counter_device'];
    if (counterChanges is! Map) return false;
    return (counterChanges['insert'] as List?)?.isNotEmpty == true ||
        (counterChanges['update'] as List?)?.isNotEmpty == true ||
        (counterChanges['delete'] as List?)?.isNotEmpty == true;
  }

  Future<bool> pushToRemote(JsonMap<List<LocalFirstEvent>> changes) async {
    if (changes.isEmpty) return true;
    dev.log(
      'Pushing changes for ${changes.length} repository(ies)',
      name: logTag,
    );
    try {
      await mongoApi.push(buildUploadPayload(changes));
      setConnectionStatus(true);
      return true;
    } catch (e) {
      setConnectionStatus(false);
      dev.log('Push failed, will retry later', name: logTag, error: e);
      return false;
    }
  }

  void requeueChanges(JsonMap<List<LocalFirstEvent>> changes) {
    for (final entry in changes.entries) {
      pendingChanges.putIfAbsent(entry.key, () => []).addAll(entry.value);
    }
  }

  void setConnectionStatus(bool connected) {
    if (isConnected == connected) return;
    isConnected = connected;
    onConnectionStatus?.call(connected);
  }

  JsonMap<dynamic> buildUploadPayload(JsonMap<List<LocalFirstEvent>> changes) {
    return {
      'lastSyncedAt': DateTime.now().toIso8601String(),
      'changes': {
        for (final entry in changes.entries)
          entry.key: (() {
            final repository = client.getRepositoryByName(entry.key);
            return entry.value.toJson<Object>(
              serializer: (Object item) => repository.toJson(item as dynamic),
              idFieldName: repository.idFieldName,
            );
          })(),
      },
    };
  }

  Future<List<JsonMap<dynamic>>> fetchUsers() {
    return mongoApi.fetchUsers();
  }
}

/// Low-level helper to push/pull changes against MongoDB.
class MongoApi {
  static const logTag = 'MongoApi';
  final String uri;
  final List<String> repositoryNames;
  final String collectionPrefix;
  final Duration requestTimeout;

  Db? db;

  MongoApi({
    required this.uri,
    required this.repositoryNames,
    this.collectionPrefix = 'offline_',
    this.requestTimeout = const Duration(seconds: 5),
  });

  Future<T> withTimeout<T>(Future<T> future) => future.timeout(requestTimeout);

  Future<Db> getDb() async {
    final current = db;
    if (current != null && current.isConnected) return current;
    try {
      final db = await Db.create(uri);
      await withTimeout(db.open());
      dev.log('Connected to MongoDB at $uri', name: logTag);
      this.db = db;
      return db;
    } catch (e) {
      dev.log('Failed to connect to MongoDB at $uri', name: logTag, error: e);
      db = null;
      rethrow;
    }
  }

  Future<DbCollection> collection(String repositoryName) async {
    final db = await getDb();
    final collection = db.collection('$collectionPrefix$repositoryName');

    try {
      await withTimeout(collection.createIndex(keys: {'updated_at': 1}));
    } catch (_) {
      // Ignora erros de índice existente
    }

    return collection;
  }

  Future<void> push(JsonMap<dynamic> payload) async {
    final operationsByNode = payload['changes'];
    if (operationsByNode is! JsonMap<dynamic>) return;

    final now = DateTime.now();
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
      final collection = await this.collection(repositoryName);

      final insertItems = operations['insert'];
      if (insertItems is List) {
        for (final item in insertItems) {
          if (item is! JsonMap<dynamic>) continue;
          final id = item['id']?.toString();
          if (id == null) continue;
          final doc = {
            ...toMongoDateFields(item),
            'operation': 'insert',
            'updated_at': now,
          };
          await withTimeout(
            collection.replaceOne(where.eq('id', id), doc, upsert: true),
          );
        }
      }

      final updateItems = operations['update'];
      if (updateItems is List) {
        for (final item in updateItems) {
          if (item is! JsonMap<dynamic>) continue;
          final id = item['id']?.toString();
          if (id == null) continue;
          final doc = {
            ...toMongoDateFields(item),
            'operation': 'update',
            'updated_at': now,
          };
          await withTimeout(
            collection.replaceOne(where.eq('id', id), doc, upsert: true),
          );
        }
      }

      final deleteItems = operations['delete'];
      if (deleteItems is List) {
        for (final id in deleteItems) {
          if (id == null) continue;
          await withTimeout(
            collection.replaceOne(where.eq('id', id.toString()), {
              'id': id.toString(),
              'operation': 'delete',
              'updated_at': now,
            }, upsert: true),
          );
        }
      }
    }
  }

  Future<JsonMap<dynamic>> pull(JsonMap<DateTime?> lastSyncByNode) async {
    final timestamp = DateTime.now();

    final changes = <String, JsonMap<List<dynamic>>>{};

    for (final repositoryName in repositoryNames) {
      final cutoff = lastSyncByNode[repositoryName];
      final collection = await this.collection(repositoryName);
      final cursor = cutoff == null
          ? (repositoryName == 'counter_device'
                ? collection.find(where.sortBy('updated_at'))
                : collection.find(
                    where.sortBy('updated_at', descending: true).limit(5),
                  ))
          : collection.find(
              where.gt('updated_at', cutoff).sortBy('updated_at'),
            );

      final inserts = <dynamic>[];
      final updates = <dynamic>[];
      final deletes = <dynamic>[];

      await withTimeout(
        cursor.forEach((doc) {
          final op = doc['operation'];
          if (op == 'delete') {
            if (doc['id'] != null) deletes.add(doc['id']);
            return;
          }
          final item = Map<String, dynamic>.from(doc)
            ..remove('operation')
            ..remove('_id');
          if (op == 'insert') {
            inserts.add(fromMongoDateFields(item));
          } else {
            updates.add(fromMongoDateFields(item));
          }
        }),
      );

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
    final collection = await this.collection('user');
    final cursor = collection.find(where.ne('operation', 'delete'));

    final users = <String, JsonMap<dynamic>>{};

    await withTimeout(
      cursor.forEach((doc) {
        final id = doc['id'];
        if (id is! String) return;
        final data = Map<String, dynamic>.from(doc)
          ..remove('_id')
          ..remove('operation');
        users[id] = fromMongoDateFields(data);
      }),
    );

    return users.values.toList();
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

  JsonMap<dynamic> toMongoDateFields(JsonMap<dynamic> item) {
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

  JsonMap<dynamic> fromMongoDateFields(JsonMap<dynamic> item) {
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
