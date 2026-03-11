import 'dart:async';

import 'package:flutter/material.dart';

import '../services/repository_service.dart';

/// A wrapper widget that displays a red "Connecting..." bar at the top
/// when the WebSocket connection is lost.
///
/// The bar appears above the safe area and uses safe area padding to
/// ensure the text is visible below any notch or status bar.
class ConnectionStatusBar extends StatefulWidget {
  final Widget child;

  const ConnectionStatusBar({super.key, required this.child});

  @override
  State<ConnectionStatusBar> createState() => _ConnectionStatusBarState();
}

class _ConnectionStatusBarState extends State<ConnectionStatusBar> {
  final _repositoryService = RepositoryService();
  StreamSubscription<bool>? _connectionSubscription;
  bool _isConnected = true;

  @override
  void initState() {
    super.initState();
    _isConnected = _repositoryService.isConnected;
    _connectionSubscription = _repositoryService.connectionState
        .distinct()
        .listen((connected) {
          if (mounted) {
            setState(() => _isConnected = connected);
          }
        });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return Column(
      children: [
        // Connection status bar - animates height when showing/hiding
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          width: double.infinity,
          height: _isConnected ? 0 : topPadding + 28,
          color: Colors.red,
          clipBehavior: Clip.hardEdge,
          padding: EdgeInsets.only(top: topPadding, bottom: 8),
          child: const Text(
            'Connecting...',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        // Main content - stable widget that doesn't rebuild
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: !_isConnected,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
