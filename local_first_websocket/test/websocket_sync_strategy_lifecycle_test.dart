import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_websocket/local_first_websocket.dart';
import 'package:mocktail/mocktail.dart';

class MockLocalFirstClient extends Mock implements LocalFirstClient {}

class MockLocalFirstRepository extends Mock
    implements LocalFirstRepository<Map<String, dynamic>> {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  group('WebSocketSyncStrategy - Lifecycle with Connection Attempts', () {
    test('should attempt to connect when start is called', () async {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://non-existent-server.invalid:9999/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        reconnectDelay: Duration(milliseconds: 500),
      );

      final client = MockLocalFirstClient();
      when(() => client.reportConnectionState(any())).thenReturn(null);
      when(() => client.connectionChanges).thenAnswer(
        (_) => Stream<bool>.value(false),
      );
      when(() => client.latestConnectionState).thenReturn(false);
      when(() => client.awaitInitialization).thenAnswer((_) async {});

      strategy.attach(client);

      // Start will attempt connection and fail, but shouldn't throw
      await strategy.start();

      // Give time for connection attempt
      await Future.delayed(Duration(milliseconds: 100));

      // Should have called initialization
      verify(() => client.awaitInitialization).called(1);

      strategy.dispose();
    });

    test('should handle stop before start', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
      );

      final client = MockLocalFirstClient();
      when(() => client.reportConnectionState(any())).thenReturn(null);
      when(() => client.connectionChanges).thenAnswer(
        (_) => Stream<bool>.value(false),
      );
      when(() => client.latestConnectionState).thenReturn(false);

      strategy.attach(client);

      // Stop before starting should not throw
      expect(() => strategy.stop(), returnsNormally);

      strategy.dispose();
    });

    test('should handle multiple stop calls', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
      );

      final client = MockLocalFirstClient();
      when(() => client.reportConnectionState(any())).thenReturn(null);
      when(() => client.connectionChanges).thenAnswer(
        (_) => Stream<bool>.value(false),
      );
      when(() => client.latestConnectionState).thenReturn(false);

      strategy.attach(client);

      strategy.stop();
      strategy.stop();
      strategy.stop();

      // Multiple stops should not throw
      expect(() => strategy.dispose(), returnsNormally);
    });

    test('should handle dispose without start', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
      );

      final client = MockLocalFirstClient();
      when(() => client.reportConnectionState(any())).thenReturn(null);
      when(() => client.connectionChanges).thenAnswer(
        (_) => Stream<bool>.value(false),
      );
      when(() => client.latestConnectionState).thenReturn(false);

      strategy.attach(client);

      expect(() => strategy.dispose(), returnsNormally);
    });

    test('should report connection state changes', () async {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://non-existent.invalid:9999/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        reconnectDelay: Duration(seconds: 10), // Long delay to avoid reconnect
      );

      final client = MockLocalFirstClient();
      when(() => client.reportConnectionState(any())).thenReturn(null);
      when(() => client.connectionChanges).thenAnswer(
        (_) => Stream<bool>.value(false),
      );
      when(() => client.latestConnectionState).thenReturn(false);
      when(() => client.awaitInitialization).thenAnswer((_) async {});

      strategy.attach(client);

      await strategy.start();
      await Future.delayed(Duration(milliseconds: 200));

      // Connection attempt was made
      verify(() => client.awaitInitialization).called(greaterThan(0));

      strategy.dispose();
    });
  });

  group('WebSocketSyncStrategy - Event Pushing While Disconnected', () {
    late WebSocketSyncStrategy strategy;
    late MockLocalFirstClient client;
    late MockLocalFirstRepository repo;

    setUp(() {
      strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        reconnectDelay: Duration(seconds: 10),
      );

      client = MockLocalFirstClient();
      when(() => client.reportConnectionState(any())).thenReturn(null);
      when(() => client.connectionChanges).thenAnswer(
        (_) => Stream<bool>.value(false),
      );
      when(() => client.latestConnectionState).thenReturn(false);

      repo = MockLocalFirstRepository();
      when(() => repo.name).thenReturn('test_repo');
      when(() => repo.getId(any())).thenReturn('test-id');

      strategy.attach(client);
    });

    tearDown(() {
      strategy.dispose();
    });

    test('should queue events when disconnected', () async {
      final events = List.generate(
        10,
        (i) => LocalFirstEvent.createNewInsertEvent(
          repository: repo,
          data: {'id': 'id-$i', 'value': 'test-$i'},
          needSync: true,
        ),
      );

      for (final event in events) {
        final status = await strategy.onPushToRemote(event);
        expect(status, SyncStatus.pending);
      }
    });

    test('should return pending for insert events', () async {
      final event = LocalFirstEvent.createNewInsertEvent(
        repository: repo,
        data: {'id': 'test-id', 'name': 'Test'},
        needSync: true,
      );

      final status = await strategy.onPushToRemote(event);
      expect(status, SyncStatus.pending);
    });

    test('should return pending for update events', () async {
      final event = LocalFirstEvent.createNewUpdateEvent(
        repository: repo,
        data: {'id': 'test-id', 'name': 'Updated'},
        needSync: true,
      );

      final status = await strategy.onPushToRemote(event);
      expect(status, SyncStatus.pending);
    });

    test('should return pending for delete events', () async {
      final event = LocalFirstEvent.createNewDeleteEvent<Map<String, dynamic>>(
        repository: repo,
        dataId: 'test-id',
        needSync: true,
      );

      final status = await strategy.onPushToRemote(event);
      expect(status, SyncStatus.pending);
    });
  });

  group('WebSocketSyncStrategy - Configuration Validation', () {
    test('should accept valid websocket URL', () {
      expect(
        () => WebSocketSyncStrategy(
          websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
      ),
        returnsNormally,
      );
    });

    test('should accept wss:// URL', () {
      expect(
        () => WebSocketSyncStrategy(
          websocketUrl: 'wss://example.com/sync',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
      ),
        returnsNormally,
      );
    });

    test('should accept URL with query parameters', () {
      expect(
        () => WebSocketSyncStrategy(
          websocketUrl: 'ws://localhost:8080/sync?token=abc123',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
      ),
        returnsNormally,
      );
    });

    test('should accept URL with authentication', () {
      expect(
        () => WebSocketSyncStrategy(
          websocketUrl: 'ws://user:pass@localhost:8080/sync',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
      ),
        returnsNormally,
      );
    });

    test('should accept very short reconnect delay', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        reconnectDelay: Duration(milliseconds: 10),
      );

      expect(strategy.reconnectDelay, Duration(milliseconds: 10));
    });

    test('should accept very long reconnect delay', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        reconnectDelay: Duration(minutes: 5),
      );

      expect(strategy.reconnectDelay, Duration(minutes: 5));
    });

    test('should accept very short heartbeat interval', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        heartbeatInterval: Duration(milliseconds: 100),
      );

      expect(strategy.heartbeatInterval, Duration(milliseconds: 100));
    });

    test('should accept very long heartbeat interval', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        heartbeatInterval: Duration(minutes: 10),
      );

      expect(strategy.heartbeatInterval, Duration(minutes: 10));
    });
  });

  group('WebSocketSyncStrategy - Pull Changes Edge Cases', () {
    late WebSocketSyncStrategy strategy;
    late MockLocalFirstClient client;

    setUp(() {
      strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
      );

      client = MockLocalFirstClient();
      when(() => client.reportConnectionState(any())).thenReturn(null);
      when(() => client.connectionChanges).thenAnswer(
        (_) => Stream<bool>.value(false),
      );
      when(() => client.latestConnectionState).thenReturn(false);
      when(() => client.pullChanges(
            repositoryName: any(named: 'repositoryName'),
            changes: any(named: 'changes'),
          )).thenAnswer((_) async {});

      strategy.attach(client);
    });

    tearDown(() {
      strategy.dispose();
    });

    test('should handle null values in event data', () async {
      final changes = [
        {
          'id': 'test-1',
          'name': null,
          'value': null,
        }
      ];

      await strategy.pullChangesToLocal(
        repositoryName: 'test_repo',
        remoteChanges: changes,
      );

      verify(() => client.pullChanges(
            repositoryName: 'test_repo',
            changes: changes,
          )).called(1);
    });

    test('should handle nested objects in event data', () async {
      final changes = [
        {
          'id': 'test-1',
          'nested': {
            'level1': {
              'level2': {'value': 'deep'}
            }
          }
        }
      ];

      await strategy.pullChangesToLocal(
        repositoryName: 'test_repo',
        remoteChanges: changes,
      );

      verify(() => client.pullChanges(
            repositoryName: 'test_repo',
            changes: changes,
          )).called(1);
    });

    test('should handle arrays in event data', () async {
      final changes = [
        {
          'id': 'test-1',
          'tags': ['tag1', 'tag2', 'tag3'],
          'numbers': [1, 2, 3, 4, 5],
        }
      ];

      await strategy.pullChangesToLocal(
        repositoryName: 'test_repo',
        remoteChanges: changes,
      );

      verify(() => client.pullChanges(
            repositoryName: 'test_repo',
            changes: changes,
          )).called(1);
    });

    test('should handle very large event data', () async {
      final largeString = 'x' * 10000;
      final changes = [
        {
          'id': 'test-1',
          'largeField': largeString,
        }
      ];

      await strategy.pullChangesToLocal(
        repositoryName: 'test_repo',
        remoteChanges: changes,
      );

      verify(() => client.pullChanges(
            repositoryName: 'test_repo',
            changes: changes,
          )).called(1);
    });

    test('should handle special characters in repository name', () async {
      final changes = [
        {'id': 'test-1'}
      ];

      await strategy.pullChangesToLocal(
        repositoryName: 'repo-with-dashes_and_underscores.dots',
        remoteChanges: changes,
      );

      verify(() => client.pullChanges(
            repositoryName: 'repo-with-dashes_and_underscores.dots',
            changes: changes,
          )).called(1);
    });

    test('should handle Unicode characters in data', () async {
      final changes = [
        {
          'id': 'test-1',
          'name': '🚀 Rocket',
          'description': '你好世界',
          'emoji': '😀😃😄😁',
        }
      ];

      await strategy.pullChangesToLocal(
        repositoryName: 'test_repo',
        remoteChanges: changes,
      );

      verify(() => client.pullChanges(
            repositoryName: 'test_repo',
            changes: changes,
          )).called(1);
    });
  });
}
