import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:counter_app/widgets/counter_log_tile.dart';
import 'package:counter_app/models/counter_log_model.dart';

void main() {
  group('CounterLogTile', () {
    testWidgets('displays log message and avatar', (tester) async {
      final log = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: 5,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CounterLogTile(
              log: log,
              avatarUrl: '',
            ),
          ),
        ),
      );

      expect(find.text('Increased by 5 by testuser'), findsOneWidget);
      expect(find.byType(Row), findsWidgets);
    });

    testWidgets('displays formatted date', (tester) async {
      final log = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: 5,
        createdAt: DateTime(2024, 3, 15, 14, 30, 45).toUtc(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CounterLogTile(
              log: log,
              avatarUrl: '',
            ),
          ),
        ),
      );

      // Should find the formatted date text
      expect(find.textContaining('/'), findsOneWidget);
      expect(find.textContaining(':'), findsOneWidget);
    });

    testWidgets('displays decrease message for negative increment', (tester) async {
      final log = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: -3,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CounterLogTile(
              log: log,
              avatarUrl: '',
            ),
          ),
        ),
      );

      expect(find.text('Decreased by 3 by testuser'), findsOneWidget);
    });

    testWidgets('displays avatar using AvatarPreview widget', (tester) async {
      final log = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CounterLogTile(
              log: log,
              avatarUrl: '',
            ),
          ),
        ),
      );

      // Check for CircleAvatar widget (part of AvatarPreview)
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('uses Column layout for log details', (tester) async {
      final log = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CounterLogTile(
              log: log,
              avatarUrl: '',
            ),
          ),
        ),
      );

      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('applies correct text styles', (tester) async {
      final log = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CounterLogTile(
              log: log,
              avatarUrl: '',
            ),
          ),
        ),
      );

      // Find the log message text
      final logText = tester.widget<Text>(
        find.text('Increased by 1 by testuser'),
      );
      expect(logText.style, isNotNull);
    });

    testWidgets('expands content to fill available width', (tester) async {
      final log = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CounterLogTile(
              log: log,
              avatarUrl: '',
            ),
          ),
        ),
      );

      expect(find.byType(Expanded), findsOneWidget);
    });

    testWidgets('applies vertical padding', (tester) async {
      final log = CounterLogModel(
        username: 'testuser',
        sessionId: 'session123',
        increment: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CounterLogTile(
              log: log,
              avatarUrl: '',
            ),
          ),
        ),
      );

      final padding = tester.widget<Padding>(
        find.byType(Padding).first,
      );
      expect(padding.padding, const EdgeInsets.symmetric(vertical: 4.0));
    });
  });
}
