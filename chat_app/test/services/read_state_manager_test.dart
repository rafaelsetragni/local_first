import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:local_first/local_first.dart';
import 'package:chat_app/services/read_state_manager.dart';

class MockLocalFirstClient extends Mock implements LocalFirstClient {}

void main() {
  group('ReadStateManager', () {
    late MockLocalFirstClient mockClient;
    late ReadStateManager manager;
    late String currentNamespace;

    setUp(() {
      mockClient = MockLocalFirstClient();
      currentNamespace = 'user_testuser';
      manager = ReadStateManager(mockClient, () => currentNamespace);
    });

    group('getLastReadAt', () {
      test('returns null when no value stored', () async {
        when(() => mockClient.getConfigValue(any())).thenAnswer((_) async => null);

        final result = await manager.getLastReadAt('chat1');

        expect(result, isNull);
      });

      test('returns null when empty string stored', () async {
        when(() => mockClient.getConfigValue(any())).thenAnswer((_) async => '');

        final result = await manager.getLastReadAt('chat1');

        expect(result, isNull);
      });

      test('returns null when invalid date stored', () async {
        when(() => mockClient.getConfigValue(any())).thenAnswer((_) async => 'not_a_date');

        final result = await manager.getLastReadAt('chat1');

        expect(result, isNull);
      });

      test('returns DateTime when valid ISO8601 string stored', () async {
        final timestamp = DateTime.utc(2024, 1, 15, 12, 30, 45);
        when(() => mockClient.getConfigValue(any()))
            .thenAnswer((_) async => timestamp.toIso8601String());

        final result = await manager.getLastReadAt('chat1');

        expect(result, timestamp);
      });

      test('uses namespace-aware key', () async {
        when(() => mockClient.getConfigValue(any())).thenAnswer((_) async => null);

        await manager.getLastReadAt('chat1');

        verify(() => mockClient.getConfigValue('user_testuser___last_read__chat1')).called(1);
      });

      test('uses different key for different chats', () async {
        when(() => mockClient.getConfigValue(any())).thenAnswer((_) async => null);

        await manager.getLastReadAt('chat1');
        await manager.getLastReadAt('chat2');

        verify(() => mockClient.getConfigValue('user_testuser___last_read__chat1')).called(1);
        verify(() => mockClient.getConfigValue('user_testuser___last_read__chat2')).called(1);
      });
    });

    group('saveLastReadAt', () {
      test('saves timestamp with namespace-aware key', () async {
        final timestamp = DateTime.utc(2024, 1, 15, 12, 30, 45);
        when(() => mockClient.setConfigValue(any(), any())).thenAnswer((_) async => true);

        await manager.saveLastReadAt('chat1', timestamp);

        verify(() => mockClient.setConfigValue(
          'user_testuser___last_read__chat1',
          timestamp.toIso8601String(),
        )).called(1);
      });

      test('converts local time to UTC before saving', () async {
        final localTime = DateTime(2024, 1, 15, 12, 30, 45);
        when(() => mockClient.setConfigValue(any(), any())).thenAnswer((_) async => true);

        await manager.saveLastReadAt('chat1', localTime);

        verify(() => mockClient.setConfigValue(
          any(),
          localTime.toUtc().toIso8601String(),
        )).called(1);
      });
    });

    group('markChatAsRead', () {
      test('saves current UTC timestamp', () async {
        when(() => mockClient.setConfigValue(any(), any())).thenAnswer((_) async => true);

        final before = DateTime.now().toUtc();
        await manager.markChatAsRead('chat1');
        final after = DateTime.now().toUtc();

        final capturedValue = verify(() => mockClient.setConfigValue(
          'user_testuser___last_read__chat1',
          captureAny(),
        )).captured.single as String;

        final savedTime = DateTime.parse(capturedValue);
        expect(savedTime.isAfter(before.subtract(Duration(seconds: 1))), true);
        expect(savedTime.isBefore(after.add(Duration(seconds: 1))), true);
      });
    });

    group('deleteReadState', () {
      test('sets empty string for the chat read state', () async {
        when(() => mockClient.setConfigValue(any(), any())).thenAnswer((_) async => true);

        await manager.deleteReadState('chat1');

        verify(() => mockClient.setConfigValue(
          'user_testuser___last_read__chat1',
          '',
        )).called(1);
      });

      test('uses correct namespace-aware key', () async {
        when(() => mockClient.setConfigValue(any(), any())).thenAnswer((_) async => true);

        currentNamespace = 'user_other';
        await manager.deleteReadState('chat2');

        verify(() => mockClient.setConfigValue(
          'user_other___last_read__chat2',
          '',
        )).called(1);
      });
    });

    group('namespace isolation', () {
      test('different users have different read states', () async {
        when(() => mockClient.getConfigValue(any())).thenAnswer((_) async => null);
        when(() => mockClient.setConfigValue(any(), any())).thenAnswer((_) async => true);

        // User 1 marks chat as read
        currentNamespace = 'user_alice';
        await manager.markChatAsRead('chat1');

        // User 2 gets read state
        currentNamespace = 'user_bob';
        await manager.getLastReadAt('chat1');

        // Verify different keys were used
        verify(() => mockClient.setConfigValue(
          'user_alice___last_read__chat1',
          any(),
        )).called(1);
        verify(() => mockClient.getConfigValue(
          'user_bob___last_read__chat1',
        )).called(1);
      });
    });
  });
}
