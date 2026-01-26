import 'dart:convert';
import 'dart:io';

/// Example REST API client demonstrating how to interact with the server.
///
/// This example shows:
/// - Health check
/// - Listing repositories
/// - Fetching events with server sequence filtering
/// - Creating single events
/// - Creating batch events
///
/// To run this example:
/// 1. Start the server: `melos server:start`
/// 2. Run this client: `dart run rest_client_example.dart`
void main() async {
  final client = RestApiClient('http://localhost:8080');

  print('=== REST API Client Example ===\n');

  try {
    // 1. Health check
    print('1. Checking server health...');
    final health = await client.healthCheck();
    print('   Server status: ${health['status']}');
    print('   MongoDB: ${health['mongodb']}');
    print('   Active connections: ${health['activeConnections']}\n');

    // 2. List repositories
    print('2. Listing repositories...');
    final repos = await client.listRepositories();
    print('   Found ${repos['count']} repositories:');
    for (final repo in repos['repositories'] as List) {
      print('   - ${repo['name']}: ${repo['eventCount']} events '
          '(maxSequence: ${repo['maxSequence']})');
    }
    print('');

    // 3. Create a test event
    print('3. Creating a test user event...');
    final testEventId = 'evt_rest_test_${DateTime.now().millisecondsSinceEpoch}';
    final createResult = await client.createEvent('user', {
      'eventId': testEventId,
      'id': 'rest_test_user',
      'username': 'REST Test User',
      'avatarUrl': 'https://api.dicebear.com/7.x/avataaars/svg?seed=RESTTest',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    print('   Created event: ${createResult['eventId']}');
    print('   Status: ${createResult['status']}\n');

    // 4. Fetch the created event
    print('4. Fetching the created event...');
    final fetchedEvent = await client.getEventById('user', testEventId);
    print('   Event ID: ${fetchedEvent['event']['eventId']}');
    print('   Server Sequence: ${fetchedEvent['event']['serverSequence']}');
    print('   Username: ${fetchedEvent['event']['username']}\n');

    // 5. Get all events from user repository
    print('5. Fetching all user events...');
    final allEvents = await client.getEvents('user');
    print('   Total events: ${allEvents['count']}');
    print('   Has more: ${allEvents['hasMore']}\n');

    // 6. Get events after a specific sequence
    if ((allEvents['count'] as int) > 0) {
      final events = allEvents['events'] as List;
      if (events.isNotEmpty) {
        final firstEvent = events.first as Map<String, dynamic>;
        final firstSequence = firstEvent['serverSequence'] as int;

        print('6. Fetching events after sequence $firstSequence...');
        final afterEvents = await client.getEvents(
          'user',
          afterSequence: firstSequence,
        );
        print('   Events after sequence $firstSequence: ${afterEvents['count']}\n');
      }
    }

    // 7. Create batch events
    print('7. Creating batch events for counter_log...');
    final batchResult = await client.createEventsBatch('counter_log', [
      {
        'eventId': 'evt_log_rest_1_${DateTime.now().millisecondsSinceEpoch}',
        'id': 'log_rest_1',
        'username': 'rest_test_user',
        'sessionId': 'sess_rest_test',
        'increment': 1,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
      {
        'eventId': 'evt_log_rest_2_${DateTime.now().millisecondsSinceEpoch}',
        'id': 'log_rest_2',
        'username': 'rest_test_user',
        'sessionId': 'sess_rest_test',
        'increment': 5,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    ]);
    print('   Created ${batchResult['count']} events');
    print('   Event IDs: ${batchResult['eventIds']}\n');

    print('=== Example completed successfully! ===');
  } catch (e, s) {
    print('Error: $e');
    print(s);
    exit(1);
  }
}

/// Simple REST API client for the local_first sync server.
class RestApiClient {
  final String baseUrl;
  final HttpClient _httpClient = HttpClient();

  RestApiClient(this.baseUrl);

  /// GET /api/health - Check server health.
  Future<Map<String, dynamic>> healthCheck() async {
    return await _get('/api/health');
  }

  /// GET /api/repositories - List all repositories.
  Future<Map<String, dynamic>> listRepositories() async {
    return await _get('/api/repositories');
  }

  /// GET /api/events/{repository}?afterSequence={n} - Get events.
  Future<Map<String, dynamic>> getEvents(
    String repository, {
    int? afterSequence,
    int? limit,
  }) async {
    final queryParams = <String, String>{};
    if (afterSequence != null) {
      queryParams['afterSequence'] = afterSequence.toString();
    }
    if (limit != null) {
      queryParams['limit'] = limit.toString();
    }

    final path = '/api/events/$repository';
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: queryParams);

    return await _get(uri.toString());
  }

  /// GET /api/events/{repository}/{eventId} - Get specific event.
  Future<Map<String, dynamic>> getEventById(
    String repository,
    String eventId,
  ) async {
    return await _get('/api/events/$repository/$eventId');
  }

  /// POST /api/events/{repository} - Create single event.
  Future<Map<String, dynamic>> createEvent(
    String repository,
    Map<String, dynamic> event,
  ) async {
    return await _post('/api/events/$repository', event);
  }

  /// POST /api/events/{repository}/batch - Create multiple events.
  Future<Map<String, dynamic>> createEventsBatch(
    String repository,
    List<Map<String, dynamic>> events,
  ) async {
    return await _post('/api/events/$repository/batch', {'events': events});
  }

  /// Helper method for GET requests.
  Future<Map<String, dynamic>> _get(String path) async {
    final url = path.startsWith('http') ? path : '$baseUrl$path';
    final uri = Uri.parse(url);

    final request = await _httpClient.getUrl(uri);
    final response = await request.close();

    final responseBody = await utf8.decoder.bind(response).join();
    final data = jsonDecode(responseBody) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      throw Exception(
        'HTTP ${response.statusCode}: ${data['error'] ?? 'Unknown error'}',
      );
    }

    return data;
  }

  /// Helper method for POST requests.
  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$baseUrl$path');

    final request = await _httpClient.postUrl(uri);
    request.headers.set('Content-Type', 'application/json');
    request.write(jsonEncode(body));

    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    final data = jsonDecode(responseBody) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      throw Exception(
        'HTTP ${response.statusCode}: ${data['error'] ?? 'Unknown error'}',
      );
    }

    return data;
  }

  /// Close the HTTP client.
  void close() {
    _httpClient.close();
  }
}
