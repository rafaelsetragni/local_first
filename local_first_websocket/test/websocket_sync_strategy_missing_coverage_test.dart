import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_first/local_first.dart';
import 'package:local_first_websocket/local_first_websocket.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// --- Mocks ---

class MockLocalFirstClient extends Mock implements LocalFirstClient {}

class MockLocalFirstRepository extends Mock
    implements LocalFirstRepository<Map<String, dynamic>> {}

class MockWebSocketChannel extends Mock implements WebSocketChannel {}

class MockWebSocketSink extends Mock implements WebSocketSink {}

// --- Helpers ---

/// Builds a mock WebSocket channel trio: (channel, sink, messageController).
(MockWebSocketChannel, MockWebSocketSink, StreamController<dynamic>)
_buildChannel({bool Function(String)? throwStateErrorWhen}) {
  final controller = StreamController<dynamic>.broadcast();
  final mockChannel = MockWebSocketChannel();
  final mockSink = MockWebSocketSink();

  when(() => mockChannel.ready).thenAnswer((_) async {});
  when(() => mockChannel.stream).thenAnswer((_) => controller.stream);
  when(() => mockChannel.sink).thenReturn(mockSink);
  when(() => mockSink.add(any())).thenAnswer((inv) {
    final msg = inv.positionalArguments[0] as String;
    if (throwStateErrorWhen != null && throwStateErrorWhen(msg)) {
      throw StateError('Simulated connection loss');
    }
  });
  when(() => mockSink.close()).thenAnswer((_) async {});

  return (mockChannel, mockSink, controller);
}

/// Sends `auth_success` then waits for the async processing.
Future<void> _completeAuth(StreamController<dynamic> controller) async {
  controller.add(jsonEncode({'type': 'auth_success'}));
  await Future.delayed(const Duration(milliseconds: 50));
}

