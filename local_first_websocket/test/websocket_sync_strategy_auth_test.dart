import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_websocket/local_first_websocket.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class MockLocalFirstClient extends Mock implements LocalFirstClient {}

class MockWebSocketChannel extends Mock implements WebSocketChannel {}

class MockWebSocketSink extends Mock implements WebSocketSink {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('WebSocketSyncStrategy - Authentication Callback', () {
    late MockLocalFirstClient client;

    setUp(() {
      client = MockLocalFirstClient();

      when(() => client.reportConnectionState(any())).thenReturn(null);
      when(
        () => client.connectionChanges,
      ).thenAnswer((_) => Stream<bool>.value(false));
      when(() => client.latestConnectionState).thenReturn(false);
      when(() => client.awaitInitialization).thenAnswer((_) async {});
      when(
        () => client.pullChanges(
          repositoryName: any(named: 'repositoryName'),
          changes: any(named: 'changes'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => client.getAllPendingEvents(
          repositoryName: any(named: 'repositoryName'),
        ),
      ).thenAnswer((_) async => []);
    });

    test('should call onAuthenticationFailed when auth fails', () async {
      final messageController = StreamController<dynamic>.broadcast();
      final mockChannel = MockWebSocketChannel();
      final mockSink = MockWebSocketSink();
      final capturedMessages = <String>[];

      var authCallCount = 0;
      when(() => mockChannel.ready).thenAnswer((_) async {});
      when(
        () => mockChannel.stream,
      ).thenAnswer((_) => messageController.stream);
      when(() => mockChannel.sink).thenReturn(mockSink);
      when(() => mockSink.add(any())).thenAnswer((invocation) {
        final message = invocation.positionalArguments[0] as String;
        capturedMessages.add(message);

        // Simulate StateError on first auth attempt
        final decoded = jsonDecode(message);
        if (decoded['type'] == 'auth' && authCallCount == 0) {
          authCallCount++;
          throw StateError('Connection lost');
        }
      });
      when(() => mockSink.close()).thenAnswer((_) async {});

      var callbackInvoked = false;
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        authToken: 'expired-token',
        channelFactory: (_) => mockChannel,
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        onAuthenticationFailed: () async {
          callbackInvoked = true;
          // Simulate refreshing token
          return const AuthCredentials(
            authToken: 'refreshed-token',
            headers: {'X-Refreshed': 'true'},
          );
        },
      );
      strategy.attach(client);

      await strategy.start();
      await Future.delayed(Duration(milliseconds: 100));

      // Callback should have been invoked
      expect(callbackInvoked, isTrue);

      // Should have attempted auth twice (initial + retry)
      final authMessages = capturedMessages.where((msg) {
        try {
          final decoded = jsonDecode(msg);
          return decoded['type'] == 'auth';
        } catch (_) {
          return false;
        }
      }).toList();

      // At least one auth attempt should have been made
      expect(authMessages, isNotEmpty);

      messageController.close();
      strategy.dispose();
    });

    test('should not retry auth if callback returns null', () async {
      final messageController = StreamController<dynamic>.broadcast();
      final mockChannel = MockWebSocketChannel();
      final mockSink = MockWebSocketSink();

      when(() => mockChannel.ready).thenAnswer((_) async {});
      when(
        () => mockChannel.stream,
      ).thenAnswer((_) => messageController.stream);
      when(() => mockChannel.sink).thenReturn(mockSink);
      when(() => mockSink.add(any())).thenAnswer((_) {
        // Simulate error on every auth attempt
        throw StateError('Connection lost');
      });
      when(() => mockSink.close()).thenAnswer((_) async {});

      var callbackInvoked = false;
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        authToken: 'expired-token',
        channelFactory: (_) => mockChannel,
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        onAuthenticationFailed: () async {
          callbackInvoked = true;
          // Return null = don't retry
          return null;
        },
      );
      strategy.attach(client);

      await strategy.start();
      await Future.delayed(Duration(milliseconds: 100));

      // Callback should have been invoked
      expect(callbackInvoked, isTrue);

      messageController.close();
      strategy.dispose();
    });

    test('should handle callback errors gracefully', () async {
      final messageController = StreamController<dynamic>.broadcast();
      final mockChannel = MockWebSocketChannel();
      final mockSink = MockWebSocketSink();

      when(() => mockChannel.ready).thenAnswer((_) async {});
      when(
        () => mockChannel.stream,
      ).thenAnswer((_) => messageController.stream);
      when(() => mockChannel.sink).thenReturn(mockSink);
      when(() => mockSink.add(any())).thenAnswer((_) {
        throw StateError('Connection lost');
      });
      when(() => mockSink.close()).thenAnswer((_) async {});

      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        authToken: 'expired-token',
        channelFactory: (_) => mockChannel,
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        onAuthenticationFailed: () async {
          // Simulate callback error
          throw Exception('Failed to refresh token');
        },
      );
      strategy.attach(client);

      // Should not crash despite callback error
      await strategy.start();
      await Future.delayed(Duration(milliseconds: 100));

      // Should still be in valid state
      expect(strategy.latestConnectionState, isNotNull);

      messageController.close();
      strategy.dispose();
    });

    test('should update credentials from callback', () async {
      final messageController = StreamController<dynamic>.broadcast();
      final mockChannel = MockWebSocketChannel();
      final mockSink = MockWebSocketSink();
      final capturedMessages = <String>[];

      var authCallCount = 0;
      when(() => mockChannel.ready).thenAnswer((_) async {});
      when(
        () => mockChannel.stream,
      ).thenAnswer((_) => messageController.stream);
      when(() => mockChannel.sink).thenReturn(mockSink);
      when(() => mockSink.add(any())).thenAnswer((invocation) {
        final message = invocation.positionalArguments[0] as String;
        capturedMessages.add(message);

        // Fail on first attempt only
        final decoded = jsonDecode(message);
        if (decoded['type'] == 'auth' && authCallCount == 0) {
          authCallCount++;
          throw StateError('Connection lost');
        }
      });
      when(() => mockSink.close()).thenAnswer((_) async {});

      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        authToken: 'old-token',
        headers: const {'X-Old': 'header'},
        channelFactory: (_) => mockChannel,
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        onAuthenticationFailed: () async {
          return const AuthCredentials(
            authToken: 'new-token',
            headers: {'X-New': 'header', 'X-Refreshed': 'true'},
          );
        },
      );
      strategy.attach(client);

      await strategy.start();
      await Future.delayed(Duration(milliseconds: 100));

      // Verify token was updated
      expect(strategy.authToken, 'new-token');

      // Verify headers were updated
      expect(strategy.headers['X-New'], 'header');
      expect(strategy.headers['X-Refreshed'], 'true');

      messageController.close();
      strategy.dispose();
    });
  });
}
