import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:local_first/local_first.dart';
import 'package:chat_app/services/sync_state_manager.dart';

class MockLocalFirstClient extends Mock implements LocalFirstClient {}

void main() {
  group('SyncStateManager', () {
    late MockLocalFirstClient mockClient;
    late SyncStateManager manager;
    late String currentNamespace;

    setUp(() {
      mockClient = MockLocalFirstClient();
      currentNamespace = 'user_testuser';
      manager = SyncStateManager(mockClient, () => currentNamespace);
    });

    group('getLastSequence', () {
      test('returns null when no value stored', () async {
        when(() => mockClient.getConfigValue(any())).thenAnswer((_) async => null);

        final result = await manager.getLastSequence('user');

        expect(result, isNull);
      });

      test('returns null when empty string stored', () async {
        when(() => mockClient.getConfigValue(any())).thenAnswer((_) async => '');

        final result = await manager.getLastSequence('user');

        expect(result, isNull);
      });

      test('returns null when invalid number stored', () async {
        when(() => mockClient.getConfigValue(any())).thenAnswer((_) async => 'not_a_number');

        final result = await manager.getLastSequence('user');

        expect(result, isNull);
      });

      test('returns sequence number when valid value stored', () async {
        when(() => mockClient.getConfigValue(any())).thenAnswer((_) async => '42');

        final result = await manager.getLastSequence('user');

        expect(result, 42);
      });

      test('uses namespace-aware key', () async {
        when(() => mockClient.getConfigValue(any())).thenAnswer((_) async => '100');

        await manager.getLastSequence('chat');

        verify(() => mockClient.getConfigValue('user_testuser___last_sequence__chat')).called(1);
      });

      test('uses different key for different namespaces', () async {
        when(() => mockClient.getConfigValue(any())).thenAnswer((_) async => '100');

        await manager.getLastSequence('user');
        currentNamespace = 'user_other';
        await manager.getLastSequence('user');

        verify(() => mockClient.getConfigValue('user_testuser___last_sequence__user')).called(1);
        verify(() => mockClient.getConfigValue('user_other___last_sequence__user')).called(1);
      });
    });

    group('saveLastSequence', () {
      test('saves sequence with namespace-aware key', () async {
        when(() => mockClient.setConfigValue(any(), any())).thenAnswer((_) async => true);

        await manager.saveLastSequence('user', 42);

        verify(() => mockClient.setConfigValue(
          'user_testuser___last_sequence__user',
          '42',
        )).called(1);
      });

      test('saves different sequences for different repositories', () async {
        when(() => mockClient.setConfigValue(any(), any())).thenAnswer((_) async => true);

        await manager.saveLastSequence('user', 10);
        await manager.saveLastSequence('chat', 20);
        await manager.saveLastSequence('message', 30);

        verify(() => mockClient.setConfigValue(
          'user_testuser___last_sequence__user',
          '10',
        )).called(1);
        verify(() => mockClient.setConfigValue(
          'user_testuser___last_sequence__chat',
          '20',
        )).called(1);
        verify(() => mockClient.setConfigValue(
          'user_testuser___last_sequence__message',
          '30',
        )).called(1);
      });
    });

    group('extractMaxSequence', () {
      test('returns null for empty list', () {
        final result = manager.extractMaxSequence([]);

        expect(result, isNull);
      });

      test('returns null when no events have serverSequence', () {
        final events = [
          {'id': '1', 'data': {}},
          {'id': '2', 'data': {}},
        ];

        final result = manager.extractMaxSequence(events);

        expect(result, isNull);
      });

      test('returns single sequence when only one event', () {
        final events = [
          {'id': '1', 'serverSequence': 42},
        ];

        final result = manager.extractMaxSequence(events);

        expect(result, 42);
      });

      test('returns max sequence from multiple events', () {
        final events = [
          {'id': '1', 'serverSequence': 10},
          {'id': '2', 'serverSequence': 50},
          {'id': '3', 'serverSequence': 30},
        ];

        final result = manager.extractMaxSequence(events);

        expect(result, 50);
      });

      test('ignores non-integer serverSequence values', () {
        final events = [
          {'id': '1', 'serverSequence': 10},
          {'id': '2', 'serverSequence': 'invalid'},
          {'id': '3', 'serverSequence': 30},
        ];

        final result = manager.extractMaxSequence(events);

        expect(result, 30);
      });

      test('handles mixed events with and without serverSequence', () {
        final events = [
          {'id': '1', 'serverSequence': 10},
          {'id': '2', 'data': {}},
          {'id': '3', 'serverSequence': 20},
        ];

        final result = manager.extractMaxSequence(events);

        expect(result, 20);
      });
    });
  });
}
