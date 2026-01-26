import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:mongo_dart/mongo_dart.dart';

/// Hybrid WebSocket + REST API server for local_first synchronization.
///
/// This server handles:
/// - Client authentication
/// - Pushing local events to MongoDB
/// - Pulling remote events from MongoDB
/// - Broadcasting events to connected clients via WebSocket
/// - Heartbeat/ping-pong for connection health
/// - REST API endpoints for HTTP clients
///
/// REST API Endpoints:
/// - GET /api/health - Health check
/// - GET /api/repositories - List available repositories
/// - GET /api/events/{repository}?afterSequence={n} - Get events after sequence
/// - GET /api/events/{repository}/{eventId} - Get specific event
/// - POST /api/events/{repository} - Create single event
/// - POST /api/events/{repository}/batch - Create multiple events
///
/// To run this server:
/// ```bash
/// # From the monorepo root (recommended):
/// melos websocket:server
///
/// # Or directly:
/// cd server && dart run websocket_server.dart
/// ```
///
/// The recommended `melos websocket:server` command automatically:
/// - Starts MongoDB with Docker Compose
/// - Configures networking between services
/// - Shows real-time logs
void main() async {
  final server = WebSocketSyncServer();
  await server.start();
}

class WebSocketSyncServer {
  static const logTag = 'WebSocketSyncServer';
  static const port = 8080;

  // Support both Docker (mongodb service name) and local (127.0.0.1)
  static String get mongoConnectionString {
    final host = Platform.environment['MONGO_HOST'] ?? '127.0.0.1';
    final port = Platform.environment['MONGO_PORT'] ?? '27017';
    final db = Platform.environment['MONGO_DB'] ?? 'remote_counter_db';
    return 'mongodb://admin:admin@$host:$port/$db?authSource=admin';
  }

  HttpServer? _httpServer;
  Db? _db;
  final Set<ConnectedClient> _clients = {};

