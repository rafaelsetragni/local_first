import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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

  group('UnreadCountsProvider', () {
    testWidgets('provides empty counts initially', (tester) async {
      int? count;

      await tester.pumpWidget(
        MaterialApp(
          home: UnreadCountsProvider(
            child: Builder(
              builder: (context) {
                count = UnreadCountsProvider.getCount(context, 'chat1');
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(count, 0);
    });

    testWidgets('provides initial counts from service', (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 5, 'chat2': 10});

      int? count1;
      int? count2;

      await tester.pumpWidget(
        MaterialApp(
          home: UnreadCountsProvider(
            child: Builder(
              builder: (context) {
                count1 = UnreadCountsProvider.getCount(context, 'chat1');
                count2 = UnreadCountsProvider.getCount(context, 'chat2');
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(count1, 5);
      expect(count2, 10);
    });

    testWidgets('returns 0 for unknown chat', (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 5});

      int? count;

      await tester.pumpWidget(
        MaterialApp(
          home: UnreadCountsProvider(
            child: Builder(
              builder: (context) {
                count = UnreadCountsProvider.getCount(context, 'unknown');
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(count, 0);
    });

    testWidgets('getCounts returns all counts', (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 5, 'chat2': 10});

      Map<String, int>? counts;

      await tester.pumpWidget(
        MaterialApp(
          home: UnreadCountsProvider(
            child: Builder(
              builder: (context) {
                counts = UnreadCountsProvider.getCounts(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(counts, {'chat1': 5, 'chat2': 10});
    });

    testWidgets('updates counts when stream emits', (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 5});

      int? count;

      await tester.pumpWidget(
        MaterialApp(
          home: UnreadCountsProvider(
            child: Builder(
              builder: (context) {
                count = UnreadCountsProvider.getCount(context, 'chat1');
                return Text('Count: $count');
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(count, 5);

      // Update via stream
      unreadController.add({'chat1': 15});
      await tester.pumpAndSettle();

      expect(find.text('Count: 15'), findsOneWidget);
    });

    testWidgets('does not rebuild when counts are equal', (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 5});

      int buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: UnreadCountsProvider(
            child: Builder(
              builder: (context) {
                UnreadCountsProvider.getCount(context, 'chat1');
                buildCount++;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final initialBuildCount = buildCount;

      // Send same counts
      unreadController.add({'chat1': 5});
      await tester.pump();

      // Should not trigger extra rebuild
      expect(buildCount, initialBuildCount);
    });

    testWidgets('renders child widget', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: UnreadCountsProvider(
            child: Text('Child Content'),
          ),
        ),
      );

      expect(find.text('Child Content'), findsOneWidget);
    });

    testWidgets('getCount returns 0 when no provider', (tester) async {
      int? count;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              count = UnreadCountsProvider.getCount(context, 'chat1');
              return const SizedBox();
            },
          ),
        ),
      );

      expect(count, 0);
    });

    testWidgets('getCounts returns empty map when no provider', (tester) async {
      Map<String, int>? counts;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              counts = UnreadCountsProvider.getCounts(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(counts, isEmpty);
    });

    testWidgets('handles multiple chats', (tester) async {
      when(() => mockService.getUnreadCountsMap()).thenAnswer(
          (_) async => {'chat1': 1, 'chat2': 2, 'chat3': 3, 'chat4': 0});

      Map<String, int>? counts;

      await tester.pumpWidget(
        MaterialApp(
          home: UnreadCountsProvider(
            child: Builder(
              builder: (context) {
                counts = UnreadCountsProvider.getCounts(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(counts?['chat1'], 1);
      expect(counts?['chat2'], 2);
      expect(counts?['chat3'], 3);
      expect(counts?['chat4'], 0);
    });

    testWidgets('handles count updates for new chats', (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 5});

      int? chat1Count;
      int? chat2Count;

      await tester.pumpWidget(
        MaterialApp(
          home: UnreadCountsProvider(
            child: Builder(
              builder: (context) {
                chat1Count = UnreadCountsProvider.getCount(context, 'chat1');
                chat2Count = UnreadCountsProvider.getCount(context, 'chat2');
                return Text('$chat1Count, $chat2Count');
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(chat1Count, 5);
      expect(chat2Count, 0);

      // Add a new chat with unread messages
      unreadController.add({'chat1': 5, 'chat2': 7});
      await tester.pumpAndSettle();

      expect(find.text('5, 7'), findsOneWidget);
    });

    testWidgets('handles chat removal from counts', (tester) async {
      when(() => mockService.getUnreadCountsMap())
          .thenAnswer((_) async => {'chat1': 5, 'chat2': 10});

      await tester.pumpWidget(
        MaterialApp(
          home: UnreadCountsProvider(
            child: Builder(
              builder: (context) {
                final counts = UnreadCountsProvider.getCounts(context);
                return Text('Chats: ${counts.length}');
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Chats: 2'), findsOneWidget);

      // Remove a chat
      unreadController.add({'chat1': 5});
      await tester.pumpAndSettle();

      expect(find.text('Chats: 1'), findsOneWidget);
    });

    testWidgets('disposes subscription on widget disposal', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: UnreadCountsProvider(
            child: Text('Content'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Dispose by pumping a different widget
      await tester.pumpWidget(
        const MaterialApp(
          home: Text('Different'),
        ),
      );

      // Stream should still be functional for other listeners
      // (we can't directly test disposal, but this ensures no errors)
      expect(find.text('Different'), findsOneWidget);
    });
  });
}
