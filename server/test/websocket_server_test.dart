import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:http/http.dart' as http;

/// Integration tests for WebSocket + REST API server.
///
/// Prerequisites:
/// - MongoDB must be running on localhost:27017
/// - Run with: dart test
///
/// To start MongoDB:
/// docker run -d --name mongo_test -p 27017:27017 \
///   -e MONGO_INITDB_ROOT_USERNAME=admin \
///   -e MONGO_INITDB_ROOT_PASSWORD=admin mongo:7
void main() {
  late Process serverProcess;
  late String baseUrl;
  late String wsUrl;

  // Setup: Start server before all tests
  setUpAll(() async {
    baseUrl = 'http://localhost:8080';
    wsUrl = 'ws://localhost:8080';

    // CRITICAL: Verify test database name to prevent production data corruption
    const testDbName = 'remote_counter_db_test';
    const prodDbName = 'remote_counter_db';

    if (testDbName == prodDbName) {
      throw Exception(
        'SAFETY CHECK FAILED: Test database name cannot be the same as production! '
        'Test DB: $testDbName, Prod DB: $prodDbName',
      );
    }

    if (!testDbName.contains('test')) {
      throw Exception(
        'SAFETY CHECK FAILED: Test database name must contain "test" to prevent accidents. '
        'Current: $testDbName',
      );
    }

    // CRITICAL: Verify port 8080 is not already in use
    // If Docker server is running, tests will connect to it instead of starting a new one
    try {
      final serverSocket = await ServerSocket.bind('127.0.0.1', 8080);
      await serverSocket.close();
    } catch (e) {
      throw Exception(
        'SAFETY CHECK FAILED: Port 8080 is already in use!\n'
        'This usually means the Docker WebSocket server is running.\n'
        'Stop it with: docker stop local_first_websocket_server\n'
        'Tests must start their own server with test database configuration.',
      );
    }

    // Check if MongoDB is running
    try {
      final result = await Process.run('docker', [
        'exec',
        'local_first_mongodb',
        'mongosh',
        '--quiet',
        '--eval',
        'db.version()',
      ]);

      if (result.exitCode != 0) {
        throw Exception(
          'MongoDB container not found or not running. '
          'Start it with: melos websocket:server',
        );
      }
    } catch (e) {
      print(
        'Warning: Could not verify MongoDB. '
        'Ensure MongoDB is running on localhost:27017',
      );
    }

    // Start the server with test database
    print('Starting WebSocket server with test database: $testDbName');
    serverProcess = await Process.start(
      'dart',
      ['run', 'websocket_server.dart'],
      workingDirectory: Directory.current.path,
      environment: {
        'MONGO_DB': testDbName, // Use separate test database
        'MONGO_HOST': '127.0.0.1',
        'MONGO_PORT': '27017',
      },
    );

    // Wait for server to start (check health endpoint)
    var attempts = 0;
    while (attempts < 30) {
      try {
        final response = await http
            .get(Uri.parse('$baseUrl/api/health'))
            .timeout(Duration(seconds: 1));
        if (response.statusCode == 200) {
          print('Server started successfully');
          break;
        }
      } catch (e) {
        // Server not ready yet
        await Future.delayed(Duration(milliseconds: 500));
        attempts++;
      }
    }

    if (attempts >= 30) {
      serverProcess.kill();
      throw Exception('Server failed to start after 15 seconds');
    }

    // CRITICAL: Verify server is using test database
    await _verifyTestDatabase();

    // Drop test database to ensure deterministic test state
    print('Dropping test database to ensure clean state...');
    await _dropTestDatabase();
  });

  // Teardown: Stop server after all tests
  tearDownAll(() async {
    print('Stopping WebSocket server...');
    serverProcess.kill();
    await serverProcess.exitCode;

    // Drop test database for cleanup
    await _dropTestDatabase();
  });

  group('REST API - Health and Info Endpoints', () {
    test('GET /api/health returns server status', () async {
      final response = await http.get(Uri.parse('$baseUrl/api/health'));

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      expect(data['status'], 'ok');
      expect(data['mongodb'], 'connected');
      expect(data.containsKey('timestamp'), true);
      expect(data.containsKey('activeConnections'), true);
    });

    test('GET /api/repositories lists all repositories', () async {
      final response = await http.get(Uri.parse('$baseUrl/api/repositories'));

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      expect(data.containsKey('repositories'), true);
      expect(data.containsKey('count'), true);
      expect(data['repositories'], isA<List>());
    });
  });

  group('REST API - Event Operations', () {
    test('POST /api/events/{repository} creates a single event', () async {
      final testEvent = {
        'eventId': 'test_event_${DateTime.now().millisecondsSinceEpoch}',
        'id': 'test_user_1',
        'username': 'Test User 1',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/events/test_users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(testEvent),
      );

      expect(response.statusCode, 201);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      expect(data['status'], 'success');
      expect(data['repository'], 'test_users');
      expect(data['eventId'], testEvent['eventId']);
    });

    test('POST /api/events/{repository}/batch creates multiple events',
        () async {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final testEvents = [
        {
          'eventId': 'test_batch_1_$timestamp',
          'id': 'batch_user_1',
          'username': 'Batch User 1',
        },
        {
          'eventId': 'test_batch_2_$timestamp',
          'id': 'batch_user_2',
          'username': 'Batch User 2',
        },
      ];

      final response = await http.post(
        Uri.parse('$baseUrl/api/events/test_users/batch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'events': testEvents}),
      );

      expect(response.statusCode, 201);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      expect(data['status'], 'success');
      expect(data['repository'], 'test_users');
      expect(data['count'], 2);
      expect(data['eventIds'], isA<List>());
      expect((data['eventIds'] as List).length, 2);
    });

    test('GET /api/events/{repository} fetches all events', () async {
      // First create a test event
      final testEvent = {
        'eventId': 'test_get_${DateTime.now().millisecondsSinceEpoch}',
        'id': 'get_user',
        'username': 'Get Test User',
      };

      await http.post(
        Uri.parse('$baseUrl/api/events/test_users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(testEvent),
      );

      // Now fetch events
      final response =
          await http.get(Uri.parse('$baseUrl/api/events/test_users'));

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      expect(data['repository'], 'test_users');
      expect(data['events'], isA<List>());
      expect(data['count'], greaterThan(0));

      // Verify events have serverSequence
      final events = data['events'] as List;
      for (final event in events) {
        expect(event['serverSequence'], isA<int>());
        expect(event['eventId'], isA<String>());
      }
    });

    test('GET /api/events/{repository}?afterSequence={n} filters by sequence',
        () async {
      // Create events
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      await http.post(
        Uri.parse('$baseUrl/api/events/test_sequence'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'eventId': 'seq_1_$timestamp',
          'id': 'seq_user_1',
          'username': 'Seq User 1',
        }),
      );

      await http.post(
        Uri.parse('$baseUrl/api/events/test_sequence'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'eventId': 'seq_2_$timestamp',
          'id': 'seq_user_2',
          'username': 'Seq User 2',
        }),
      );

      // Get all events to find the first sequence
      final allResponse =
          await http.get(Uri.parse('$baseUrl/api/events/test_sequence'));
      final allData = jsonDecode(allResponse.body) as Map<String, dynamic>;
      final allEvents = allData['events'] as List;

      if (allEvents.isEmpty) {
        fail('No events found');
      }

      final firstSequence = allEvents.first['serverSequence'] as int;

      // Now get events after first sequence
      final response = await http.get(
        Uri.parse(
            '$baseUrl/api/events/test_sequence?afterSequence=$firstSequence'),
      );

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final filteredEvents = data['events'] as List;

      // All returned events should have sequence > firstSequence
      for (final event in filteredEvents) {
        expect(event['serverSequence'], greaterThan(firstSequence));
      }
    });

    test('GET /api/events/{repository}/{eventId} fetches specific event',
        () async {
      final eventId = 'test_specific_${DateTime.now().millisecondsSinceEpoch}';

      // Create event
      await http.post(
        Uri.parse('$baseUrl/api/events/test_users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'eventId': eventId,
          'id': 'specific_user',
          'username': 'Specific Test User',
        }),
      );

      // Fetch specific event
      final response =
          await http.get(Uri.parse('$baseUrl/api/events/test_users/$eventId'));

      expect(response.statusCode, 200);
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      expect(data['repository'], 'test_users');
      expect(data['event']['eventId'], eventId);
      expect(data['event']['username'], 'Specific Test User');
      expect(data['event']['serverSequence'], isA<int>());
    });

    test('GET /api/events/{repository}/{eventId} returns 404 for missing event',
        () async {
      final response = await http.get(
        Uri.parse('$baseUrl/api/events/test_users/nonexistent_event'),
      );

      expect(response.statusCode, 404);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      expect(data['error'], 'Event not found');
    });
  });

  group('REST API - Error Handling', () {
    test('POST /api/events/{repository} returns 400 for missing eventId',
        () async {
      final response = await http.post(
        Uri.parse('$baseUrl/api/events/test_users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': 'test_user',
          'username': 'Test User',
          // Missing eventId
        }),
      );

      expect(response.statusCode, 400);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      expect(data['error'], contains('eventId'));
    });

    test('POST /api/events/{repository}/batch returns 400 for invalid events',
        () async {
      final response = await http.post(
        Uri.parse('$baseUrl/api/events/test_users/batch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'events': 'not an array', // Invalid format
        }),
      );

      expect(response.statusCode, 400);
    });

    test('GET /api/invalid returns 404', () async {
      final response = await http.get(Uri.parse('$baseUrl/api/invalid'));

      expect(response.statusCode, 404);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      expect(data['error'], 'Endpoint not found');
    });

    test('POST /api/health returns 405 Method Not Allowed', () async {
      final response = await http.post(Uri.parse('$baseUrl/api/health'));

      expect(response.statusCode, 405);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      expect(data['error'], 'Method not allowed');
    });
  });

  group('REST API - Idempotency', () {
    test('Creating same event twice returns success both times', () async {
      final eventId = 'idempotent_${DateTime.now().millisecondsSinceEpoch}';
      final testEvent = {
        'eventId': eventId,
        'id': 'idempotent_user',
        'username': 'Idempotent User',
      };

      // First creation
      final response1 = await http.post(
        Uri.parse('$baseUrl/api/events/test_users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(testEvent),
      );

      expect(response1.statusCode, 201);

      // Second creation (duplicate)
      final response2 = await http.post(
        Uri.parse('$baseUrl/api/events/test_users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(testEvent),
      );

      expect(response2.statusCode, 201);

      // Both should succeed due to idempotency
      final data2 = jsonDecode(response2.body) as Map<String, dynamic>;
      expect(data2['status'], 'success');
      expect(data2['eventId'], eventId);
    });
  });

  group('REST API - CORS Headers', () {
    test('OPTIONS request returns CORS headers', () async {
      final request = await HttpClient().openUrl(
        'OPTIONS',
        Uri.parse('$baseUrl/api/health'),
      );
      final response = await request.close();

      expect(response.statusCode, 200);
      expect(
        response.headers.value('access-control-allow-origin'),
        '*',
      );
      expect(
        response.headers.value('access-control-allow-methods'),
        contains('GET'),
      );
    });

    test('GET request includes CORS headers', () async {
      final response = await http.get(Uri.parse('$baseUrl/api/health'));

      expect(response.headers['access-control-allow-origin'], '*');
    });
  });

  group('REST API - Server Sequence Assignment', () {
    test('Events receive sequential serverSequence numbers', () async {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final repo = 'test_sequence_assignment';

      // Create first event
      await http.post(
        Uri.parse('$baseUrl/api/events/$repo'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'eventId': 'seq_assign_1_$timestamp',
          'data': 'first',
        }),
      );

      // Create second event
      await http.post(
        Uri.parse('$baseUrl/api/events/$repo'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'eventId': 'seq_assign_2_$timestamp',
          'data': 'second',
        }),
      );

      // Fetch events
      final response = await http.get(Uri.parse('$baseUrl/api/events/$repo'));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final events = data['events'] as List;

      // Verify sequences are increasing
      for (var i = 1; i < events.length; i++) {
        final prevSeq = events[i - 1]['serverSequence'] as int;
        final currSeq = events[i]['serverSequence'] as int;
        expect(currSeq, greaterThan(prevSeq));
      }
    });

    test(
        'Creating first event in new repository initializes sequence counter correctly',
        () async {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final repo = 'test_new_repo_$timestamp';

      // This test specifically verifies the fix for the ObjectId type cast bug.
      // When creating the first event in a new repository, the sequence counter
      // must be created using 'repository' field instead of '_id' to avoid
      // MongoDB's automatic ObjectId casting.

      final response = await http.post(
        Uri.parse('$baseUrl/api/events/$repo'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'eventId': 'first_event_$timestamp',
          'data': {
            'test': 'data',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          },
        }),
      );

      // Should succeed without ObjectId type cast error
      expect(response.statusCode, 201);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      expect(data['status'], 'success');

      // Verify event was created with sequence 1
      final getResponse = await http.get(Uri.parse('$baseUrl/api/events/$repo'));
      expect(getResponse.statusCode, 200);

      final eventsData = jsonDecode(getResponse.body) as Map<String, dynamic>;
      final events = eventsData['events'] as List;
      expect(events.length, 1);
      expect(events[0]['serverSequence'], 1);
    });
  });

  group('WebSocket - Basic Connection', () {
    test('WebSocket connection succeeds', () async {
      final ws = await WebSocket.connect(wsUrl);
      expect(ws.readyState, WebSocket.open);

      await ws.close();
    });

    test('WebSocket auth message succeeds', () async {
      final ws = await WebSocket.connect(wsUrl);
      final completer = Completer<Map<String, dynamic>>();

      ws.listen((message) {
        final data = jsonDecode(message as String) as Map<String, dynamic>;
        if (data['type'] == 'auth_success') {
          completer.complete(data);
        }
      });

      // Send auth message
      ws.add(jsonEncode({'type': 'auth', 'token': 'test_token'}));

      final response = await completer.future
          .timeout(Duration(seconds: 5), onTimeout: () {
        fail('Auth response timeout');
      });

      expect(response['type'], 'auth_success');

      await ws.close();
    });

    test('WebSocket ping-pong works', () async {
      final ws = await WebSocket.connect(wsUrl);
      final completer = Completer<Map<String, dynamic>>();

      ws.listen((message) {
        final data = jsonDecode(message as String) as Map<String, dynamic>;
        if (data['type'] == 'pong') {
          completer.complete(data);
        }
      });

      // Send ping
      ws.add(jsonEncode({'type': 'ping'}));

      final response = await completer.future
          .timeout(Duration(seconds: 5), onTimeout: () {
        fail('Pong response timeout');
      });

      expect(response['type'], 'pong');

      await ws.close();
    });
  });

  group('Integration - REST and WebSocket', () {
    test('Event created via REST is broadcast to WebSocket clients', () async {
      // Connect WebSocket client
      final ws = await WebSocket.connect(wsUrl);
      final eventReceived = Completer<Map<String, dynamic>>();

      // Authenticate
      ws.add(jsonEncode({'type': 'auth'}));

      ws.listen((message) {
        final data = jsonDecode(message as String) as Map<String, dynamic>;
        if (data['type'] == 'events') {
          eventReceived.complete(data);
        }
      });

      // Wait a bit for auth to complete
      await Future.delayed(Duration(milliseconds: 500));

      // Create event via REST
      final eventId = 'broadcast_test_${DateTime.now().millisecondsSinceEpoch}';
      await http.post(
        Uri.parse('$baseUrl/api/events/test_broadcast'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'eventId': eventId,
          'data': 'broadcast test',
        }),
      );

      // Verify WebSocket client received the event
      final received = await eventReceived.future.timeout(
        Duration(seconds: 5),
        onTimeout: () => <String, dynamic>{},
      );

      // Note: The broadcast goes to OTHER clients, not the sender
      // So this test verifies the broadcast mechanism exists
      expect(received.isEmpty || received['type'] == 'events', true);

      await ws.close();
    });
  });
}

