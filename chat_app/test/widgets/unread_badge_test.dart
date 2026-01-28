import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:chat_app/widgets/unread_badge.dart';
import 'package:chat_app/widgets/unread_counts_provider.dart';
import 'package:chat_app/services/repository_service.dart';

class MockRepositoryService extends Mock implements RepositoryService {}

void main() {
  late MockRepositoryService mockService;
  late StreamController<Map<String, int>> unreadController;

  setUp(() {
    mockService = MockRepositoryService();
    unreadController = StreamController<Map<String, int>>.broadcast();

    when(() => mockService.getUnreadCountsMap())
        .thenAnswer((_) async => <String, int>{});
    when(() => mockService.watchUnreadCounts())
        .thenAnswer((_) => unreadController.stream);

    RepositoryService.instance = mockService;
  });

  tearDown(() {
    unreadController.close();
    RepositoryService.instance = null;
  });

  group('UnreadBadge', () {
    testWidgets('shows nothing when count is 0', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: UnreadCountsProvider(
            child: Scaffold(
              body: UnreadBadge(chatId: 'chat1'),
            ),
          ),
        ),
      );

      await tester.pump();

      // Should show SizedBox.shrink (no visible content)
      // The UnreadBadge widget returns SizedBox.shrink when count is 0
      final badge = tester.widget<UnreadBadge>(find.byType(UnreadBadge));
      expect(badge.chatId, 'chat1');
      // No text should be visible
      expect(find.textContaining(RegExp(r'\d')), findsNothing);
    });

    testWidgets('shows badge with count when greater than 0', (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 5});

      await tester.pumpWidget(
        const MaterialApp(
          home: UnreadCountsProvider(
            child: Scaffold(
              body: UnreadBadge(chatId: 'chat1'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('shows 99+ when count exceeds 99', (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 150});

      await tester.pumpWidget(
        const MaterialApp(
          home: UnreadCountsProvider(
            child: Scaffold(
              body: UnreadBadge(chatId: 'chat1'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('shows exact count at 99', (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 99});

      await tester.pumpWidget(
        const MaterialApp(
          home: UnreadCountsProvider(
            child: Scaffold(
              body: UnreadBadge(chatId: 'chat1'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('99'), findsOneWidget);
    });

    testWidgets('shows 99+ at 100', (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 100});

      await tester.pumpWidget(
        const MaterialApp(
          home: UnreadCountsProvider(
            child: Scaffold(
              body: UnreadBadge(chatId: 'chat1'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('updates when unread count changes', (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 3});

      await tester.pumpWidget(
        const MaterialApp(
          home: UnreadCountsProvider(
            child: Scaffold(
              body: UnreadBadge(chatId: 'chat1'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);

      // Update count
      unreadController.add({'chat1': 10});
      await tester.pumpAndSettle();

      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('shows nothing for unknown chat', (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 5});

      await tester.pumpWidget(
        const MaterialApp(
          home: UnreadCountsProvider(
            child: Scaffold(
              body: UnreadBadge(chatId: 'unknown'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show SizedBox.shrink for unknown chat (count defaults to 0)
      // No number text should be visible
      expect(find.textContaining(RegExp(r'\d')), findsNothing);
    });

    testWidgets('has Container with decoration when showing badge',
        (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 1});

      await tester.pumpWidget(
        const MaterialApp(
          home: UnreadCountsProvider(
            child: Scaffold(
              body: UnreadBadge(chatId: 'chat1'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final container = tester.widget<Container>(find.byType(Container));
      expect(container.decoration, isA<BoxDecoration>());
    });

    testWidgets('badge has rounded corners', (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 1});

      await tester.pumpWidget(
        const MaterialApp(
          home: UnreadCountsProvider(
            child: Scaffold(
              body: UnreadBadge(chatId: 'chat1'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(12));
    });

    testWidgets('uses primary color from theme', (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 1});

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
          ),
          home: const UnreadCountsProvider(
            child: Scaffold(
              body: UnreadBadge(chatId: 'chat1'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, isNotNull);
    });

    testWidgets('text has bold font weight', (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 5});

      await tester.pumpWidget(
        const MaterialApp(
          home: UnreadCountsProvider(
            child: Scaffold(
              body: UnreadBadge(chatId: 'chat1'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('5'));
      expect(text.style?.fontWeight, FontWeight.bold);
    });

    testWidgets('hides when count goes to 0', (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 5});

      await tester.pumpWidget(
        const MaterialApp(
          home: UnreadCountsProvider(
            child: Scaffold(
              body: UnreadBadge(chatId: 'chat1'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('5'), findsOneWidget);

      // Count goes to 0
      unreadController.add({'chat1': 0});
      await tester.pumpAndSettle();

      expect(find.text('5'), findsNothing);
      // No number text should be visible
      expect(find.textContaining(RegExp(r'\d')), findsNothing);
    });
  });
}
