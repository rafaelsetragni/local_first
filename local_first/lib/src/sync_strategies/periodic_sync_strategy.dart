part of '../../local_first.dart';

/// Base strategy for periodic sync flows with connection reporting and timeout handling.
abstract class PeriodicSyncStrategy extends DataSyncStrategy {
  PeriodicSyncStrategy({required this.period});

  final Duration period;

  Timer? _timer;
  bool _isSyncing = false;
  bool _disposed = false;
  bool? _lastConnected;

  /// Starts the periodic cycle after the client is initialized.
  void start() {
    stop();
    client.awaitInitialization.then((_) async {
      if (_disposed) return;
      await onStart();
      if (_disposed) return;
      _timer = Timer.periodic(period, _handleTick);
      // Perform an immediate tick once started.
      await _handleTick(null);
    });
  }

  /// Stops the periodic cycle.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Disposes timers and prevents future ticks.
  void dispose() {
    _disposed = true;
    stop();
  }

  Future<void> _handleTick(dynamic _) async {
    if (_disposed || _isSyncing) return;
    _isSyncing = true;
    try {
      await onTick();
      _emitConnection(true);
    } on TimeoutException catch (e, s) {
      await onTickError(e, s);
      _emitConnection(false);
    } catch (e, s) {
      await onTickError(e, s);
      _emitConnection(false);
    } finally {
      _isSyncing = false;
    }
  }

  /// Hook called once before starting the timer.
  @protected
  Future<void> onStart() async {}

  /// Main periodic task; must be implemented by subclasses.
  @protected
  Future<void> onTick();

  /// Hook to handle errors thrown by [onTick].
  @protected
  Future<void> onTickError(Object error, StackTrace stackTrace) async {}

  /// Hook invoked when connection state changes.
  @protected
  void onConnectionChange(bool connected) {}

  /// Hook invoked when connection is restored after a disconnect.
  @protected
  Future<void> onConnectionRestored() async {}

  void _emitConnection(bool connected) {
    if (_disposed) return;
    onConnectionChange(connected);
    final wasDisconnected = _lastConnected == false;
    _lastConnected = connected;
    reportConnectionState(connected);
    if (connected && wasDisconnected) {
      // Fire and forget; subclasses can override to await if needed.
      onConnectionRestored();
    }
  }
}
