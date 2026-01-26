import 'dart:convert';
import 'package:http/http.dart' as http;

/// Standalone test script to verify sequence tracking works correctly
void main() async {
  const baseUrl = 'http://localhost:8080';
  const repository = 'counter_log';

  print('=== Testing Sequence Tracking ===\n');

  // Step 1: Fetch all events (no sequence parameter)
  print('Step 1: Initial fetch (no sequence filter)');
  final initialResponse = await http.get(
    Uri.parse('$baseUrl/api/events/$repository'),
  );

  if (initialResponse.statusCode != 200) {
    print('❌ Failed to fetch events: ${initialResponse.statusCode}');
    return;
  }

  final initialData = jsonDecode(initialResponse.body) as Map<String, dynamic>;
  final initialEvents = (initialData['events'] as List).cast<Map<String, dynamic>>();

  print('✓ Fetched ${initialEvents.length} events');

  if (initialEvents.isEmpty) {
    print('⚠️  No events in database. Add some events first.');
    return;
  }

  // Extract max sequence (simulate what the app does)
  int? maxSequence;
  for (final event in initialEvents) {
    final seq = event['serverSequence'] as int?;
    if (seq != null) {
      maxSequence = maxSequence == null ? seq : (seq > maxSequence ? seq : maxSequence);
    }
  }

  print('✓ Extracted maxSequence: $maxSequence');
  print('  Event sequences: ${initialEvents.map((e) => e['serverSequence']).toList()}\n');

  if (maxSequence == null) {
    print('❌ No serverSequence found in events');
    return;
  }

  // Step 2: Save maxSequence and fetch again (simulate next sync cycle)
  print('Step 2: Fetch with seq=$maxSequence (simulate next sync)');
  final filteredResponse = await http.get(
    Uri.parse('$baseUrl/api/events/$repository?seq=$maxSequence'),
  );

  if (filteredResponse.statusCode != 200) {
    print('❌ Failed to fetch filtered events: ${filteredResponse.statusCode}');
    return;
  }

  final filteredData = jsonDecode(filteredResponse.body) as Map<String, dynamic>;
  final filteredEvents = (filteredData['events'] as List).cast<Map<String, dynamic>>();

  print('✓ Fetched ${filteredEvents.length} events');

  if (filteredEvents.isEmpty) {
    print('✓ Correct! No events with sequence > $maxSequence');
    print('✓ This confirms the app won\'t fetch the same events again\n');
  } else {
    print('✓ Found ${filteredEvents.length} new events:');
    for (final event in filteredEvents) {
      final seq = event['serverSequence'];
      final id = event['eventId'];
      print('  - Event $id with sequence $seq');

      if (seq <= maxSequence) {
        print('❌ ERROR: Event has sequence $seq which is <= $maxSequence!');
        print('   This would cause an infinite loop!');
        return;
      }
    }
    print('✓ All new events have sequence > $maxSequence\n');

    // Update maxSequence
    final newMaxSequence = filteredEvents
        .map((e) => e['serverSequence'] as int)
        .reduce((a, b) => a > b ? a : b);
    print('✓ New maxSequence would be: $newMaxSequence\n');
  }

  // Step 3: Add a test event and verify it's fetched correctly
  print('Step 3: Add new event and verify fetch');

  final newEvent = {
    'events': [
      {
        'eventId': 'test-${DateTime.now().millisecondsSinceEpoch}',
        'eventType': 'CounterLogData',
        'repositoryName': repository,
        'dataId': 'test-counter',
        'userId': 'test-user',
        'timestamp': DateTime.now().toIso8601String(),
        'data': {'count': 999, 'message': 'Test event'},
      }
    ]
  };

  final addResponse = await http.post(
    Uri.parse('$baseUrl/api/events/$repository/batch'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(newEvent),
  );

  if (addResponse.statusCode != 200 && addResponse.statusCode != 201) {
    print('❌ Failed to add event: ${addResponse.statusCode}');
    return;
  }

  final addData = jsonDecode(addResponse.body) as Map<String, dynamic>;
  print('✓ Added event: ${addData['eventIds']?.first}');

  // Fetch again with previous maxSequence
  final afterAddResponse = await http.get(
    Uri.parse('$baseUrl/api/events/$repository?seq=$maxSequence'),
  );

  if (afterAddResponse.statusCode != 200) {
    print('❌ Failed to fetch after adding: ${afterAddResponse.statusCode}');
    return;
  }

  final afterAddData = jsonDecode(afterAddResponse.body) as Map<String, dynamic>;
  final afterAddEvents = (afterAddData['events'] as List).cast<Map<String, dynamic>>();

  print('✓ Fetched ${afterAddEvents.length} events after adding');

  if (afterAddEvents.isEmpty) {
    print('❌ Expected to find the new event but got none');
    return;
  }

  final newEventSequence = afterAddEvents.last['serverSequence'] as int;
  print('✓ New event has sequence $newEventSequence');

  if (newEventSequence > maxSequence) {
    print('✓ Correct! $newEventSequence > $maxSequence\n');
  } else {
    print('❌ ERROR: $newEventSequence <= $maxSequence\n');
    return;
  }

  print('=== ✅ All Tests Passed! ===');
  print('Sequence tracking is working correctly:');
  print('1. Client fetches events');
  print('2. Client saves maxSequence (no modification)');
  print('3. Server filters with where.gt(serverSequence, seq)');
  print('4. Client only receives new events');
  print('5. No infinite loop!');
}