  /// Starts the WebSocket server.
  Future<void> start() async {
    try {
      // Connect to MongoDB
      await _connectToMongo();

      // Start HTTP server for WebSocket upgrade
      final httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _httpServer = httpServer;
      dev.log('WebSocket server listening on ws://0.0.0.0:$port', name: logTag);

      await for (final HttpRequest request in httpServer) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          _handleWebSocketConnection(request);
        } else {
          // Handle REST API requests
          await _handleHttpRequest(request);
        }
      }
    } catch (e, s) {
      dev.log('Error starting server: $e',
          name: logTag, error: e, stackTrace: s);
      rethrow;
    }
  }

  /// Stops the server.
  Future<void> stop() async {
    await _httpServer?.close();
    await _db?.close();
    for (final client in _clients) {
      await client.close();
    }
    _clients.clear();
  }

  /// Connects to MongoDB.
  Future<void> _connectToMongo() async {
    final db = await Db.create(mongoConnectionString);
    _db = db;
    await db.open();
    dev.log('Connected to MongoDB at $mongoConnectionString', name: logTag);

    // Ensure indexes
    await _ensureIndexes();
  }

  /// Ensures MongoDB indexes exist.
  Future<void> _ensureIndexes() async {
    final db = _db;
    if (db == null) return;

    final repos = ['user', 'counter_log', 'session_counter'];

    for (final repoName in repos) {
      final collection = db.collection(repoName);

      try {
        // Index for server sequence-based sync
        await collection.createIndex(keys: {'serverSequence': 1});
        await collection.createIndex(
          keys: {'eventId': 1},
          unique: true,
        );
      } catch (e) {
        dev.log('Failed to create indexes for $repoName: $e', name: logTag);
      }
    }

    // Initialize sequence counters collection
    try {
      final countersCollection = db.collection('_sequence_counters');
      await countersCollection.createIndex(
        keys: {'_id': 1},
        unique: true,
      );
    } catch (e) {
      dev.log('Failed to create sequence counters collection: $e', name: logTag);
    }
  }

  /// Handles new WebSocket connection.
  Future<void> _handleWebSocketConnection(HttpRequest request) async {
    try {
      final webSocket = await WebSocketTransformer.upgrade(request);
      final client = ConnectedClient(
        webSocket: webSocket,
        server: this,
      );

      _clients.add(client);
      dev.log('Client connected. Total clients: ${_clients.length}',
          name: logTag);

      client.listen(
        onDone: () {
          _clients.remove(client);
          dev.log('Client disconnected. Total clients: ${_clients.length}',
              name: logTag);
        },
      );
    } catch (e, s) {
      dev.log('Error handling WebSocket connection: $e',
          name: logTag, error: e, stackTrace: s);
    }
  }

  /// Handles HTTP REST API requests.
  Future<void> _handleHttpRequest(HttpRequest request) async {
    final response = request.response;

    // Set CORS headers
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    response.headers.set('Content-Type', 'application/json');

    try {
      // Handle preflight requests
      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.ok;
        await response.close();
        return;
      }

      final uri = request.uri;
      final path = uri.path;
      final method = request.method;

      dev.log('REST API request: $method $path', name: logTag);

      // Route requests
      if (path == '/api/health') {
        if (method == 'GET') {
          await _handleHealthCheck(request);
        } else {
          _sendError(response, HttpStatus.methodNotAllowed, 'Method not allowed');
        }
      } else if (path == '/api/repositories') {
        if (method == 'GET') {
          await _handleListRepositories(request);
        } else {
          _sendError(response, HttpStatus.methodNotAllowed, 'Method not allowed');
        }
      } else if (path.startsWith('/api/events/')) {
        final pathSegments = uri.pathSegments;
        if (pathSegments.length == 3) {
          // /api/events/{repository}
          final repository = pathSegments[2];
          if (method == 'GET') {
            await _handleGetEvents(request, repository);
          } else if (method == 'POST') {
            await _handlePostEvent(request, repository);
          } else {
            _sendError(response, HttpStatus.methodNotAllowed, 'Method not allowed');
          }
        } else if (pathSegments.length == 4) {
          // /api/events/{repository}/{eventId} or /api/events/{repository}/batch
          final repository = pathSegments[2];
          final identifier = pathSegments[3];

          if (identifier == 'batch' && method == 'POST') {
            await _handlePostEventsBatch(request, repository);
          } else if (method == 'GET') {
            await _handleGetEventById(request, repository, identifier);
          } else {
            _sendError(response, HttpStatus.methodNotAllowed, 'Method not allowed');
          }
        } else {
          _sendError(response, HttpStatus.notFound, 'Endpoint not found');
        }
      } else {
        _sendError(response, HttpStatus.notFound, 'Endpoint not found');
      }
    } catch (e, s) {
      dev.log('Error handling HTTP request: $e',
          name: logTag, error: e, stackTrace: s);
      _sendError(response, HttpStatus.internalServerError, 'Internal server error: $e');
    }
  }

  /// Sends an error response.
  void _sendError(HttpResponse response, int statusCode, String message) {
    try {
      response.statusCode = statusCode;
      response.write(jsonEncode({
        'error': message,
        'statusCode': statusCode,
      }));
      response.close();
    } catch (e) {
      dev.log('Error sending error response: $e', name: logTag);
    }
  }

  /// Handles GET /api/health - Health check endpoint.
  Future<void> _handleHealthCheck(HttpRequest request) async {
    final response = request.response;
    final isDbConnected = _db?.isConnected ?? false;

    response.statusCode = HttpStatus.ok;
    response.write(jsonEncode({
      'status': 'ok',
      'timestamp': DateTime.now().toIso8601String(),
      'mongodb': isDbConnected ? 'connected' : 'disconnected',
      'activeConnections': _clients.length,
    }));
    await response.close();
  }

  /// Handles GET /api/repositories - List available repositories.
  Future<void> _handleListRepositories(HttpRequest request) async {
    final response = request.response;
    final db = _db;

    if (db == null) {
      _sendError(response, HttpStatus.serviceUnavailable, 'Database not connected');
      return;
    }

    try {
      final collections = await db.getCollectionNames();

      // Filter out system collections and internal collections
      final repositories = collections
          .where((name) =>
              name != null &&
              !name.startsWith('_') &&
              !name.endsWith('__events') &&
              !name.startsWith('system.'))
          .cast<String>()
          .toList();

      // Get statistics for each repository
      final stats = <Map<String, dynamic>>[];
      for (final repo in repositories) {
        final collection = db.collection(repo);
        final count = await collection.count();

        // Get max sequence
        final maxSeqDoc = await collection.findOne(
          where.sortBy('serverSequence', descending: true).limit(1),
        );
        final maxSequence = maxSeqDoc?['serverSequence'] as int? ?? 0;

        stats.add({
          'name': repo,
          'eventCount': count,
          'maxSequence': maxSequence,
        });
      }

      response.statusCode = HttpStatus.ok;
      response.write(jsonEncode({
        'repositories': stats,
        'count': repositories.length,
      }));
      await response.close();
    } catch (e) {
      _sendError(response, HttpStatus.internalServerError, 'Failed to list repositories: $e');
    }
  }

  /// Handles GET /api/events/{repository}?afterSequence={n} - Get events after sequence.
  Future<void> _handleGetEvents(HttpRequest request, String repository) async {
    final response = request.response;
    final db = _db;

    if (db == null) {
      _sendError(response, HttpStatus.serviceUnavailable, 'Database not connected');
      return;
    }

    try {
      final afterSequence = request.uri.queryParameters['afterSequence'];
      final limit = int.tryParse(request.uri.queryParameters['limit'] ?? '100') ?? 100;

      final events = await fetchEvents(
        repository,
        afterSequence: afterSequence != null ? int.tryParse(afterSequence) : null,
      );

      // Apply limit
      final limitedEvents = events.take(limit).toList();

      response.statusCode = HttpStatus.ok;
      response.write(jsonEncode({
        'repository': repository,
        'events': limitedEvents,
        'count': limitedEvents.length,
        'hasMore': events.length > limit,
      }));
      await response.close();
    } catch (e) {
      _sendError(response, HttpStatus.internalServerError, 'Failed to fetch events: $e');
    }
  }

  /// Handles GET /api/events/{repository}/{eventId} - Get specific event.
  Future<void> _handleGetEventById(
    HttpRequest request,
    String repository,
    String eventId,
  ) async {
    final response = request.response;
    final db = _db;

    if (db == null) {
      _sendError(response, HttpStatus.serviceUnavailable, 'Database not connected');
      return;
    }

    try {
      final collection = db.collection(repository);
      final event = await collection.findOne(where.eq('eventId', eventId));

      if (event == null) {
        _sendError(response, HttpStatus.notFound, 'Event not found');
        return;
      }

      // Remove MongoDB internal _id
      event.remove('_id');

      response.statusCode = HttpStatus.ok;
      response.write(jsonEncode({
        'repository': repository,
        'event': event,
      }));
      await response.close();
    } catch (e) {
      _sendError(response, HttpStatus.internalServerError, 'Failed to fetch event: $e');
    }
  }

  /// Handles POST /api/events/{repository} - Create single event.
  Future<void> _handlePostEvent(HttpRequest request, String repository) async {
    final response = request.response;

    try {
      // Read request body
      final bodyString = await utf8.decoder.bind(request).join();
      final body = jsonDecode(bodyString) as Map<String, dynamic>;

      // Validate event has required fields
      if (!body.containsKey('eventId')) {
        _sendError(response, HttpStatus.badRequest, 'Missing required field: eventId');
        return;
      }

      // Push event to MongoDB
      await pushEvent(repository, body);

      response.statusCode = HttpStatus.created;
      response.write(jsonEncode({
        'status': 'success',
        'repository': repository,
        'eventId': body['eventId'],
      }));
      await response.close();
    } catch (e) {
      _sendError(response, HttpStatus.internalServerError, 'Failed to create event: $e');
    }
  }

  /// Handles POST /api/events/{repository}/batch - Create multiple events.
  Future<void> _handlePostEventsBatch(HttpRequest request, String repository) async {
    final response = request.response;

    try {
      // Read request body
      final bodyString = await utf8.decoder.bind(request).join();
      final body = jsonDecode(bodyString) as Map<String, dynamic>;

      // Validate events array exists
      if (!body.containsKey('events') || body['events'] is! List) {
        _sendError(response, HttpStatus.badRequest, 'Missing or invalid events array');
        return;
      }

      final events = (body['events'] as List).cast<Map<String, dynamic>>();

      // Validate all events have eventId
      for (final event in events) {
        if (!event.containsKey('eventId')) {
          _sendError(response, HttpStatus.badRequest, 'All events must have eventId field');
          return;
        }
      }

      // Push events to MongoDB
      await pushEventsBatch(repository, events);

      final eventIds = events.map((e) => e['eventId'] as String).toList();

      response.statusCode = HttpStatus.created;
      response.write(jsonEncode({
        'status': 'success',
        'repository': repository,
        'eventIds': eventIds,
        'count': eventIds.length,
      }));
      await response.close();
    } catch (e) {
      _sendError(response, HttpStatus.internalServerError, 'Failed to create events: $e');
    }
  }

  /// Gets the next sequence number for a repository.
  Future<int> _getNextSequence(String repositoryName) async {
    final db = _db;
    if (db == null) {
      throw StateError('MongoDB not connected');
    }

    final countersCollection = db.collection('_sequence_counters');

    final result = await countersCollection.findAndModify(
      query: where.eq('_id', repositoryName),
      update: {r'$inc': {'sequence': 1}},
      returnNew: true,
      upsert: true,
    );

    return result?['sequence'] as int? ?? 1;
  }

  /// Pushes an event to MongoDB.
  Future<void> pushEvent(String repositoryName, Map<String, dynamic> event) async {
    final db = _db;
    if (db == null) {
      throw StateError('MongoDB not connected');
    }

    final collection = db.collection(repositoryName);
    final eventId = event['eventId'];

    try {
      dev.log('Checking if event exists: $eventId in $repositoryName', name: logTag);
      // Check if event already exists
      final existing = await collection.findOne(where.eq('eventId', eventId));

      if (existing != null) {
        // Event already exists, just return (idempotency)
        dev.log('Event $eventId already exists in $repositoryName', name: logTag);
        await _broadcastEvent(repositoryName, existing);
        return;
      }

      dev.log('Getting next sequence for $repositoryName', name: logTag);
      // Get next sequence number
      final serverSequence = await _getNextSequence(repositoryName);

      dev.log('Preparing event with sequence $serverSequence', name: logTag);
      // Add server sequence to event and ensure no _id field
      final eventWithSequence = Map<String, dynamic>.from(event)
        ..remove('_id') // Remove any _id field from client
        ..['serverSequence'] = serverSequence;

      // Ensure all nested maps and values are properly serialized
      final cleanedEvent = _cleanEventForMongo(eventWithSequence);

      dev.log('Inserting event into MongoDB: ${cleanedEvent.keys.toList()}', name: logTag);
      await collection.insertOne(cleanedEvent);

      dev.log('Event $eventId pushed to $repositoryName with sequence $serverSequence', name: logTag);

      // Broadcast to other clients
      await _broadcastEvent(repositoryName, eventWithSequence);
    } catch (e, s) {
      dev.log('Error pushing event: $e', name: logTag, error: e, stackTrace: s);
      rethrow;
    }
  }

  /// Pushes multiple events to MongoDB.
  Future<void> pushEventsBatch(
    String repositoryName,
    List<Map<String, dynamic>> events,
  ) async {
    for (final event in events) {
      await pushEvent(repositoryName, event);
    }
  }

  /// Fetches events from MongoDB after a given sequence number.
  Future<List<Map<String, dynamic>>> fetchEvents(
    String repositoryName, {
    int? afterSequence,
  }) async {
    final db = _db;
    if (db == null) {
      throw StateError('MongoDB not connected');
    }

    final collection = db.collection(repositoryName);
    final selector = afterSequence != null
        ? where.gt('serverSequence', afterSequence)
        : where;

    final cursor = collection.find(selector.sortBy('serverSequence'));
    final results = <Map<String, dynamic>>[];

    await cursor.forEach((doc) {
      final map = Map<String, dynamic>.from(doc)
        ..remove('_id')
        ..putIfAbsent('repository', () => repositoryName);
      results.add(map);
    });

    return results;
  }

  /// Fetches all events from all repositories.
  Future<Map<String, List<Map<String, dynamic>>>> fetchAllEvents() async {
    final repos = ['user', 'counter_log', 'session_counter'];
    final result = <String, List<Map<String, dynamic>>>{};

    for (final repo in repos) {
      result[repo] = await fetchEvents(repo);
    }

    return result;
  }

  /// Broadcasts an event to all connected clients except the sender.
  Future<void> _broadcastEvent(
    String repositoryName,
    Map<String, dynamic> event, {
    ConnectedClient? except,
  }) async {
    for (final client in _clients) {
      if (client != except && client.isAuthenticated) {
        try {
          client.sendMessage({
            'type': 'events',
            'repository': repositoryName,
            'events': [event],
          });
        } catch (e) {
          dev.log('Error broadcasting to client: $e', name: logTag);
        }
      }
    }
  }

  /// Cleans event data for MongoDB insertion by ensuring proper types.
  /// This handles any legacy data or edge cases where types might not match.
  Map<String, dynamic> _cleanEventForMongo(Map<String, dynamic> event) {
    final cleaned = <String, dynamic>{};

    for (final entry in event.entries) {
      final key = entry.key;
      final value = entry.value;

      if (value == null) {
        cleaned[key] = null;
      } else if (value is Map) {
        cleaned[key] = _cleanEventForMongo(value.cast<String, dynamic>());
      } else if (value is List) {
        cleaned[key] = value.map((item) {
          if (item is Map) {
            return _cleanEventForMongo(item.cast<String, dynamic>());
          }
          return item;
        }).toList();
      } else {
        // Keep primitive types as-is
        cleaned[key] = value;
      }
    }

    return cleaned;
  }
}

