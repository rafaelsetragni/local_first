import 'package:flutter_test/flutter_test.dart';
import 'package:counter_app/services/sync_state_manager.dart';
import 'package:local_first/local_first.dart';
import 'package:mocktail/mocktail.dart';

class MockLocalFirstClient extends Mock implements LocalFirstClient {}

void main() {
  group('SyncStateManager', () {
    late MockLocalFirstClient mockClient;
    late SyncStateManager manager;
    late String currentNamespace;

    setUp(() {
      mockClient = MockLocalFirstClient();
      currentNamespace = 'user__testuser';
      manager = SyncStateManager(mockClient, () => currentNamespace);
    });

    test('getLastSequence returns null when no value exists', () async {
      when(() => mockClient.getConfigValue(any())).thenAnswer((_) async => null);

      final result = await manager.getLastSequence('user');

      expect(result, null);
      verify(() => mockClient.getConfigValue('user__testuser___last_sequence__user')).called(1);
    });

    test('getLastSequence returns parsed int when value exists', () async {
      when(() => mockClient.getConfigValue(any())).thenAnswer((_) async => '42');

      final result = await manager.getLastSequence('user');

      expect(result, 42);
    });

    test('getLastSequence returns null when value is not a valid int', () async {
      when(() => mockClient.getConfigValue(any())).thenAnswer((_) async => 'invalid');

      final result = await manager.getLastSequence('user');

      expect(result, null);
    });

    test('saveLastSequence stores value correctly', () async {
      when(() => mockClient.setConfigValue(any(), any())).thenAnswer((_) async => true);

      await manager.saveLastSequence('user', 42);

      verify(() => mockClient.setConfigValue('user__testuser___last_sequence__user', '42')).called(1);
    });

    test('buildSequenceKey uses current namespace', () async {
      when(() => mockClient.getConfigValue(any())).thenAnswer((_) async => null);

      // Change namespace
      currentNamespace = 'user__anotheruser';

      await manager.getLastSequence('counter_log');

      verify(() => mockClient.getConfigValue('user__anotheruser___last_sequence__counter_log')).called(1);
    });

    test('extractMaxSequence returns null for empty list', () {
      final result = manager.extractMaxSequence([]);

      expect(result, null);
    });

    test('extractMaxSequence returns max sequence from events', () {
      final events = [
        {'serverSequence': 5},
        {'serverSequence': 10},
        {'serverSequence': 3},
      ];

      final result = manager.extractMaxSequence(events);

      expect(result, 10);
    });

    test('extractMaxSequence ignores events without serverSequence', () {
      final events = [
        {'serverSequence': 5},
        {'other': 'data'},
        {'serverSequence': 10},
      ];

      final result = manager.extractMaxSequence(events);

      expect(result, 10);
    });

    test('extractMaxSequence ignores non-int serverSequence values', () {
      final events = [
        {'serverSequence': 5},
        {'serverSequence': 'not_a_number'},
        {'serverSequence': 10},
      ];

      final result = manager.extractMaxSequence(events);

      expect(result, 10);
    });

    test('extractMaxSequence returns single sequence when only one exists', () {
      final events = [
        {'serverSequence': 42},
      ];

      final result = manager.extractMaxSequence(events);

      expect(result, 42);
    });

    test('extractMaxSequence handles all same values', () {
      final events = [
        {'serverSequence': 5},
        {'serverSequence': 5},
        {'serverSequence': 5},
      ];

      final result = manager.extractMaxSequence(events);

      expect(result, 5);
    });
  });
}
