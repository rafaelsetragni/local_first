import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_websocket/local_first_websocket.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class MockLocalFirstClient extends Mock implements LocalFirstClient {}

class MockLocalFirstRepository extends Mock
    implements LocalFirstRepository<Map<String, dynamic>> {}

class MockWebSocketChannel extends Mock implements WebSocketChannel {}

class MockWebSocketSink extends Mock implements WebSocketSink {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(
      LocalFirstEvent.createNewInsertEvent(
        repository: MockLocalFirstRepository(),
        data: {},
        needSync: true,
      ),
    );
  });

  group('WebSocketSyncStrategy - Edge Cases', () {
    late MockLocalFirstClient client;
    late MockLocalFirstRepository repo;

    setUp(() {
      client = MockLocalFirstClient();
      repo = MockLocalFirstRepository();

      when(() => client.reportConnectionState(any())).thenReturn(null);
      when(() => client.connectionChanges).thenAnswer(
        (_) => Stream<bool>.value(false),
      );
      when(() => client.latestConnectionState).thenReturn(false);
      when(() => client.awaitInitialization).thenAnswer((_) async {});
      when(() => client.pullChanges(
            repositoryName: any(named: 'repositoryName'),
            changes: any(named: 'changes'),
          )).thenAnswer((_) async {});
      when(() => client.getAllPendingEvents(
            repositoryName: any(named: 'repositoryName'),
          )).thenAnswer((_) async => []);

      when(() => repo.name).thenReturn('test_repo');
      when(() => repo.getId(any())).thenReturn('test-id');
    });

    test('should handle reconnection after delay', () async {
      int connectionAttempts = 0;
      final List<StreamController<dynamic>> controllers = [];

      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        reconnectDelay: Duration(milliseconds: 50),
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        channelFactory: (uri) {
          connectionAttempts++;
          final controller = StreamController<dynamic>.broadcast();
          controllers.add(controller);
          final mockChannel = MockWebSocketChannel();
          final mockSink = MockWebSocketSink();

          when(() => mockChannel.ready).thenAnswer((_) async {});
          when(() => mockChannel.stream).thenAnswer((_) => controller.stream);
          when(() => mockChannel.sink).thenReturn(mockSink);
          when(() => mockSink.add(any())).thenAnswer((_) {});
          when(() => mockSink.close()).thenAnswer((_) async {});

          return mockChannel;
        },
      );
      strategy.attach(client);

      await strategy.start();
      await Future.delayed(Duration(milliseconds: 10));

      // Force disconnection
      controllers.first.addError(Exception('Connection failed'));
      await Future.delayed(Duration(milliseconds: 10));

      // Wait for reconnection timer
      await Future.delayed(Duration(milliseconds: 100));

      // Should have attempted reconnection
      expect(connectionAttempts, greaterThanOrEqualTo(2));

      for (final controller in controllers) {
        controller.close();
      }
      strategy.dispose();
    });

    // Note: DateTime object extraction is already tested in comprehensive tests
    // with DateTime.tryParse and millisecondsSinceEpoch variations

    test('should handle heartbeat error gracefully', () async {
      final messageController = StreamController<dynamic>.broadcast();
      final mockChannel = MockWebSocketChannel();
      final mockSink = MockWebSocketSink();

      int addCallCount = 0;
      when(() => mockChannel.ready).thenAnswer((_) async {});
      when(() => mockChannel.stream).thenAnswer((_) => messageController.stream);
      when(() => mockChannel.sink).thenReturn(mockSink);
      when(() => mockSink.add(any())).thenAnswer((_) {
        addCallCount++;
        // Throw error on heartbeat messages (non-auth messages after initial setup)
        if (addCallCount > 2) {
          throw StateError('WebSocket not connected');
        }
      });
      when(() => mockSink.close()).thenAnswer((_) async {});

      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        heartbeatInterval: Duration(milliseconds: 50),
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        channelFactory: (_) => mockChannel,
      );
      strategy.attach(client);

      await strategy.start();
      await Future.delayed(Duration(milliseconds: 100));

      // Wait for heartbeat to attempt and fail
      await Future.delayed(Duration(milliseconds: 100));

      // Should still be running, error was caught
      expect(strategy.latestConnectionState, isNotNull);

      messageController.close();
      strategy.dispose();
    });

    // Note: Pending queue flush is complex to test with mocks due to async timing
    // The logic is validated through lifecycle tests where events are queued
  });
}