/// Represents a connected WebSocket client.
class ConnectedClient {
  static const logTag = 'ConnectedClient';

  final WebSocket webSocket;
  final WebSocketSyncServer server;
  bool isAuthenticated = false;
  StreamSubscription? _subscription;

  ConnectedClient({
    required this.webSocket,
    required this.server,
  });

  /// Starts listening for messages from the client.
  void listen({required VoidCallback onDone}) {
    _subscription = webSocket.listen(
      _onMessage,
      onError: (error, stackTrace) {
        dev.log('Client error: $error',
            name: logTag, error: error, stackTrace: stackTrace);
        close();
        onDone();
      },
      onDone: () {
        dev.log('Client connection closed', name: logTag);
        close();
        onDone();
      },
      cancelOnError: false,
    );
  }

  /// Processes a message from the client.
  Future<void> _onMessage(dynamic rawMessage) async {
    try {
      final message = jsonDecode(rawMessage as String) as Map<String, dynamic>;
      final type = message['type'] as String?;

      dev.log('Message received: $type', name: logTag);

      switch (type) {
        case 'auth':
          await _handleAuth(message);
          break;

        case 'ping':
          _handlePing();
          break;

        case 'push_event':
          await _handlePushEvent(message);
          break;

        case 'push_events_batch':
          await _handlePushEventsBatch(message);
          break;

        case 'request_events':
          await _handleRequestEvents(message);
          break;

        case 'request_all_events':
          await _handleRequestAllEvents();
          break;

        case 'events_received':
          _handleEventsReceived(message);
          break;

        default:
          dev.log('Unknown message type: $type', name: logTag);
          sendMessage({
            'type': 'error',
            'message': 'Unknown message type: $type',
          });
      }
    } catch (e, s) {
      dev.log('Error processing message: $e',
          name: logTag, error: e, stackTrace: s);
      sendMessage({
        'type': 'error',
        'message': 'Error processing message: $e',
      });
    }
  }

