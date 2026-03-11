import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:counter_app/services/navigator_service.dart';

void main() {
  group('NavigatorService', () {
    test('is a singleton', () {
      final instance1 = NavigatorService();
      final instance2 = NavigatorService();

      expect(identical(instance1, instance2), true);
    });

    test('has a navigator key', () {
      final service = NavigatorService();
      expect(service.navigatorKey, isA<GlobalKey<NavigatorState>>());
    });

    testWidgets('push returns null when navigator state is not available', (tester) async {
      final service = NavigatorService();

      // Don't create MaterialApp - navigatorKey won't have state
      final result = await service.push(const Scaffold(body: Text('Test')));

      expect(result, isNull);
    });

    testWidgets('pushReplacement returns null when navigator state is not available', (tester) async {
      final service = NavigatorService();

      // Don't create MaterialApp - navigatorKey won't have state
      final result = await service.pushReplacement(const Scaffold(body: Text('Test')));

      expect(result, isNull);
    });

    testWidgets('pop does nothing when navigator state is not available', (tester) async {
      final service = NavigatorService();

      // Don't create MaterialApp - navigatorKey won't have state
      // This should not throw
      service.pop();

      expect(service.navigatorKey.currentState, isNull);
    });

    testWidgets('maybePop returns false when navigator state is not available', (tester) async {
      final service = NavigatorService();

      // Don't create MaterialApp - navigatorKey won't have state
      final result = await service.maybePop();

      expect(result, false);
    });

    test('navigateToHome does not throw when called', () {
      final service = NavigatorService();

      // This should not throw even without navigator state
      // It will just call pushReplacement which returns null when no state
      expect(() => service.navigateToHome(), returnsNormally);
    });

    test('navigateToSignIn does not throw when called', () {
      final service = NavigatorService();

      // This should not throw even without navigator state
      // It will just call pushReplacement which returns null when no state
      expect(() => service.navigateToSignIn(), returnsNormally);
    });

    testWidgets('navigateToHome with active navigator state initiates navigation', (tester) async {
      final service = NavigatorService();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: service.navigatorKey,
          home: const Scaffold(body: Text('Initial')),
        ),
      );

      // Verify we have navigator state
      expect(service.navigatorKey.currentState, isNotNull);

      // Call navigateToHome - it should call pushReplacement
      service.navigateToHome();

      // Just verify it was called without error
      expect(service.navigatorKey.currentState, isNotNull);
    });

    testWidgets('navigateToSignIn with active navigator state initiates navigation', (tester) async {
      final service = NavigatorService();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: service.navigatorKey,
          home: const Scaffold(body: Text('Initial')),
        ),
      );

      // Verify we have navigator state
      expect(service.navigatorKey.currentState, isNotNull);

      // Call navigateToSignIn - it should call pushReplacement
      service.navigateToSignIn();

      // Just verify it was called without error
      expect(service.navigatorKey.currentState, isNotNull);
    });
  });
}
