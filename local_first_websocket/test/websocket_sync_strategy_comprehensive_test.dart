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

  group('WebSocketSyncStrategy - pullChangesToLocal', () {
    late WebSocketSyncStrategy strategy;
    late MockLocalFirstClient client;

    setUp(() {
      strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
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

    test('should call client.pullChanges with correct parameters', () async {
      final changes = [
        {'id': '1', 'data': 'test'}
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

    test('should handle empty changes list', () async {
      await strategy.pullChangesToLocal(
        repositoryName: 'test_repo',
        remoteChanges: [],
      );

      verify(() => client.pullChanges(
            repositoryName: 'test_repo',
            changes: [],
          )).called(1);
    });

    test('should extract DateTime timestamp', () async {
      final now = DateTime.now().toUtc();
      final changes = [
        {'syncCreatedAt': now}
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

    test('should extract string timestamp', () async {
      final now = DateTime.now().toUtc();
      final changes = [
        {'syncCreatedAt': now.toIso8601String()}
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

    test('should extract int timestamp', () async {
      final now = DateTime.now().toUtc();
      final changes = [
        {'syncCreatedAt': now.millisecondsSinceEpoch}
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

    test('should handle invalid string timestamp', () async {
      final changes = [
        {'syncCreatedAt': 'invalid-date'}
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

    test('should handle missing timestamp field', () async {
      final changes = [
        {'data': 'test'}
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

    test('should handle multiple events with different timestamps', () async {
      final older = DateTime(2025, 1, 1).toUtc();
      final newer = DateTime(2025, 1, 2).toUtc();

      final changes = [
        {'syncCreatedAt': older.toIso8601String()},
        {'syncCreatedAt': newer.millisecondsSinceEpoch},
        {'syncCreatedAt': newer},
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

  group('WebSocketSyncStrategy - getPendingEvents', () {
    late WebSocketSyncStrategy strategy;
    late MockLocalFirstClient client;

    setUp(() {
      strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
      );

      client = MockLocalFirstClient();
      when(() => client.reportConnectionState(any())).thenReturn(null);
      when(() => client.connectionChanges).thenAnswer(
        (_) => Stream<bool>.value(false),
      );
      when(() => client.latestConnectionState).thenReturn(false);

      strategy.attach(client);
    });

    tearDown(() {
      strategy.dispose();
    });

    test('should delegate to client.getAllPendingEvents', () async {
      when(() => client.getAllPendingEvents(repositoryName: 'test_repo'))
          .thenAnswer((_) async => []);

      final events = await strategy.getPendingEvents(
        repositoryName: 'test_repo',
      );

      expect(events, isEmpty);
      verify(() => client.getAllPendingEvents(repositoryName: 'test_repo'))
          .called(1);
    });

    test('should return events from client', () async {
      final mockRepo = MockLocalFirstRepository();
      when(() => mockRepo.name).thenReturn('test_repo');

      final event = LocalFirstEvent.createNewInsertEvent(
        repository: mockRepo,
        data: {'id': '1'},
        needSync: true,
      );

      when(() => client.getAllPendingEvents(repositoryName: 'test_repo'))
          .thenAnswer((_) async => [event]);

      final events = await strategy.getPendingEvents(
        repositoryName: 'test_repo',
      );

      expect(events, hasLength(1));
      expect(events.first, equals(event));
    });
  });

  group('WebSocketSyncStrategy - Event Queue', () {
    late WebSocketSyncStrategy strategy;
    late MockLocalFirstClient client;
    late MockLocalFirstRepository repo;

    setUp(() {
      strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
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

    test('should return pending status when not connected', () async {
      final event = LocalFirstEvent.createNewInsertEvent(
        repository: repo,
        data: {'id': '1', 'value': 'test'},
        needSync: true,
      );

      final status = await strategy.onPushToRemote(event);

      expect(status, SyncStatus.pending);
    });

    test('should queue multiple events when disconnected', () async {
      final events = List.generate(
        5,
        (i) => LocalFirstEvent.createNewInsertEvent(
          repository: repo,
          data: {'id': '$i', 'value': 'test$i'},
          needSync: true,
        ),
      );

      for (final event in events) {
        final status = await strategy.onPushToRemote(event);
        expect(status, SyncStatus.pending);
      }
    });
  });

  group('WebSocketSyncStrategy - Credential Updates', () {
    test('updateAuthToken updates the token', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
        authToken: 'initial-token',
      );

      expect(strategy.authToken, 'initial-token');

      strategy.updateAuthToken('new-token');
      expect(strategy.authToken, 'new-token');

      strategy.updateAuthToken(null);
      expect(strategy.authToken, isNull);
    });

    test('updateHeaders updates the headers', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
        headers: {'X-Initial': 'value'},
      );

      expect(strategy.headers, {'X-Initial': 'value'});

      strategy.updateHeaders({'X-New': 'header'});
      expect(strategy.headers, {'X-New': 'header'});

      strategy.updateHeaders({});
      expect(strategy.headers, isEmpty);
    });

    test('updateCredentials updates both token and headers', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
      );

      strategy.updateCredentials(
        authToken: 'token',
        headers: {'X-Header': 'value'},
      );

      expect(strategy.authToken, 'token');
      expect(strategy.headers, {'X-Header': 'value'});
    });

    test('updateCredentials updates only token when headers is null', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
        headers: {'X-Existing': 'value'},
      );

      strategy.updateCredentials(authToken: 'new-token');

      expect(strategy.authToken, 'new-token');
      expect(strategy.headers, {'X-Existing': 'value'});
    });

    test('updateCredentials updates only headers when token is null', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
        authToken: 'existing-token',
      );

      strategy.updateCredentials(headers: {'X-New': 'header'});

      expect(strategy.authToken, 'existing-token');
      expect(strategy.headers, {'X-New': 'header'});
    });

    test('updateCredentials with both null keeps existing values', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
        authToken: 'token',
        headers: {'X-Header': 'value'},
      );

      strategy.updateCredentials();

      expect(strategy.authToken, 'token');
      expect(strategy.headers, {'X-Header': 'value'});
    });
  });

  group('WebSocketSyncStrategy - Configuration', () {
    test('uses default values when not provided', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
      );

      expect(strategy.websocketUrl, 'ws://localhost:8080/test');
      expect(strategy.reconnectDelay, Duration(seconds: 3));
      expect(strategy.heartbeatInterval, Duration(seconds: 30));
      expect(strategy.authToken, isNull);
      expect(strategy.headers, isEmpty);
    });

    test('accepts custom reconnect delay', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
        reconnectDelay: Duration(seconds: 10),
      );

      expect(strategy.reconnectDelay, Duration(seconds: 10));
    });

    test('accepts custom heartbeat interval', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
        heartbeatInterval: Duration(minutes: 1),
      );

      expect(strategy.heartbeatInterval, Duration(minutes: 1));
    });

    test('accepts custom auth token', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
        authToken: 'custom-token',
      );

      expect(strategy.authToken, 'custom-token');
    });

    test('accepts custom headers', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
        headers: {'Authorization': 'Bearer token', 'X-Custom': 'value'},
      );

      expect(strategy.headers, {
        'Authorization': 'Bearer token',
        'X-Custom': 'value',
      });
    });

    test('headers getter returns unmodifiable map', () {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
        headers: {'X-Original': 'value'},
      );

      final headers = strategy.headers;

      expect(() => headers['X-New'] = 'value', throwsUnsupportedError);
    });
  });

  group('WebSocketSyncStrategy - Lifecycle', () {
    late WebSocketSyncStrategy strategy;
    late MockLocalFirstClient client;

    setUp(() {
      strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
      );

      client = MockLocalFirstClient();
      when(() => client.reportConnectionState(any())).thenReturn(null);
      when(() => client.connectionChanges).thenAnswer(
        (_) => Stream<bool>.value(false),
      );
      when(() => client.latestConnectionState).thenReturn(false);

      strategy.attach(client);
    });

    test('stop should handle when not started', () {
      expect(() => strategy.stop(), returnsNormally);
    });

    test('dispose should call stop', () {
      expect(() => strategy.dispose(), returnsNormally);
      // Calling dispose again should be safe
      expect(() => strategy.dispose(), returnsNormally);
    });

    test('connectionChanges should return a stream', () {
      expect(strategy.connectionChanges, isA<Stream<bool>>());
    });

    test('latestConnectionState should delegate to client', () {
      // The mock client returns false, so the strategy should return false
      expect(strategy.latestConnectionState, isFalse);
    });
  });

  group('WebSocketSyncStrategy - markEventsAsSynced', () {
    late WebSocketSyncStrategy strategy;
    late MockLocalFirstClient client;

    setUp(() {
      strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
      );

      client = MockLocalFirstClient();
      when(() => client.reportConnectionState(any())).thenReturn(null);
      when(() => client.connectionChanges).thenAnswer(
        (_) => Stream<bool>.value(false),
      );
      when(() => client.latestConnectionState).thenReturn(false);

      strategy.attach(client);
    });

    tearDown(() {
      strategy.dispose();
    });

    test('should handle empty events list', () async {
      await strategy.markEventsAsSynced([]);
      // Should complete without errors
    });

    test('should call markEventsAsSynced without errors', () async {
      // markEventsAsSynced is a method from the base class that internally
      // calls repository methods. For unit tests, we verify it handles empty list
      expect(() => strategy.markEventsAsSynced([]), returnsNormally);
    });
  });

  group('WebSocketSyncStrategy - Timestamp Extraction', () {
    late WebSocketSyncStrategy strategy;
    late MockLocalFirstClient client;

    setUp(() {
      strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
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

    test('should extract latest timestamp from mixed format events', () async {
      final oldest = DateTime(2025, 1, 1, 10, 0, 0).toUtc();
      final middle = DateTime(2025, 1, 2, 10, 0, 0).toUtc();
      final newest = DateTime(2025, 1, 3, 10, 0, 0).toUtc();

      final changes = [
        {
          LocalFirstEvent.kSyncCreatedAt: oldest.toIso8601String(),
          'data': 'test1'
        },
        {
          LocalFirstEvent.kSyncCreatedAt: middle.millisecondsSinceEpoch,
          'data': 'test2'
        },
        {LocalFirstEvent.kSyncCreatedAt: newest, 'data': 'test3'},
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

    test('should handle events with no valid timestamps', () async {
      final changes = [
        {'data': 'test1'},
        {LocalFirstEvent.kSyncCreatedAt: 'invalid', 'data': 'test2'},
        {LocalFirstEvent.kSyncCreatedAt: null, 'data': 'test3'},
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

    test('should handle events with timestamps of different types', () async {
      final now = DateTime.now().toUtc();
      final changes = [
        {LocalFirstEvent.kSyncCreatedAt: now, 'data': 'test1'},
        {
          LocalFirstEvent.kSyncCreatedAt: now.toIso8601String(),
          'data': 'test2'
        },
        {
          LocalFirstEvent.kSyncCreatedAt: now.millisecondsSinceEpoch,
          'data': 'test3'
        },
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

  group('WebSocketSyncStrategy - Multiple Repositories', () {
    late WebSocketSyncStrategy strategy;
    late MockLocalFirstClient client;

    setUp(() {
      strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, __) async {},
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

    test('should handle pull changes for different repositories', () async {
      await strategy.pullChangesToLocal(
        repositoryName: 'users',
        remoteChanges: [
          {'id': '1', 'name': 'User 1'}
        ],
      );

      await strategy.pullChangesToLocal(
        repositoryName: 'todos',
        remoteChanges: [
          {'id': '1', 'title': 'Todo 1'}
        ],
      );

      verify(() => client.pullChanges(
            repositoryName: 'users',
            changes: any(named: 'changes'),
          )).called(1);
      verify(() => client.pullChanges(
            repositoryName: 'todos',
            changes: any(named: 'changes'),
          )).called(1);
    });

    test('should track pending events for different repositories', () async {
      final usersRepo = MockLocalFirstRepository();
      final todosRepo = MockLocalFirstRepository();

      when(() => usersRepo.name).thenReturn('users');
      when(() => usersRepo.getId(any())).thenReturn('user-id');
      when(() => todosRepo.name).thenReturn('todos');
      when(() => todosRepo.getId(any())).thenReturn('todo-id');

      final userEvent = LocalFirstEvent.createNewInsertEvent(
        repository: usersRepo,
        data: {'id': 'user-id', 'name': 'Test User'},
        needSync: true,
      );

      final todoEvent = LocalFirstEvent.createNewInsertEvent(
        repository: todosRepo,
        data: {'id': 'todo-id', 'title': 'Test Todo'},
        needSync: true,
      );

      final status1 = await strategy.onPushToRemote(userEvent);
      final status2 = await strategy.onPushToRemote(todoEvent);

      expect(status1, SyncStatus.pending);
      expect(status2, SyncStatus.pending);
    });
  });
}