  /// Handles authentication request.
  Future<void> _handleAuth(Map<String, dynamic> message) async {
    // In a real app, validate the token/credentials here
    isAuthenticated = true;
    dev.log('Client authenticated', name: logTag);

    sendMessage({
      'type': 'auth_success',
    });
  }

  /// Handles ping (heartbeat).
  void _handlePing() {
    sendMessage({'type': 'pong'});
  }

  /// Handles push event request.
  Future<void> _handlePushEvent(Map<String, dynamic> message) async {
    if (!isAuthenticated) {
      sendMessage({
        'type': 'error',
        'message': 'Not authenticated',
      });
      return;
    }

    final repositoryName = message['repository'] as String?;
    final event = message['event'] as Map<String, dynamic>?;

    if (repositoryName == null || event == null) {
      sendMessage({
        'type': 'error',
        'message': 'Missing repository or event',
      });
      return;
    }

    try {
      await server.pushEvent(repositoryName, event);

      // Send acknowledgment
      sendMessage({
        'type': 'ack',
        'eventIds': [event['eventId']],
        'repositories': {
          repositoryName: [event['eventId']],
        },
      });
    } catch (e) {
      sendMessage({
        'type': 'error',
        'message': 'Failed to push event: $e',
      });
    }
  }

  /// Handles push events batch request.
  Future<void> _handlePushEventsBatch(Map<String, dynamic> message) async {
    if (!isAuthenticated) {
      sendMessage({
        'type': 'error',
        'message': 'Not authenticated',
      });
      return;
    }

    final repositoryName = message['repository'] as String?;
    final events = message['events'] as List<dynamic>?;

    if (repositoryName == null || events == null) {
      sendMessage({
        'type': 'error',
        'message': 'Missing repository or events',
      });
      return;
    }

    try {
      dev.log('Received batch of ${events.length} events for $repositoryName', name: logTag);
      final eventList = events.cast<Map<String, dynamic>>();
      for (var i = 0; i < eventList.length; i++) {
        dev.log('Event $i keys: ${eventList[i].keys.toList()}', name: logTag);
      }
      await server.pushEventsBatch(repositoryName, eventList);

      // Send acknowledgment
      final eventIds = eventList.map((e) => e['eventId'] as String).toList();
      sendMessage({
        'type': 'ack',
        'eventIds': eventIds,
        'repositories': {
          repositoryName: eventIds,
        },
      });
    } catch (e) {
      sendMessage({
        'type': 'error',
        'message': 'Failed to push events batch: $e',
      });
    }
  }

