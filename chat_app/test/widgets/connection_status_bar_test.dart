import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:chat_app/widgets/connection_status_bar.dart';
import 'package:chat_app/services/repository_service.dart';

class MockRepositoryService extends Mock implements RepositoryService {}

void main() {
  late MockRepositoryService mockService;
  late StreamController<bool> connectionController;

  setUp(() {
    mockService = MockRepositoryService();
    connectionController = StreamController<bool>.broadcast();

    when(() => mockService.isConnected).thenReturn(true);
    when(() => mockService.connectionState)
        .thenAnswer((_) => connectionController.stream);

    RepositoryService.instance = mockService;
  });

  tearDown(() {
    connectionController.close();
    RepositoryService.instance = null;
  });

  group('ConnectionStatusBar', () {
    testWidgets('shows child when connected', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectionStatusBar(
            child: Text('Content'),
          ),
        ),
      );

      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('has zero height container when connected', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectionStatusBar(
            child: Text('Content'),
          ),
        ),
      );

      // When connected, the AnimatedContainer has height 0
      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(container.constraints?.maxHeight, 0);
    });

    testWidgets('has non-zero height container when disconnected',
        (tester) async {
      when(() => mockService.isConnected).thenReturn(false);

      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectionStatusBar(
            child: Text('Content'),
          ),
        ),
      );

      // When disconnected, the AnimatedContainer has height > 0
      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      // Height should be topPadding + 28, but topPadding might be 0 in tests
      // Just check it's greater than 0
      expect((container.constraints?.maxHeight ?? 0) >= 28, true);
    });

    testWidgets('always shows child content when disconnected', (tester) async {
      when(() => mockService.isConnected).thenReturn(false);

      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectionStatusBar(
            child: Text('Always Visible'),
          ),
        ),
      );

      expect(find.text('Always Visible'), findsOneWidget);
    });

    testWidgets('updates container height when connection state changes',
        (tester) async {
      when(() => mockService.isConnected).thenReturn(true);

      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectionStatusBar(
            child: Text('Content'),
          ),
        ),
      );

      // Start connected - height should be 0
      var container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(container.constraints?.maxHeight, 0);

      // Simulate disconnect
      connectionController.add(false);
      await tester.pumpAndSettle();

      container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect((container.constraints?.maxHeight ?? 0) > 0, true);

      // Simulate reconnect
      connectionController.add(true);
      await tester.pumpAndSettle();

      container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(container.constraints?.maxHeight, 0);
    });

    testWidgets('uses Column layout', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectionStatusBar(
            child: Text('Content'),
          ),
        ),
      );

      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('has AnimatedContainer for smooth transitions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectionStatusBar(
            child: Text('Content'),
          ),
        ),
      );

      expect(find.byType(AnimatedContainer), findsOneWidget);
    });

    testWidgets('child is in Expanded widget', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectionStatusBar(
            child: Text('Content'),
          ),
        ),
      );

      expect(find.byType(Expanded), findsOneWidget);
    });

    testWidgets('contains Connecting text widget', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectionStatusBar(
            child: Text('Content'),
          ),
        ),
      );

      // The text is always present in the widget tree
      expect(find.text('Connecting...'), findsOneWidget);
    });

    testWidgets('AnimatedContainer exists in disconnected state', (tester) async {
      when(() => mockService.isConnected).thenReturn(false);

      await tester.pumpWidget(
        const MaterialApp(
          home: ConnectionStatusBar(
            child: Text('Content'),
          ),
        ),
      );

      // Verify the AnimatedContainer is present
      expect(find.byType(AnimatedContainer), findsOneWidget);
      // And the "Connecting..." text is in the tree
      expect(find.text('Connecting...'), findsOneWidget);
    });
  });
}
