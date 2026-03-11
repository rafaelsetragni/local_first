import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/widgets/chat_tile.dart';
import 'package:chat_app/models/chat_model.dart';

void main() {
  group('ChatTile', () {
    late ChatModel chatWithLastMessage;
    late ChatModel chatWithoutLastMessage;
    late ChatModel chatWithAvatar;
    late ChatModel chatWithSystemMessage;

    setUp(() {
      chatWithLastMessage = ChatModel(
        id: 'chat1',
        name: 'Test Chat',
        createdBy: 'creator',
        lastMessageAt: DateTime(2024, 1, 15, 14, 30).toUtc(),
        lastMessageText: 'Hello!',
        lastMessageSender: 'sender1',
      );

      chatWithoutLastMessage = ChatModel(
        id: 'chat2',
        name: 'New Chat',
        createdBy: 'testuser',
      );

      chatWithAvatar = ChatModel(
        id: 'chat3',
        name: 'Avatar Chat',
        createdBy: 'creator',
        // Note: avatarUrl not set to avoid network image loading errors in tests
      );

      chatWithSystemMessage = ChatModel(
        id: 'chat4',
        name: 'System Chat',
        createdBy: 'creator',
        lastMessageAt: DateTime(2024, 1, 15, 14, 30).toUtc(),
        lastMessageText: 'Chat closed by admin',
        lastMessageSender: '_system_',
      );
    });

    testWidgets('displays chat name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatTile(
              chat: chatWithoutLastMessage,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('New Chat'), findsOneWidget);
    });

    testWidgets('displays first letter of chat name when no avatar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatTile(
              chat: chatWithoutLastMessage,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('N'), findsOneWidget);
    });

    testWidgets('shows created by message when no last message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatTile(
              chat: chatWithoutLastMessage,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Created by testuser'), findsOneWidget);
    });

    testWidgets('shows last message with sender', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatTile(
              chat: chatWithLastMessage,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('sender1: Hello!'), findsOneWidget);
    });

    testWidgets('shows system message without sender prefix', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatTile(
              chat: chatWithSystemMessage,
              onTap: () {},
            ),
          ),
        ),
      );

      // System messages should not show "_system_:" prefix
      expect(find.text('Chat closed by admin'), findsOneWidget);
      expect(find.textContaining('_system_'), findsNothing);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatTile(
              chat: chatWithoutLastMessage,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ListTile));
      await tester.pump();

      expect(tapped, true);
    });

    testWidgets('uses ListTile widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatTile(
              chat: chatWithoutLastMessage,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byType(ListTile), findsOneWidget);
    });

    testWidgets('has CircleAvatar for leading widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatTile(
              chat: chatWithoutLastMessage,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byType(CircleAvatar), findsWidgets);
    });

    testWidgets('shows trailing with Column for timestamp and badge', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatTile(
              chat: chatWithLastMessage,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('displays ? for empty chat name', (tester) async {
      final emptyNameChat = ChatModel(
        id: 'chat5',
        name: '',
        createdBy: 'creator',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatTile(
              chat: emptyNameChat,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('uppercase first letter in avatar', (tester) async {
      final lowercaseChat = ChatModel(
        id: 'chat6',
        name: 'lowercase',
        createdBy: 'creator',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatTile(
              chat: lowercaseChat,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('L'), findsOneWidget);
    });

    testWidgets('displays chat from chatWithAvatar model', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatTile(
              chat: chatWithAvatar,
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Avatar Chat'), findsOneWidget);
      // CircleAvatar should be present with first letter fallback
      expect(find.byType(CircleAvatar), findsWidgets);
      expect(find.text('A'), findsOneWidget); // First letter of "Avatar Chat"
    });
  });
}
