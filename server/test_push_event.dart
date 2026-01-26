import 'dart:convert';
import 'package:http/http.dart' as http;

/// Test script to push a properly formatted event and verify it's returned correctly
void main() async {
  const baseUrl = 'http://localhost:8080';
  const repository = 'counter_log';

  print('=== Testing Event Push and Fetch ===\n');

  // Create a properly formatted event with ALL required fields
  final testEvent = {
    'eventId': 'test-complete-${DateTime.now().millisecondsSinceEpoch}',
    'operation': 0, // 0=insert
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'dataId': 'counter-test',
    'data': {
      'count': 888,
      'message': 'Test event with all fields',
    },
  };

  print('Step 1: Push event with all required fields');
  print('Event fields: ${testEvent.keys.toList()}');
  print('Event data: ${jsonEncode(testEvent)}\n');

  final pushResponse = await http.post(
    Uri.parse('$baseUrl/api/events/$repository/batch'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'events': [testEvent]
    }),
  );

  if (pushResponse.statusCode != 200 && pushResponse.statusCode != 201) {
    print('❌ Failed to push event: ${pushResponse.statusCode}');
    print('Response: ${pushResponse.body}');
    return;
  }

  print('✓ Event pushed successfully');
  final pushData = jsonDecode(pushResponse.body) as Map<String, dynamic>;
  print('Server response: ${jsonEncode(pushData)}\n');

  // Wait a moment for the event to be saved
  await Future.delayed(Duration(milliseconds: 500));

  print('Step 2: Fetch events to verify it was saved correctly');
  final fetchResponse = await http.get(
    Uri.parse('$baseUrl/api/events/$repository'),
  );

  if (fetchResponse.statusCode != 200) {
    print('❌ Failed to fetch events: ${fetchResponse.statusCode}');
    return;
  }

  final fetchData = jsonDecode(fetchResponse.body) as Map<String, dynamic>;
  final events = (fetchData['events'] as List).cast<Map<String, dynamic>>();

  print('✓ Fetched ${events.length} total events');

  // Find our test event
  final ourEvent = events.firstWhere(
    (e) => e['eventId'] == testEvent['eventId'],
    orElse: () => <String, dynamic>{},
  );

  if (ourEvent.isEmpty) {
    print('❌ Could not find our test event in the response');
    return;
  }

  print('\nStep 3: Verify returned event has all required fields');
  print('Returned event fields: ${ourEvent.keys.toList()}');
  print('Returned event: ${jsonEncode(ourEvent)}\n');

  // Check required fields
  final requiredFields = ['eventId', 'operation', 'createdAt', 'dataId', 'data', 'serverSequence'];
  final missingFields = <String>[];

  for (final field in requiredFields) {
    if (!ourEvent.containsKey(field)) {
      missingFields.add(field);
    }
  }

  if (missingFields.isNotEmpty) {
    print('❌ Missing fields: ${missingFields.join(", ")}');
    return;
  }

  print('✓ All required fields present!');
  print('✓ serverSequence: ${ourEvent['serverSequence']}');
  print('✓ operation: ${ourEvent['operation']}');
  print('✓ createdAt: ${ourEvent['createdAt']}');
  print('✓ dataId: ${ourEvent['dataId']}');

  print('\n=== ✅ Test Passed! ===');
  print('Server correctly:');
  print('1. Received event with all required fields');
  print('2. Added serverSequence');
  print('3. Returned event with all fields intact');
}