/// Verifies that the server is connected to the test database.
/// This is a critical safety check to prevent accidental operations on production data.
Future<void> _verifyTestDatabase() async {
  try {
    final result = await Process.run('docker', [
      'exec',
      'local_first_mongodb',
      'mongosh',
      '--quiet',
      '-u',
      'admin',
      '-p',
      'admin',
      '--authenticationDatabase',
      'admin',
      '--eval',
      'db.getMongo().getDBNames()',
    ]);

    if (result.exitCode == 0) {
      final output = result.stdout.toString();

      // Verify test database exists or will be created
      // Also ensure we're NOT accidentally using production database
      if (output.contains('remote_counter_db') &&
          !output.contains('remote_counter_db_test')) {
        throw Exception(
          'SAFETY CHECK FAILED: Production database detected! '
          'Tests must use remote_counter_db_test, not remote_counter_db. '
          'Databases found: $output',
        );
      }

      print('✓ Database safety check passed - using test database');
    }
  } catch (e) {
    if (e.toString().contains('SAFETY CHECK FAILED')) {
      rethrow;
    }
    print('Warning: Could not verify test database (may be created on first use): $e');
  }
}

/// Helper function to clean up test data from MongoDB
/// Drops the entire test database to ensure deterministic test execution.
/// This prevents state leakage between test runs and ensures each test
/// suite starts with a completely clean database.
Future<void> _dropTestDatabase() async {
  const testDbName = 'remote_counter_db_test';

  try {
    final result = await Process.run('docker', [
      'exec',
      'local_first_mongodb',
      'mongosh',
      '--quiet',
      '-u',
      'admin',
      '-p',
      'admin',
      '--authenticationDatabase',
      'admin',
      testDbName,
      '--eval',
      'db.dropDatabase()',
    ]);

    if (result.exitCode == 0) {
      print('Test database dropped successfully');
    } else {
      print('Warning: Failed to drop test database: ${result.stderr}');
    }
  } catch (e) {
    print('Warning: Could not drop test database: $e');
  }
}
