import 'dart:async';

import 'package:flutter/material.dart';

import '../services/repository_service.dart';

/// InheritedWidget that provides unread counts to descendant widgets.
///
/// This ensures only ONE stream subscription exists for unread counts,
/// and all descendant widgets share the same data without causing
/// unnecessary rebuilds of the parent widget tree.
class UnreadCountsProvider extends StatefulWidget {
  final Widget child;

  const UnreadCountsProvider({
    super.key,
    required this.child,
  });

  /// Gets the unread count for a specific chat from the nearest provider.
  /// Returns 0 if no provider is found or chat has no unread messages.
  static int getCount(BuildContext context, String chatId) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<_UnreadCountsInherited>();
    return provider?.counts[chatId] ?? 0;
  }

  /// Gets all unread counts from the nearest provider.
  static Map<String, int> getCounts(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<_UnreadCountsInherited>();
    return provider?.counts ?? {};
  }

  @override
  State<UnreadCountsProvider> createState() => _UnreadCountsProviderState();
}

class _UnreadCountsProviderState extends State<UnreadCountsProvider> {
  final _repositoryService = RepositoryService();
  Map<String, int> _counts = {};
  StreamSubscription<Map<String, int>>? _subscription;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    // Load initial counts
    final initialCounts = await _repositoryService.getUnreadCountsMap();
    if (mounted) {
      setState(() {
        _counts = initialCounts;
        _initialized = true;
      });
    }

    // Subscribe to updates
    _subscription = _repositoryService.watchUnreadCounts().listen((counts) {
      if (mounted && !_mapsEqual(_counts, counts)) {
        setState(() => _counts = counts);
      }
    });
  }

  bool _mapsEqual(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _UnreadCountsInherited(
      counts: _counts,
      initialized: _initialized,
      child: widget.child,
    );
  }
}

/// The actual InheritedWidget that holds the data.
class _UnreadCountsInherited extends InheritedWidget {
  final Map<String, int> counts;
  final bool initialized;

  const _UnreadCountsInherited({
    required this.counts,
    required this.initialized,
    required super.child,
  });

  @override
  bool updateShouldNotify(_UnreadCountsInherited oldWidget) {
    // Only notify if the counts actually changed
    if (counts.length != oldWidget.counts.length) return true;
    for (final key in counts.keys) {
      if (counts[key] != oldWidget.counts[key]) return true;
    }
    return false;
  }
}
