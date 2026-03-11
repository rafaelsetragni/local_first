import 'dart:async';
import 'package:flutter/material.dart';
import 'package:local_first/local_first.dart';
import '../models/user_model.dart';
import '../models/counter_log_model.dart';
import '../services/repository_service.dart';
import '../services/navigator_service.dart';
import '../widgets/avatar_preview.dart';
import '../widgets/counter_log_tile.dart';

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
