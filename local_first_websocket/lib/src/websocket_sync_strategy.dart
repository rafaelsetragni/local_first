import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:local_first/local_first.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Authentication credentials for WebSocket connection.
class AuthCredentials {
  /// Optional authentication token
  final String? authToken;

  /// Additional headers for authentication
  final JsonMap<String>? headers;

  /// Creates authentication credentials.
  const AuthCredentials({this.authToken, this.headers});
}

/// Real-time bidirectional synchronization strategy using WebSockets.
///
/// Features:
/// - Immediate push when local events are created
/// - Real-time pull when server sends updates
/// - Automatic reconnection on connection failure
/// - Synchronization of missed events during disconnection
/// - Connection state reporting to the UI
///
/// Example:
/// ```dart
/// final wsStrategy = WebSocketSyncStrategy(
///   websocketUrl: 'ws://localhost:8080/sync',
///   headers: {'Authorization': 'Bearer token'},
/// );
///
/// final client = LocalFirstClient(
///   repositories: [userRepository],
///   localStorage: InMemoryLocalFirstStorage(),
///   syncStrategies: [wsStrategy],
/// );
///
/// await client.initialize();
/// await wsStrategy.start();
/// ```
class WebSocketSyncStrategy extends DataSyncStrategy {
  static const logTag = 'WebSocketSyncStrategy';

  /// WebSocket server URL (e.g., 'ws://localhost:8080/sync')
  final String websocketUrl;

  /// Delay before attempting reconnection after connection loss
  final Duration reconnectDelay;

  /// Additional headers to send during WebSocket handshake
  JsonMap<String> _headers;

  /// Interval for sending heartbeat ping messages
  final Duration heartbeatInterval;

  /// Optional authentication token
  String? _authToken;

  /// Optional factory for creating WebSocketChannel (for testing)
  final WebSocketChannel Function(Uri)? _channelFactory;

  /// Callback invoked when authentication fails
  ///
  /// Use this to refresh expired tokens or update credentials.
  /// Return new credentials to retry authentication, or null to skip retry.
  ///
  /// Example:
  /// ```dart
  /// onAuthenticationFailed: () async {
  ///   final newToken = await refreshToken();
  ///   return AuthCredentials(
  ///     authToken: newToken,
  ///     headers: {'Authorization': 'Bearer $newToken'},
  ///   );
  /// }
  /// ```
  final Future<AuthCredentials?> Function()? onAuthenticationFailed;

  /// Callback to build sync filter parameters for a repository.
  ///
  /// Called when requesting events from the server. Return the filter
  /// parameters that the server expects (e.g., timestamp, sequence number).
  /// Return null or empty map to request all events.
  ///
  /// Example with timestamp:
  /// ```dart
  /// onBuildSyncFilter: (repositoryName) async {
  ///   final lastSync = await storage.getLastSync(repositoryName);
  ///   return lastSync != null
  ///     ? {'since': lastSync.toIso8601String()}
  ///     : null;
  /// }
  /// ```
  ///
  /// Example with sequence number:
  /// ```dart
  /// onBuildSyncFilter: (repositoryName) async {
  ///   final lastSeq = await storage.getLastSequence(repositoryName);
  ///   return lastSeq != null
  ///     ? {'afterSequence': lastSeq}
  ///     : null;
  /// }
  /// ```
  final Future<JsonMap<dynamic>?> Function(String repositoryName)
      onBuildSyncFilter;

  /// Callback invoked when events are successfully received and applied.
  ///
  /// Use this to update your sync state (e.g., save latest timestamp or
  /// sequence number). Called after events are applied locally.
  ///
  /// Example with timestamp:
  /// ```dart
  /// onSyncCompleted: (repositoryName, events) async {
  ///   if (events.isEmpty) return;
  ///   final latest = events
  ///     .map((e) => DateTime.parse(e['syncCreatedAt']))
  ///     .reduce((a, b) => a.isAfter(b) ? a : b);
  ///   await storage.saveLastSync(repositoryName, latest);
  /// }
  /// ```
  ///
  /// Example with sequence number:
  /// ```dart
  /// onSyncCompleted: (repositoryName, events) async {
  ///   if (events.isEmpty) return;
  ///   final maxSeq = events
  ///     .map((e) => e['sequence'] as int)
  ///     .reduce((a, b) => a > b ? a : b);
  ///   await storage.saveLastSequence(repositoryName, maxSeq);
  /// }
  /// ```
  final Future<void> Function(
    String repositoryName,
    List<JsonMap<dynamic>> events,
  ) onSyncCompleted;

