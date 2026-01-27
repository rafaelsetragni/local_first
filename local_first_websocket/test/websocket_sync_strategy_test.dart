import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_websocket/local_first_websocket.dart';
import 'package:mocktail/mocktail.dart';

class MockLocalFirstClient extends Mock implements LocalFirstClient {}

class MockLocalFirstRepository extends Mock
    implements LocalFirstRepository<Map<String, dynamic>> {}

void main() {
  group('WebSocketSyncStrategy', () {
    late WebSocketSyncStrategy strategy;
    late MockLocalFirstClient client;

    setUp(() {
      strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        reconnectDelay: Duration(milliseconds: 100),
        heartbeatInterval: Duration(milliseconds: 200),
      );

      // Attach a mock client to avoid LateInitializationError
      client = MockLocalFirstClient();
      when(() => client.reportConnectionState(any())).thenReturn(null);
      when(
        () => client.connectionChanges,
      ).thenAnswer((_) => Stream<bool>.value(false));
      when(() => client.latestConnectionState).thenReturn(false);

      strategy.attach(client);
    });

    tearDown(() {
      strategy.dispose();
    });

    test('should initialize with correct configuration', () {
      expect(strategy.websocketUrl, 'ws://localhost:8080/test');
      expect(strategy.reconnectDelay, Duration(milliseconds: 100));
      expect(strategy.heartbeatInterval, Duration(milliseconds: 200));
    });

    test('should expose connectionChanges stream', () {
      expect(strategy.connectionChanges, isA<Stream<bool>>());
    });

    test('onPushToRemote should return pending when not connected', () async {
      final repo = MockLocalFirstRepository();
      when(() => repo.name).thenReturn('test_repo');
      when(() => repo.getId(any())).thenReturn('test-id');

      final event = LocalFirstEvent.createNewInsertEvent(
        repository: repo,
        data: {'id': 'test-id', 'value': 'test'},
        needSync: true,
      );

      final status = await strategy.onPushToRemote(event);

      expect(status, SyncStatus.pending);
    });

    test('should handle dispose gracefully', () {
      expect(() => strategy.dispose(), returnsNormally);
    });

    test('should handle stop gracefully', () {
      expect(() => strategy.stop(), returnsNormally);
    });
  });

  group('WebSocketSyncStrategy authentication', () {
    test('should initialize with null authToken by default', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
      );

      expect(strategy.authToken, isNull);
      expect(strategy.headers, isEmpty);
    });

    test('should initialize with provided authToken and headers', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        authToken: 'test-token',
        headers: {'X-Custom': 'value'},
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
      );

      expect(strategy.authToken, 'test-token');
      expect(strategy.headers, {'X-Custom': 'value'});
    });

    test('should update authToken', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
      );

      strategy.updateAuthToken('new-token');

      expect(strategy.authToken, 'new-token');
    });

    test('should update headers', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
      );

      strategy.updateHeaders({'Authorization': 'Bearer token'});

      expect(strategy.headers, {'Authorization': 'Bearer token'});
    });

    test('should update both authToken and headers with updateCredentials', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
      );

      strategy.updateCredentials(
        authToken: 'new-token',
        headers: {'X-Custom': 'value'},
      );

      expect(strategy.authToken, 'new-token');
      expect(strategy.headers, {'X-Custom': 'value'});
    });

    test(
      'should update only authToken when headers is null in updateCredentials',
      () {
        final strategy = WebSocketSyncStrategy(
          websocketUrl: 'ws://localhost:8080/test',
          onBuildSyncFilter: (_) async => null,
          onSyncCompleted: (_, _) async {},
          headers: {'Existing': 'header'},
        );

        strategy.updateCredentials(authToken: 'new-token');

        expect(strategy.authToken, 'new-token');
        expect(strategy.headers, {'Existing': 'header'});
      },
    );

    test(
      'should update only headers when authToken is null in updateCredentials',
      () {
        final strategy = WebSocketSyncStrategy(
          websocketUrl: 'ws://localhost:8080/test',
          onBuildSyncFilter: (_) async => null,
          onSyncCompleted: (_, _) async {},
          authToken: 'existing-token',
        );

        strategy.updateCredentials(headers: {'New': 'header'});

        expect(strategy.authToken, 'existing-token');
        expect(strategy.headers, {'New': 'header'});
      },
    );

    test('should return unmodifiable copy of headers', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        headers: {'Original': 'value'},
      );

      final headers = strategy.headers;

      // Attempt to modify the returned headers should not affect internal state
      expect(() => headers['New'] = 'value', throwsUnsupportedError);
    });
  });

  group('WebSocketSyncStrategy connection state', () {
    test('should report disconnected initially', () async {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://invalid-host:9999/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        reconnectDelay: Duration(seconds: 1),
      );

      // Attach a mock client
      final mockClient = MockLocalFirstClient();
      when(() => mockClient.reportConnectionState(any())).thenReturn(null);
      when(
        () => mockClient.connectionChanges,
      ).thenAnswer((_) => Stream<bool>.value(false));
      when(() => mockClient.latestConnectionState).thenReturn(null);

      strategy.attach(mockClient);

      // The strategy should initially be disconnected
      expect(strategy.latestConnectionState, isNull);

      strategy.dispose();
    });
  });
}
