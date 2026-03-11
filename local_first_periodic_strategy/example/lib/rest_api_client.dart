import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'package:local_first/local_first.dart';

/// REST API client for communicating with the Dart WebSocket server.
///
/// This client implements the business logic for HTTP-based event operations,
/// while the PeriodicSyncStrategy plugin handles the technical sync orchestration.
class RestApiClient {
  static const logTag = 'RestApiClient';
  final String baseUrl;

  RestApiClient({required this.baseUrl});

  /// Fetches events from the server for a specific repository
  ///
  /// [repositoryName] The repository to fetch events for
  /// [afterSequence] Optional sequence number to fetch only events after this sequence
  Future<List<JsonMap>> fetchEvents(
    String repositoryName, {
    int? afterSequence,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/events/$repositoryName').replace(
        queryParameters: afterSequence != null
            ? {'seq': afterSequence.toString()}
            : null,
      );

      dev.log(
        'Fetching events from $uri',
        name: logTag,
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        dev.log(
          'Failed to fetch events: ${response.statusCode}',
          name: logTag,
        );
        throw Exception('Failed to fetch events: ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final events = (json['events'] as List)
          .cast<Map<String, dynamic>>()
          .map((e) => JsonMap<dynamic>.from(e))
          .toList();

      dev.log(
        'Fetched ${events.length} events for $repositoryName',
        name: logTag,
      );

      return events;
    } catch (e, s) {
      dev.log(
        'Error fetching events for $repositoryName: $e',
        name: logTag,
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  /// Pushes (creates) events to the server for a specific repository
  ///
  /// [repositoryName] The repository to push events to
  /// [events] List of events to push
  ///
  /// Returns true if successful
  Future<bool> pushEvents(
    String repositoryName,
    LocalFirstEvents events,
  ) async {
    if (events.isEmpty) return true;

    try {
      final uri = Uri.parse('$baseUrl/api/events/$repositoryName/batch');
      final eventsJson = events.toJson();

      dev.log(
        'Pushing ${events.length} events to $uri',
        name: logTag,
      );

      // Convert DateTime objects to ISO 8601 strings for JSON serialization
      final jsonSafeEvents = _convertToJsonSafe(eventsJson);

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'events': jsonSafeEvents}),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        dev.log(
          'Failed to push events: ${response.statusCode}',
          name: logTag,
        );
        return false;
      }

      dev.log(
        'Successfully pushed ${events.length} events for $repositoryName',
        name: logTag,
      );

      return true;
    } catch (e, s) {
      dev.log(
        'Error pushing events for $repositoryName: $e',
        name: logTag,
        error: e,
        stackTrace: s,
      );
      return false;
    }
  }

  /// Converts a value to JSON-safe format by converting DateTime to ISO 8601 strings.
  ///
  /// This recursively processes maps and lists to ensure all DateTime objects
  /// are converted to strings before JSON encoding.
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

  /// Checks if the server is reachable
  Future<bool> ping() async {
    try {
      final uri = Uri.parse('$baseUrl/api/health');
      final response = await http.get(uri).timeout(
        Duration(seconds: 5),
        onTimeout: () => http.Response('Timeout', 408),
      );

      return response.statusCode == 200;
    } catch (e) {
      dev.log('Ping failed: $e', name: logTag, error: e);
      return false;
    }
  }
}
