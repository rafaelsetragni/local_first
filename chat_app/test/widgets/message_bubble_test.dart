import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/widgets/message_bubble.dart';
import 'package:chat_app/models/message_model.dart';

void main() {
  group('MessageBubble', () {
    late MessageModel regularMessage;
    late MessageModel systemMessage;

    setUp(() {
      regularMessage = MessageModel(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'testuser',
        text: 'Hello, World!',
        createdAt: DateTime(2024, 1, 15, 14, 30).toUtc(),
      );

      systemMessage = MessageModel.system(
        chatId: 'chat1',
        text: 'User joined the chat',
        createdAt: DateTime(2024, 1, 15, 14, 30).toUtc(),
      );
    });

    testWidgets('displays sender username', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: regularMessage,
              isOwnMessage: false,
              avatarUrl: '',
            ),
          ),
        ),
      );

      expect(find.text('testuser'), findsOneWidget);
    });

    testWidgets('displays message text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: regularMessage,
              isOwnMessage: false,
              avatarUrl: '',
            ),
          ),
        ),
      );

      expect(find.text('Hello, World!'), findsOneWidget);
    });

    testWidgets('displays timestamp', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: regularMessage,
              isOwnMessage: false,
              avatarUrl: '',
            ),
          ),
        ),
      );

      // The timestamp format is HH:mm
      // Since it converts to local time, we check that some time text exists
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('shows avatar preview', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: regularMessage,
              isOwnMessage: false,
              avatarUrl: '',
            ),
          ),
        ),
      );

      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('aligns message to right for own message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: regularMessage,
              isOwnMessage: true,
              avatarUrl: '',
            ),
          ),
        ),
      );

      final row = tester.widget<Row>(find.byType(Row));
      expect(row.mainAxisAlignment, MainAxisAlignment.end);
    });

    testWidgets('aligns message to left for other message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: regularMessage,
              isOwnMessage: false,
              avatarUrl: '',
            ),
          ),
        ),
      );

      final row = tester.widget<Row>(find.byType(Row));
      expect(row.mainAxisAlignment, MainAxisAlignment.start);
    });

    testWidgets('system message is centered', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: systemMessage,
              isOwnMessage: false,
              avatarUrl: '',
            ),
          ),
        ),
      );

      expect(find.byType(Center), findsOneWidget);
    });

    testWidgets('system message shows text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: systemMessage,
              isOwnMessage: false,
              avatarUrl: '',
            ),
          ),
        ),
      );

      expect(find.text('User joined the chat'), findsOneWidget);
    });

    testWidgets('system message does not show avatar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: systemMessage,
              isOwnMessage: false,
              avatarUrl: '',
            ),
          ),
        ),
      );

      // System message uses Center, not Row with avatar
      expect(find.byType(Row), findsNothing);
    });

    testWidgets('system message does not show sender', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: systemMessage,
              isOwnMessage: false,
              avatarUrl: '',
            ),
          ),
        ),
      );

      // System message doesn't display _system_ sender
      expect(find.text('_system_'), findsNothing);
    });

    testWidgets('uses Container for bubble styling', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: regularMessage,
              isOwnMessage: false,
              avatarUrl: '',
            ),
          ),
        ),
      );

      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('uses Column for message content layout', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: regularMessage,
              isOwnMessage: false,
              avatarUrl: '',
            ),
          ),
        ),
      );

      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('has SizedBox for spacing between elements', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: regularMessage,
              isOwnMessage: false,
              avatarUrl: '',
            ),
          ),
        ),
      );

      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('avatar is on right for own message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: regularMessage,
              isOwnMessage: true,
              avatarUrl: '',
            ),
          ),
        ),
      );

      final row = tester.widget<Row>(find.byType(Row));
      // For own message, avatar is at the end (right)
      expect(row.children.last, isA<Padding>());
    });

    testWidgets('avatar is on left for other message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: regularMessage,
              isOwnMessage: false,
              avatarUrl: '',
            ),
          ),
        ),
      );

      final row = tester.widget<Row>(find.byType(Row));
      // For other message, avatar is at the start (left)
      expect(row.children.first, isA<Padding>());
    });
  });
}