  /// Handles request for events after a given sequence number.
  Future<void> _handleRequestEvents(Map<String, dynamic> message) async {
    if (!isAuthenticated) {
      sendMessage({
        'type': 'error',
        'message': 'Not authenticated',
      });
      return;
    }

    final repositoryName = message['repository'] as String?;
    final afterSequence = message['afterSequence'] as int?;

    if (repositoryName == null) {
      sendMessage({
        'type': 'error',
        'message': 'Missing repository',
      });
      return;
    }

    try {
      final events = await server.fetchEvents(
        repositoryName,
        afterSequence: afterSequence,
      );

      if (events.isNotEmpty) {
        sendMessage({
          'type': 'events',
          'repository': repositoryName,
          'events': events,
        });
      }

      sendMessage({
        'type': 'sync_complete',
        'repository': repositoryName,
      });
    } catch (e) {
      sendMessage({
        'type': 'error',
        'message': 'Failed to fetch events: $e',
      });
    }
  }

  /// Handles request for all events from all repositories.
  Future<void> _handleRequestAllEvents() async {
    if (!isAuthenticated) {
      sendMessage({
        'type': 'error',
        'message': 'Not authenticated',
      });
      return;
    }

    try {
      final allEvents = await server.fetchAllEvents();

      for (final entry in allEvents.entries) {
        if (entry.value.isNotEmpty) {
          sendMessage({
            'type': 'events',
            'repository': entry.key,
            'events': entry.value,
          });
        }
      }

      sendMessage({
        'type': 'sync_complete',
      });
    } catch (e) {
      sendMessage({
        'type': 'error',
        'message': 'Failed to fetch all events: $e',
      });
    }
  }

  /// Handles events received confirmation.
  void _handleEventsReceived(Map<String, dynamic> message) {
    final repository = message['repository'];
    final count = message['count'];
    dev.log('Client confirmed receipt of $count events from $repository',
        name: logTag);
  }

  /// Sends a message to the client.
  void sendMessage(Map<String, dynamic> message) {
    try {
      webSocket.add(jsonEncode(message));
    } catch (e) {
      dev.log('Error sending message to client: $e', name: logTag);
    }
  }

  /// Closes the client connection.
  Future<void> close() async {
    await _subscription?.cancel();
    await webSocket.close();
  }
}

typedef VoidCallback = void Function();