  WebSocketChannel? _channel;
  StreamSubscription? _messageSubscription;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _pongTimeoutTimer;
  Completer<void>? _authCompleter;
  Completer<void>? _pongCompleter;

  // Tracks known repositories for sync
  final Set<String> _knownRepositories = {};

  // Queue for pending events during disconnection
  final List<LocalFirstEvent> _pendingQueue = [];
  bool _isSyncing = false;

  WebSocketSyncStrategy({
    required this.websocketUrl,
    required this.onBuildSyncFilter,
    required this.onSyncCompleted,
    this.reconnectDelay = const Duration(seconds: 3),
    JsonMap<String>? headers,
    this.heartbeatInterval = const Duration(seconds: 30),
    String? authToken,
    this.onAuthenticationFailed,
    @visibleForTesting WebSocketChannel Function(Uri)? channelFactory,
  })  : _headers = headers ?? {},
        _authToken = authToken,
        _channelFactory = channelFactory;

  /// Current authentication token (read-only)
  String? get authToken => _authToken;

  /// Current headers (read-only)
  JsonMap<String> get headers => Map.unmodifiable(_headers);

  /// Updates the authentication token.
  ///
  /// If the WebSocket is currently connected, it will re-authenticate
  /// with the new token automatically.
  ///
  /// Example:
  /// ```dart
  /// wsStrategy.updateAuthToken('new-token-here');
  /// ```
  void updateAuthToken(String? token) {
    _authToken = token;
    if (_isConnected) {
      _authenticate();
    }
  }

  /// Updates the headers.
  ///
  /// If the WebSocket is currently connected, it will re-authenticate
  /// with the new headers automatically.
  ///
  /// Example:
  /// ```dart
  /// wsStrategy.updateHeaders({
  ///   'Authorization': 'Bearer new-token',
  ///   'X-Custom-Header': 'value',
  /// });
  /// ```
  void updateHeaders(JsonMap<String> headers) {
    _headers = Map.from(headers);
    if (_isConnected) {
      _authenticate();
    }
  }

  /// Updates both the authentication token and headers at once.
  ///
  /// If the WebSocket is currently connected, it will re-authenticate
  /// with the new credentials automatically.
  ///
  /// Example:
  /// ```dart
  /// wsStrategy.updateCredentials(
  ///   authToken: 'new-token',
  ///   headers: {'X-Custom-Header': 'value'},
  /// );
  /// ```
  void updateCredentials({String? authToken, JsonMap<String>? headers}) {
    if (authToken != null) {
      _authToken = authToken;
    }
    if (headers != null) {
      _headers = Map.from(headers);
    }
    if (_isConnected) {
      _authenticate();
    }
  }

  /// Starts WebSocket connection and synchronization.
  ///
  /// This method is non-blocking - it initiates the connection process
  /// in the background and returns immediately. Use the [connectionChanges]
  /// stream to monitor connection status.
  Future<void> start() async {
    dev.log('Starting WebSocket sync strategy', name: logTag);
    await client.awaitInitialization;
    // Start connection in background without blocking
    // ignore: unawaited_futures
    _connect();
  }

  /// Stops synchronization and closes the connection.
  void stop() {
    dev.log('Stopping WebSocket sync strategy', name: logTag);
    _disconnect();
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _pendingQueue.clear();
  }

  /// Disposes of all resources.
  void dispose() {
    stop();
  }

  /// Connects to the WebSocket server.
  Future<void> _connect() async {
    if (_isConnected) return;

    // Report disconnected state at start of connection attempt
    reportConnectionState(false);

    try {
      dev.log('Connecting to WebSocket: $websocketUrl', name: logTag);

      final uri = Uri.parse(websocketUrl);
      final channel =
          _channelFactory?.call(uri) ?? WebSocketChannel.connect(uri);
      _channel = channel;

      // Wait for connection with timeout
      await channel.ready.timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () {
          throw TimeoutException('WebSocket connection timeout');
        },
      );

      _isConnected = true;
      reportConnectionState(true);
      dev.log('WebSocket connected', name: logTag);

      // Listen for messages from server
      _messageSubscription = channel.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDisconnect,
        cancelOnError: false,
      );