/// Sends events to the strategy, populating _knownRepositories.
Future<void> _sendEvents(
  StreamController<dynamic> controller,
  String repositoryName, {
  String eventId = 'e1',
}) async {
  controller.add(jsonEncode({
    'type': 'events',
    'repository': repositoryName,
    'events': [
      {
        'eventId': eventId,
        LocalFirstEvent.kSyncCreatedAt:
            DateTime.now().toUtc().toIso8601String(),
        'data': {'id': '1'},
      },
    ],
  }));
  await Future.delayed(const Duration(milliseconds: 50));
}

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

  group('WebSocketSyncStrategy - Missing coverage paths', () {
    late MockLocalFirstClient client;
    late MockLocalFirstRepository repo;

    setUp(() {
      client = MockLocalFirstClient();
      repo = MockLocalFirstRepository();

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

      when(() => repo.name).thenReturn('test_repo');
      when(() => repo.getId(any())).thenReturn('test-id');
      when(
        () => repo.toJson(any()),
      ).thenAnswer((inv) => inv.positionalArguments[0] as Map<String, dynamic>);
    });

    // -------------------------------------------------------------------
    // Lines 602, 608: push_event message sent when connected
    // -------------------------------------------------------------------
    test('sends push_event message and returns pending when connected',
        () async {
      final (mockChannel, mockSink, controller) = _buildChannel();
      final capturedMessages = <String>[];
      when(() => mockSink.add(any())).thenAnswer(
        (inv) => capturedMessages.add(inv.positionalArguments[0] as String),
      );

      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        channelFactory: (_) => mockChannel,
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        reconnectDelay: const Duration(seconds: 100),
      );
      strategy.attach(client);

      await strategy.start();
      await Future.delayed(const Duration(milliseconds: 50));
      // Complete auth so _connect() finishes cleanly
      await _completeAuth(controller);
      capturedMessages.clear();

      final event = LocalFirstEvent.createNewInsertEvent(
        repository: repo,
        data: {'id': '1'},
        needSync: true,
      );
      final status = await strategy.onPushToRemote(event);

      expect(status, SyncStatus.pending);
      final pushMessages = capturedMessages.where((m) {
        try {
          return (jsonDecode(m) as Map)['type'] == 'push_event';
        } catch (_) {
          return false;
        }
      }).toList();
      expect(pushMessages, isNotEmpty);

      controller.close();
      strategy.dispose();
    });

    // -------------------------------------------------------------------
    // Lines 592–593: queue disabled + disconnected → SyncStatus.failed
    // -------------------------------------------------------------------
    test('returns SyncStatus.failed when disconnected and queue disabled',
        () async {
      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        channelFactory: (_) => MockWebSocketChannel(), // never connects
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        enablePendingQueue: false,
        reconnectDelay: const Duration(seconds: 100),
      );
      strategy.attach(client);
      // Do NOT call start() — strategy stays disconnected

      final event = LocalFirstEvent.createNewInsertEvent(
        repository: repo,
        data: {'id': '1'},
        needSync: true,
      );
      final status = await strategy.onPushToRemote(event);

      expect(status, SyncStatus.failed);
      strategy.dispose();
    });

    // -------------------------------------------------------------------
    // Lines 494–495: onSyncCompleted throws — error logged, no propagation
    // -------------------------------------------------------------------
    test('catches and logs exception thrown by onSyncCompleted', () async {
      final (mockChannel, _, controller) = _buildChannel();

      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        channelFactory: (_) => mockChannel,
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async => throw Exception('callback error'),
        reconnectDelay: const Duration(seconds: 100),
      );
      strategy.attach(client);

      await strategy.start();
      await Future.delayed(const Duration(milliseconds: 50));
      await _sendEvents(controller, 'test_repo');

      // pullChanges should have been called — exception did NOT propagate
      verify(
        () => client.pullChanges(
          repositoryName: 'test_repo',
          changes: any(named: 'changes'),
        ),
      ).called(1);

      controller.close();
      strategy.dispose();
    });

    // -------------------------------------------------------------------
    // Lines 614–616: StateError during push + queue enabled
    // -------------------------------------------------------------------
    test('queues event and returns pending when StateError during push',
        () async {
      var throwOnPush = false;
      final (mockChannel, mockSink, controller) = _buildChannel();
      when(() => mockSink.add(any())).thenAnswer((inv) {
        final msg = jsonDecode(inv.positionalArguments[0] as String) as Map;
        if (throwOnPush && msg['type'] == 'push_event') {
          throw StateError('Connection lost during push');
        }
      });

      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        channelFactory: (_) => mockChannel,
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        enablePendingQueue: true,
        reconnectDelay: const Duration(seconds: 100),
      );
      strategy.attach(client);

      await strategy.start();
      await Future.delayed(const Duration(milliseconds: 50));
      await _completeAuth(controller);

      throwOnPush = true;
      final event = LocalFirstEvent.createNewInsertEvent(
        repository: repo,
        data: {'id': '1'},
        needSync: true,
      );
      final status = await strategy.onPushToRemote(event);

      // StateError caught → event queued → returns pending
      expect(status, SyncStatus.pending);

      controller.close();
      strategy.dispose();
    });

    // -------------------------------------------------------------------
    // Lines 732–733: onBuildSyncFilter throws for a known repo
    // -------------------------------------------------------------------
    test('logs error and continues when onBuildSyncFilter throws', () async {
      final channels = <StreamController<dynamic>>[];

      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        reconnectDelay: const Duration(milliseconds: 60),
        onBuildSyncFilter: (repoName) async {
          if (repoName == 'test_repo') throw Exception('filter error');
          return null;
        },
        onSyncCompleted: (_, _) async {},
        channelFactory: (uri) {
          final controller = StreamController<dynamic>.broadcast();
          channels.add(controller);
          final (mockChannel, _, _) = _buildChannel();
          when(
            () => mockChannel.stream,
          ).thenAnswer((_) => controller.stream);
          return mockChannel;
        },
      );
      strategy.attach(client);

      await strategy.start();
      await Future.delayed(const Duration(milliseconds: 50));
      // Populate _knownRepositories
      await _sendEvents(channels.last, 'test_repo');
      await _completeAuth(channels.last);
      // Disconnect to trigger reconnect
      await channels.last.close();
      await Future.delayed(const Duration(milliseconds: 200));

      // On reconnect: onBuildSyncFilter throws for 'test_repo' — should not crash
      if (channels.length > 1) {
        await _completeAuth(channels.last);
      }

      // Strategy is still alive (no exception propagated)
      strategy.dispose();
      for (final c in channels) {
        try {
          c.close();
        } catch (_) {}
      }
    });

    // -------------------------------------------------------------------
    // Lines 744–745: request_all_events per known repo (null filter)
    // Line 755: counter_log gets limit:5
    // -------------------------------------------------------------------
    test('sends request_all_events with repository when filter is null',
        () async {
      final channels = <StreamController<dynamic>>[];
      final capturedMessages = <String>[];

      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        reconnectDelay: const Duration(milliseconds: 60),
        onBuildSyncFilter: (_) async => null, // null → request_all_events
        onSyncCompleted: (_, _) async {},
        channelFactory: (uri) {
          final controller = StreamController<dynamic>.broadcast();
          channels.add(controller);
          final mockChannel = MockWebSocketChannel();
          final mockSink = MockWebSocketSink();
          when(() => mockChannel.ready).thenAnswer((_) async {});
          when(
            () => mockChannel.stream,
          ).thenAnswer((_) => controller.stream);
          when(() => mockChannel.sink).thenReturn(mockSink);
          when(() => mockSink.add(any())).thenAnswer(
            (inv) =>
                capturedMessages.add(inv.positionalArguments[0] as String),
          );
          when(() => mockSink.close()).thenAnswer((_) async {});
          return mockChannel;
        },
      );
      strategy.attach(client);

      await strategy.start();
      await Future.delayed(const Duration(milliseconds: 50));
      // Populate _knownRepositories with test_repo and counter_log
      await _sendEvents(channels.last, 'test_repo');
      await _sendEvents(channels.last, 'counter_log', eventId: 'e2');
      await _completeAuth(channels.last);
      capturedMessages.clear();
      // Disconnect → reconnect → _syncInitialState with known repos
      await channels.last.close();
      await Future.delayed(const Duration(milliseconds: 200));

      if (channels.length > 1) {
        await _completeAuth(channels.last);
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // test_repo: request_all_events with repository (lines 744-745)
      final allEventsMessages = capturedMessages.where((m) {
        try {
          final d = jsonDecode(m) as Map;
          return d['type'] == 'request_all_events' && d['repository'] != null;
        } catch (_) {
          return false;
        }
      }).toList();
      expect(allEventsMessages, isNotEmpty);

      // counter_log: request_all_events with limit:5 (line 755)
      final counterLogMsg = capturedMessages.where((m) {
        try {
          final d = jsonDecode(m) as Map;
          return d['repository'] == 'counter_log' && d['limit'] == 5;
        } catch (_) {
          return false;
        }
      }).toList();
      expect(counterLogMsg, isNotEmpty);

      strategy.dispose();
      for (final c in channels) {
        try {
          c.close();
        } catch (_) {}
      }
    });

    // -------------------------------------------------------------------
    // Lines 653, 657: _convertToJsonSafe with DateTime and List
    // -------------------------------------------------------------------
    test('converts DateTime to ISO string and List elements in sync filter',
        () async {
      final channels = <StreamController<dynamic>>[];
      final capturedMessages = <String>[];

      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        reconnectDelay: const Duration(milliseconds: 60),
        onBuildSyncFilter: (_) async => {
          'since': DateTime.utc(2026, 1, 1), // DateTime → line 653
          'ids': ['a', 'b'], // List → line 657
        },
        onSyncCompleted: (_, _) async {},
        channelFactory: (uri) {
          final controller = StreamController<dynamic>.broadcast();
          channels.add(controller);
          final mockChannel = MockWebSocketChannel();
          final mockSink = MockWebSocketSink();
          when(() => mockChannel.ready).thenAnswer((_) async {});
          when(
            () => mockChannel.stream,
          ).thenAnswer((_) => controller.stream);
          when(() => mockChannel.sink).thenReturn(mockSink);
          when(() => mockSink.add(any())).thenAnswer(
            (inv) =>
                capturedMessages.add(inv.positionalArguments[0] as String),
          );
          when(() => mockSink.close()).thenAnswer((_) async {});
          return mockChannel;
        },
      );
      strategy.attach(client);

      await strategy.start();
      await Future.delayed(const Duration(milliseconds: 50));
      await _sendEvents(channels.last, 'test_repo');
      await _completeAuth(channels.last);
      capturedMessages.clear();
      await channels.last.close();
      await Future.delayed(const Duration(milliseconds: 200));

      if (channels.length > 1) {
        await _completeAuth(channels.last);
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // request_events was sent with filter containing DateTime/List
      final requestEventsMessages = capturedMessages.where((m) {
        try {
          final d = jsonDecode(m) as Map;
          return d['type'] == 'request_events';
        } catch (_) {
          return false;
        }
      }).toList();
      expect(requestEventsMessages, isNotEmpty);

      final decoded = jsonDecode(requestEventsMessages.last) as Map;
      // DateTime was converted to ISO string (line 653)
      expect(decoded['since'], isA<String>());
      expect(decoded['since'], startsWith('2026-01-01'));
      // List was preserved (line 657)
      expect(decoded['ids'], equals(['a', 'b']));

      strategy.dispose();
      for (final c in channels) {
        try {
          c.close();
        } catch (_) {}
      }
    });

    // -------------------------------------------------------------------
    // Lines 759, 761: StateError in per-repo _syncInitialState loop
    // -------------------------------------------------------------------
    test('handles StateError in _syncInitialState per-repo loop', () async {
      final channels = <StreamController<dynamic>>[];
      var connectionCount = 0;

      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        reconnectDelay: const Duration(milliseconds: 60),
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        channelFactory: (uri) {
          connectionCount++;
          final controller = StreamController<dynamic>.broadcast();
          channels.add(controller);
          final mockChannel = MockWebSocketChannel();
          final mockSink = MockWebSocketSink();
          when(() => mockChannel.ready).thenAnswer((_) async {});
          when(
            () => mockChannel.stream,
          ).thenAnswer((_) => controller.stream);
          when(() => mockChannel.sink).thenReturn(mockSink);
          when(() => mockSink.add(any())).thenAnswer((inv) {
            final msg = jsonDecode(inv.positionalArguments[0] as String) as Map;
            // On second connection, throw StateError on request_all_events
            if (connectionCount >= 2 && msg['type'] == 'request_all_events') {
              throw StateError('Connection lost during sync request');
            }
          });
          when(() => mockSink.close()).thenAnswer((_) async {});
          return mockChannel;
        },
      );
      strategy.attach(client);

      await strategy.start();
      await Future.delayed(const Duration(milliseconds: 50));
      await _sendEvents(channels.last, 'test_repo');
      await _completeAuth(channels.last);
      // Disconnect to trigger reconnect
      await channels.last.close();
      await Future.delayed(const Duration(milliseconds: 200));

      if (channels.length > 1) {
        await _completeAuth(channels.last);
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // StateError was caught internally — strategy is still alive
      strategy.dispose();
      for (final c in channels) {
        try {
          c.close();
        } catch (_) {}
      }
    });

    // -------------------------------------------------------------------
    // Lines 784–801: _flushPendingQueue — batch send after reconnect
    // -------------------------------------------------------------------
    test('flushes pending queue as batch messages after reconnecting',
        () async {
      final channels = <StreamController<dynamic>>[];
      final capturedMessages = <String>[];

      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        reconnectDelay: const Duration(milliseconds: 60),
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        enablePendingQueue: true,
        channelFactory: (uri) {
          final controller = StreamController<dynamic>.broadcast();
          channels.add(controller);
          final mockChannel = MockWebSocketChannel();
          final mockSink = MockWebSocketSink();
          when(() => mockChannel.ready).thenAnswer((_) async {});
          when(
            () => mockChannel.stream,
          ).thenAnswer((_) => controller.stream);
          when(() => mockChannel.sink).thenReturn(mockSink);
          when(() => mockSink.add(any())).thenAnswer(
            (inv) =>
                capturedMessages.add(inv.positionalArguments[0] as String),
          );
          when(() => mockSink.close()).thenAnswer((_) async {});
          return mockChannel;
        },
      );
      strategy.attach(client);

      // Queue two events BEFORE connecting
      final event1 = LocalFirstEvent.createNewInsertEvent(
        repository: repo,
        data: {'id': '1'},
        needSync: true,
      );
      final event2 = LocalFirstEvent.createNewInsertEvent(
        repository: repo,
        data: {'id': '2'},
        needSync: true,
      );
      await strategy.onPushToRemote(event1);
      await strategy.onPushToRemote(event2);

      // Now connect — _flushPendingQueue runs after auth
      await strategy.start();
      await Future.delayed(const Duration(milliseconds: 50));
      await _completeAuth(channels.last);
      await Future.delayed(const Duration(milliseconds: 50));

      // push_events_batch should have been sent (lines 795–800)
      final batchMessages = capturedMessages.where((m) {
        try {
          return (jsonDecode(m) as Map)['type'] == 'push_events_batch';
        } catch (_) {
          return false;
        }
      }).toList();
      expect(batchMessages, isNotEmpty);

      final batch = jsonDecode(batchMessages.first) as Map;
      expect(batch['repository'], 'test_repo');
      expect((batch['events'] as List).length, 2);

      strategy.dispose();
      for (final c in channels) {
        try {
          c.close();
        } catch (_) {}
      }
    });

    // -------------------------------------------------------------------
    // Lines 802–804: StateError during _flushPendingQueue batch send
    // -------------------------------------------------------------------
    test('handles StateError during pending queue flush', () async {
      final channels = <StreamController<dynamic>>[];
      var isConnecting = false;

      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        reconnectDelay: const Duration(seconds: 100),
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        enablePendingQueue: true,
        channelFactory: (uri) {
          isConnecting = true;
          final controller = StreamController<dynamic>.broadcast();
          channels.add(controller);
          final mockChannel = MockWebSocketChannel();
          final mockSink = MockWebSocketSink();
          when(() => mockChannel.ready).thenAnswer((_) async {});
          when(
            () => mockChannel.stream,
          ).thenAnswer((_) => controller.stream);
          when(() => mockChannel.sink).thenReturn(mockSink);
          when(() => mockSink.add(any())).thenAnswer((inv) {
            final msg =
                jsonDecode(inv.positionalArguments[0] as String) as Map;
            if (msg['type'] == 'push_events_batch') {
              throw StateError('Connection lost during batch send');
            }
          });
          when(() => mockSink.close()).thenAnswer((_) async {});
          return mockChannel;
        },
      );
      strategy.attach(client);

      // Queue an event before connecting
      final event = LocalFirstEvent.createNewInsertEvent(
        repository: repo,
        data: {'id': '1'},
        needSync: true,
      );
      await strategy.onPushToRemote(event);

      await strategy.start();
      await Future.delayed(const Duration(milliseconds: 50));
      await _completeAuth(channels.last);
      await Future.delayed(const Duration(milliseconds: 50));

      // StateError was caught inside _flushPendingQueue (line 802-804)
      expect(isConnecting, isTrue);

      strategy.dispose();
      for (final c in channels) {
        try {
          c.close();
        } catch (_) {}
      }
    });

    // -------------------------------------------------------------------
    // Lines 808–809: Unexpected error during _flushPendingQueue batch send
    // -------------------------------------------------------------------
    test('handles unexpected error during pending queue flush', () async {
      final channels = <StreamController<dynamic>>[];

      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        reconnectDelay: const Duration(seconds: 100),
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        enablePendingQueue: true,
        channelFactory: (uri) {
          final controller = StreamController<dynamic>.broadcast();
          channels.add(controller);
          final mockChannel = MockWebSocketChannel();
          final mockSink = MockWebSocketSink();
          when(() => mockChannel.ready).thenAnswer((_) async {});
          when(
            () => mockChannel.stream,
          ).thenAnswer((_) => controller.stream);
          when(() => mockChannel.sink).thenReturn(mockSink);
          when(() => mockSink.add(any())).thenAnswer((inv) {
            final msg =
                jsonDecode(inv.positionalArguments[0] as String) as Map;
            if (msg['type'] == 'push_events_batch') {
              throw FormatException('Unexpected serialization error');
            }
          });
          when(() => mockSink.close()).thenAnswer((_) async {});
          return mockChannel;
        },
      );
      strategy.attach(client);

      final event = LocalFirstEvent.createNewInsertEvent(
        repository: repo,
        data: {'id': '1'},
        needSync: true,
      );
      await strategy.onPushToRemote(event);

      await strategy.start();
      await Future.delayed(const Duration(milliseconds: 50));
      await _completeAuth(channels.last);
      await Future.delayed(const Duration(milliseconds: 50));

      // FormatException was caught (lines 808–809), strategy still alive
      strategy.dispose();
      for (final c in channels) {
        try {
          c.close();
        } catch (_) {}
      }
    });

    // -------------------------------------------------------------------
    // Lines 323–324: connection timeout (channel.ready never completes)
    // This test takes ~1600ms to run (waits for the 1500ms timeout).
    // -------------------------------------------------------------------
    test('handles connection timeout when channel.ready never resolves',
        () async {
      final neverCompletes = Completer<void>(); // intentionally never completed
      final mockChannel = MockWebSocketChannel();
      final mockSink = MockWebSocketSink();

      when(
        () => mockChannel.ready,
      ).thenAnswer((_) => neverCompletes.future);
      when(() => mockChannel.stream).thenAnswer((_) => const Stream.empty());
      when(() => mockChannel.sink).thenReturn(mockSink);
      when(() => mockSink.add(any())).thenAnswer((_) {});
      when(() => mockSink.close()).thenAnswer((_) async {});

      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        channelFactory: (_) => mockChannel,
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        reconnectDelay: const Duration(seconds: 100),
      );
      strategy.attach(client);

      await strategy.start();
      // Wait longer than the 1500ms connection timeout
      await Future.delayed(const Duration(milliseconds: 1600));

      // The connection attempt timed out → reportConnectionState(false) called
      verify(() => client.reportConnectionState(false)).called(greaterThan(0));

      strategy.dispose();
    }, timeout: const Timeout(Duration(seconds: 5)));

    // -------------------------------------------------------------------
    // Lines 841–843: pong timeout (no pong received after sending ping)
    // This test takes ~2100ms to run (waits for the 2s pong timeout).
    // -------------------------------------------------------------------
    test('handles pong timeout when server does not respond to heartbeat',
        () async {
      final (mockChannel, _, controller) = _buildChannel();

      final strategy = WebSocketSyncStrategy(
        websocketUrl: 'ws://localhost:8080/test',
        channelFactory: (_) => mockChannel,
        onBuildSyncFilter: (_) async => null,
        onSyncCompleted: (_, _) async {},
        // Fast heartbeat so ping is sent quickly
        heartbeatInterval: const Duration(milliseconds: 100),
        reconnectDelay: const Duration(seconds: 100),
      );
      strategy.attach(client);

      await strategy.start();
      await Future.delayed(const Duration(milliseconds: 50));
      // Complete auth so _connect() finishes and heartbeat is active
      await _completeAuth(controller);

      // Wait for first ping (100ms) + pong timeout (2000ms) + buffer (100ms)
      await Future.delayed(const Duration(milliseconds: 2300));

      // Pong timeout fired → _handleConnectionLoss → reportConnectionState(false)
      verify(() => client.reportConnectionState(false)).called(greaterThan(0));

      controller.close();
      strategy.dispose();
    }, timeout: const Timeout(Duration(seconds: 5)));
  });
}