      // Start heartbeat to keep connection alive
      _startHeartbeat();

      // Authenticate and sync initial state
      await _authenticate();
      await _syncInitialState();

      // Send pending events
      await _flushPendingQueue();
    } catch (e, s) {
      dev.log(
        'Error connecting to WebSocket: $e',
        name: logTag,
        error: e,
        stackTrace: s,
      );
      // Clean up failed connection attempt
      _channel?.sink.close();
      _channel = null;
      _scheduleReconnect();
    }
  }

  /// Disconnects from the server.
  void _disconnect() {
    _isConnected = false;
    reportConnectionState(false);
    _messageSubscription?.cancel();
    _messageSubscription = null;
    _channel?.sink.close();
    _channel = null;
    _heartbeatTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _pongTimeoutTimer = null;
    _pongCompleter = null;
  }

  /// Schedules automatic reconnection.
  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;

    dev.log(
      'Scheduling reconnection in ${reconnectDelay.inSeconds}s',
      name: logTag,
    );

    _reconnectTimer = Timer(reconnectDelay, () {
      _reconnectTimer = null;
      _connect();
    });
  }

  /// Processes messages received from the server.
  void _onMessage(dynamic rawMessage) async {
    try {
      // Any message from server means connection is alive - cancel pong timeout
      _pongTimeoutTimer?.cancel();
      _pongTimeoutTimer = null;
      _pongCompleter?.complete();
      _pongCompleter = null;

      final message = jsonDecode(rawMessage as String) as JsonMap<dynamic>;
      final type = message['type'] as String?;

      dev.log('Message received: $type', name: logTag);

      switch (type) {
        case 'auth_success':
          dev.log('Authentication successful', name: logTag);
          _authCompleter?.complete();
          break;

        case 'events':
          await _handleRemoteEvents(message);
          break;

        case 'ack':
          await _handleAcknowledgment(message);
          break;

        case 'sync_complete':
          dev.log('Initial synchronization complete', name: logTag);
          break;

        case 'ping':
          // Server sent ping, respond with pong
          try {
            _sendMessage({'type': 'pong'});
          } on StateError catch (e) {
            // Connection lost while responding
            _handleConnectionLoss('ping response', e);
          }
          break;

        case 'pong':
          // Heartbeat response (already handled in _onMessage)
          break;

        case 'error':
          final error = message['message'] ?? 'Unknown error';
          dev.log('Server error: $error', name: logTag);
          // If authentication fails, complete the auth completer with error
          if (_authCompleter != null && !_authCompleter!.isCompleted) {
            _authCompleter!.completeError(error);
          }
          break;

        default:
          dev.log('Unknown message type: $type', name: logTag);
      }
    } catch (e, s) {
      dev.log(
        'Error processing message: $e',
        name: logTag,
        error: e,
        stackTrace: s,
      );
    }
  }

  /// Processes remote events received (PULL).
  Future<void> _handleRemoteEvents(JsonMap<dynamic> message) async {
    final repositoryName = message['repository'] as String?;
    final events = message['events'] as List<dynamic>?;

    if (repositoryName == null || events == null || events.isEmpty) {
      return;
    }

    dev.log(
      'Applying ${events.length} remote events for $repositoryName',
      name: logTag,
    );

    // Track this repository
    _knownRepositories.add(repositoryName);

    final remoteChanges = events
        .cast<JsonMap<dynamic>>()
        .map((e) => JsonMap.from(e))
        .toList();

    // Apply changes locally
    await pullChangesToLocal(
      repositoryName: repositoryName,
      remoteChanges: remoteChanges,
    );

    // Notify sync completion via callback
    try {
      await onSyncCompleted(repositoryName, remoteChanges);
    } catch (e, s) {
      dev.log(
        'Error in onSyncCompleted callback: $e',
        name: logTag,
        error: e,
        stackTrace: s,
      );
    }

    // Send confirmation to server
    try {
      _sendMessage({
        'type': 'events_received',
        'repository': repositoryName,
        'count': events.length,
      });
    } on StateError catch (e) {
      // Connection lost while confirming - server will resend events
      _handleConnectionLoss('events confirmation', e);
    }
  }

  /// Processes acknowledgment of sent events.
  Future<void> _handleAcknowledgment(JsonMap<dynamic> message) async {
    final eventIds = (message['eventIds'] as List<dynamic>?)
        ?.cast<String>()
        .toSet();

    if (eventIds == null || eventIds.isEmpty) return;

    dev.log('Received ACK for ${eventIds.length} events', name: logTag);

    // Remove from pending queue
    _pendingQueue.removeWhere((event) => eventIds.contains(event.eventId));

    // Mark events as synced
    final repositories = message['repositories'] as JsonMap<dynamic>?;
    if (repositories != null) {
      for (final entry in repositories.entries) {
        final repoName = entry.key;
        final repoEventIds = (entry.value as List<dynamic>).cast<String>();

        final events = await getPendingEvents(repositoryName: repoName);
        final syncedEvents = events
            .where((e) => repoEventIds.contains(e.eventId))
            .toList();

        if (syncedEvents.isNotEmpty) {
          await markEventsAsSynced(syncedEvents);
        }
      }
    }
  }

  /// Implementation of push: sends local event to the server.
  @override
  Future<SyncStatus> onPushToRemote(LocalFirstEvent localData) async {
    if (!_isConnected) {
      // Add to queue if disconnected
      _pendingQueue.add(localData);
      dev.log(
        'Event added to queue (disconnected): ${localData.eventId}',
        name: logTag,
      );
      return SyncStatus.pending;
    }

    try {
      // Send event via WebSocket
      _sendMessage({
        'type': 'push_event',
        'repository': localData.repositoryName,
        'event': localData.toJson(),
      });

      dev.log('Event sent: ${localData.eventId}', name: logTag);

      // Return pending until server ACK
      return SyncStatus.pending;
    } on StateError catch (e) {
      // Connection was lost between the check and the send
      _handleConnectionLoss('push event', e);
      _pendingQueue.add(localData);
      return SyncStatus.pending;
    } catch (e, s) {
      // Other unexpected errors
      dev.log(
        'Unexpected error sending event: $e',
        name: logTag,
        error: e,
        stackTrace: s,
      );
      _pendingQueue.add(localData);
      return SyncStatus.failed;
    }
  }

  /// Sends a message via WebSocket.
  void _sendMessage(JsonMap<dynamic> message) {
    final channel = _channel;
    if (channel == null || !_isConnected) {
      throw StateError('WebSocket not connected');
    }

    // Convert DateTime objects to ISO 8601 strings
    final jsonSafeMessage = _convertToJsonSafe(message);
    channel.sink.add(jsonEncode(jsonSafeMessage));
  }

  /// Converts a map to JSON-safe format by converting DateTime to ISO 8601 strings.
  dynamic _convertToJsonSafe(dynamic value) {
    if (value == null) {
      return null;
    } else if (value is DateTime) {
      return value.toIso8601String();
    } else if (value is Map) {
      return value.map((key, val) => MapEntry(key, _convertToJsonSafe(val)));
    } else if (value is List) {
      return value.map(_convertToJsonSafe).toList();
    } else {
      return value;
    }
  }

  /// Authenticates with the server.
  Future<void> _authenticate() async {
    // Always send authentication (server requires it even without credentials)
    _authCompleter = Completer<void>();

    try {
      _sendMessage({
        'type': 'auth',
        if (_authToken != null) 'token': _authToken,
        ..._headers,
      });

      // Wait for server response (with timeout)
      await _authCompleter!.future.timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () {
          dev.log('Authentication timeout', name: logTag);
          throw TimeoutException('Authentication timeout');
        },
      );
    } on StateError catch (e) {
      // Connection lost during auth - trigger reconnection
      _handleConnectionLoss('authentication', e);

      // Try to refresh credentials if callback is provided
      if (onAuthenticationFailed != null) {
        try {
          final newCredentials = await onAuthenticationFailed!();
          if (newCredentials != null) {
            // Update credentials for next connection attempt
            if (newCredentials.authToken != null) {
              _authToken = newCredentials.authToken;
            }
            if (newCredentials.headers != null) {
              _headers = Map.from(newCredentials.headers!);
            }
            dev.log(
              'Credentials refreshed for next connection',
              name: logTag,
            );
          }
        } catch (e, s) {
          dev.log(
            'Error refreshing credentials: $e',
            name: logTag,
            error: e,
            stackTrace: s,
          );
        }
      }
    } finally {
      _authCompleter = null;
    }
  }

  /// Synchronizes initial state after connection.
  Future<void> _syncInitialState() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      dev.log('Synchronizing initial state', name: logTag);

      // If we have known repositories, request events for each with filters
      if (_knownRepositories.isNotEmpty) {
        for (final repositoryName in _knownRepositories) {
          try {
            // Build sync filter via callback
            JsonMap<dynamic>? filterParams;
            try {
              filterParams = await onBuildSyncFilter(repositoryName);
            } catch (e, s) {
              dev.log(
                'Error in onBuildSyncFilter callback for $repositoryName: $e',
                name: logTag,
                error: e,
                stackTrace: s,
              );
            }

            // Build request message
            final message = <String, dynamic>{};
            if (filterParams == null || filterParams.isEmpty) {
              // Request all events for this repository
              message['type'] = 'request_all_events';
              message['repository'] = repositoryName;
            } else {
              // Request filtered events
              message['type'] = 'request_events';
              message['repository'] = repositoryName;
              message.addAll(filterParams);
            }

            // Limit counter_log to 5 most recent events
            if (repositoryName == 'counter_log') {
              message['limit'] = 5;
            }

            _sendMessage(message);
          } on StateError catch (e) {
            // Connection lost during sync
            _handleConnectionLoss('request events for $repositoryName', e);
            return;
          }
        }
      } else {
        // First connection - request all events from server
        try {
          _sendMessage({'type': 'request_all_events'});
        } on StateError catch (e) {
          // Connection lost during sync
          _handleConnectionLoss('request all events', e);
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// Sends all pending events in the queue.
  Future<void> _flushPendingQueue() async {
    if (_pendingQueue.isEmpty) return;

    dev.log('Sending ${_pendingQueue.length} pending events', name: logTag);

    // Group events by repository
    final eventsByRepo = <String, List<LocalFirstEvent>>{};
    for (final event in _pendingQueue) {
      // Track repository
      _knownRepositories.add(event.repositoryName);
      eventsByRepo.putIfAbsent(event.repositoryName, () => []).add(event);
    }

    // Send in batches
    for (final entry in eventsByRepo.entries) {
      try {
        _sendMessage({
          'type': 'push_events_batch',
          'repository': entry.key,
          'events': entry.value.map((e) => e.toJson()).toList(),
        });
      } on StateError catch (e) {
        // Connection lost while flushing - events remain in queue
        _handleConnectionLoss('flush pending queue for ${entry.key}', e);
        return; // Stop trying to send more batches
      } catch (e, s) {
        // Other unexpected errors - log and continue with next batch
        dev.log(
          'Unexpected error sending event batch: $e',
          name: logTag,
          error: e,
          stackTrace: s,
        );
      }
    }

    // Don't clear queue here - wait for server ACK
  }

  /// Starts periodic heartbeat.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (_isConnected) {
        _sendHeartbeat();
      }
    });
  }

  /// Sends a heartbeat ping and waits for pong response.
  void _sendHeartbeat() async {
    try {
      // Create completer for pong response
      _pongCompleter = Completer<void>();

      // Send ping
      _sendMessage({'type': 'ping'});

      // Set timeout for pong response
      _pongTimeoutTimer = Timer(const Duration(seconds: 2), () {
        if (_pongCompleter != null && !_pongCompleter!.isCompleted) {
          dev.log('Pong timeout - connection appears dead', name: logTag);
          _handleConnectionLoss('pong timeout');
        }
      });
    } on StateError catch (e) {
      // Connection lost - trigger disconnect and reconnection
      _handleConnectionLoss('heartbeat', e);
    }
  }

  /// Handles connection errors.
  void _onError(dynamic error, [StackTrace? stackTrace]) {
    dev.log(
      'WebSocket error: $error',
      name: logTag,
      error: error,
      stackTrace: stackTrace,
    );
    _disconnect();
    _scheduleReconnect();
  }

  /// Handles disconnection.
  void _onDisconnect() {
    dev.log('WebSocket disconnected', name: logTag);
    _disconnect();
    _scheduleReconnect();
  }

  /// Handles connection loss detected during operations.
  ///
  /// This is called when we detect the connection is lost while trying
  /// to send messages (StateError from sink.add).
  void _handleConnectionLoss(String operation, [dynamic error]) {
    if (!_isConnected) return; // Already handling disconnection

    dev.log(
      'Connection lost during $operation',
      name: logTag,
      error: error,
    );
    _disconnect();
    _scheduleReconnect();
  }

}
