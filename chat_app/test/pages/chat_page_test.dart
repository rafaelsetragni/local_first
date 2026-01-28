import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:chat_app/pages/chat_page.dart';
import 'package:chat_app/models/chat_model.dart';
import 'package:chat_app/models/message_model.dart';
import 'package:chat_app/models/user_model.dart';
import 'package:chat_app/services/repository_service.dart';

class MockRepositoryService extends Mock implements RepositoryService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatPage', () {
    late MockRepositoryService mockService;
    late ChatModel testChat;
    late ChatModel closedChat;
    late StreamController<ChatModel?> chatController;
    late StreamController<List<MessageModel>> messagesController;
    late StreamController<List<UserModel>> usersController;
    late StreamController<bool> connectionController;
    late StreamController<int> unreadController;

    setUp(() {
      mockService = MockRepositoryService();
      chatController = StreamController<ChatModel?>.broadcast();
      messagesController = StreamController<List<MessageModel>>.broadcast();
      usersController = StreamController<List<UserModel>>.broadcast();
      connectionController = StreamController<bool>.broadcast();
      unreadController = StreamController<int>.broadcast();

      testChat = ChatModel(
        id: 'chat1',
        name: 'Test Chat',
        createdBy: 'user1',
      );

      closedChat = ChatModel(
        id: 'chat2',
        name: 'Closed Chat',
        createdBy: 'user1',
        closedBy: 'admin',
      );

      // Setup mock streams and methods
      when(() => mockService.watchChat(any())).thenAnswer((_) => chatController.stream);
      when(() => mockService.getMessages(any(), limit: any(named: 'limit'), offset: any(named: 'offset')))
          .thenAnswer((_) async => []);
      when(() => mockService.watchNewMessages(any(), any())).thenAnswer((_) => messagesController.stream);
      when(() => mockService.watchUsers()).thenAnswer((_) => usersController.stream);
      when(() => mockService.connectionState).thenAnswer((_) => connectionController.stream);
      when(() => mockService.isConnected).thenReturn(false);
      when(() => mockService.watchTotalUnreadCount()).thenAnswer((_) => unreadController.stream);
      when(() => mockService.setCurrentOpenChat(any())).thenReturn(null);
      when(() => mockService.markChatAsRead(any())).thenAnswer((_) async {});
      when(() => mockService.sendMessage(chatId: any(named: 'chatId'), text: any(named: 'text')))
          .thenAnswer((_) async => MessageModel(chatId: 'chat1', senderId: 'testuser', text: 'Hello'));
      when(() => mockService.updateChatAvatar(any(), any())).thenAnswer(
        (_) async => ChatModel(id: 'chat1', name: 'Test Chat', createdBy: 'user1'),
      );
    });

    tearDown(() {
      chatController.close();
      messagesController.close();
      usersController.close();
      connectionController.close();
      unreadController.close();
      RepositoryService.instance = null;
    });

    testWidgets('renders basic structure', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('displays chat name in app bar', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pump();

      expect(find.text('Test Chat'), findsOneWidget);
    });

    testWidgets('has back button', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pump();

      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('shows loading indicator initially', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      // Make getMessages never complete to keep loading
      when(() => mockService.getMessages(any(), limit: any(named: 'limit'), offset: any(named: 'offset')))
          .thenAnswer((_) => Completer<List<MessageModel>>().future);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state when no messages after loading', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No messages yet'), findsOneWidget);
      expect(find.text('Be the first to send a message'), findsOneWidget);
      expect(find.byIcon(Icons.message_outlined), findsOneWidget);
    });

    testWidgets('has message input field for open chat', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Type a message...'), findsOneWidget);
    });

    testWidgets('has send button for open chat', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('can enter message text', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Hello World!');
      await tester.pump();

      expect(find.text('Hello World!'), findsOneWidget);
    });

    testWidgets('shows closed chat indicator for closed chat', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: closedChat),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('This chat has been closed'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('no message input for closed chat', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: closedChat),
        ),
      );
      await tester.pumpAndSettle();

      // No text field for message input
      expect(find.widgetWithText(TextField, 'Type a message...'), findsNothing);
      // No send button
      expect(find.byIcon(Icons.send), findsNothing);
    });

    testWidgets('shows first letter of chat name when no avatar', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pump();

      // Should show 'T' for 'Test Chat'
      expect(find.text('T'), findsOneWidget);
    });

    testWidgets('send button clears text after tap', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pumpAndSettle();

      // Enter message
      await tester.enterText(find.byType(TextField), 'Hello World!');
      await tester.pump();

      expect(find.text('Hello World!'), findsOneWidget);

      // Tap send button
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // Text should be cleared
      expect(find.text('Hello World!'), findsNothing);
    });

    testWidgets('send button calls sendMessage', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pumpAndSettle();

      // Enter message
      await tester.enterText(find.byType(TextField), 'Hello World!');
      await tester.pump();

      // Tap send button
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      verify(() => mockService.sendMessage(chatId: 'chat1', text: 'Hello World!')).called(1);
    });

    testWidgets('send button does nothing with empty text', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pumpAndSettle();

      // Don't enter any text, just tap send
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // sendMessage should not be called
      verifyNever(() => mockService.sendMessage(chatId: any(named: 'chatId'), text: any(named: 'text')));
    });

    testWidgets('submitting text field sends message', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pumpAndSettle();

      // Enter message
      await tester.enterText(find.byType(TextField), 'Hello World!');

      // Submit via keyboard
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();

      verify(() => mockService.sendMessage(chatId: 'chat1', text: 'Hello World!')).called(1);
    });

    testWidgets('shows ? when chat name is empty', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final emptyNameChat = ChatModel(
        id: 'chat4',
        name: '',
        createdBy: 'user1',
      );

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: emptyNameChat),
        ),
      );
      await tester.pump();

      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('closed chat name in app bar', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: closedChat),
        ),
      );
      await tester.pump();

      expect(find.text('Closed Chat'), findsOneWidget);
    });

    testWidgets('tapping chat avatar opens dialog', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pumpAndSettle();

      // Find the GestureDetector with the avatar (the one with 'T' letter)
      final avatarFinder = find.widgetWithText(CircleAvatar, 'T');
      await tester.tap(avatarFinder);
      await tester.pumpAndSettle();

      expect(find.text('Update chat avatar URL'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('cancel closes avatar dialog', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pumpAndSettle();

      final avatarFinder = find.widgetWithText(CircleAvatar, 'T');
      await tester.tap(avatarFinder);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Update chat avatar URL'), findsNothing);
    });

    testWidgets('displays messages when available', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      final message = MessageModel(
        id: 'msg1',
        chatId: 'chat1',
        senderId: 'testuser',
        text: 'Hello there!',
      );
      when(() => mockService.authenticatedUser).thenReturn(user);
      when(() => mockService.getMessages(any(), limit: any(named: 'limit'), offset: any(named: 'offset')))
          .thenAnswer((_) async => [message]);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hello there!'), findsOneWidget);
    });

    testWidgets('sets current open chat on init', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pump();

      verify(() => mockService.setCurrentOpenChat('chat1')).called(1);
    });

    testWidgets('marks chat as read on init', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pump();

      verify(() => mockService.markChatAsRead('chat1')).called(1);
    });

    testWidgets('disposes subscriptions on dispose', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        MaterialApp(
          home: ChatPage(chat: testChat),
        ),
      );
      await tester.pump();

      // Navigate away to trigger dispose
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Other')),
        ),
      );

      // setCurrentOpenChat should be called with null on dispose
      verify(() => mockService.setCurrentOpenChat(null)).called(1);
      expect(find.text('Other'), findsOneWidget);
    });

    group('Pagination', () {
      const pageSize = 25;

      List<MessageModel> generateMessages(int count, {int startIndex = 0}) {
        return List.generate(count, (i) {
          final idx = startIndex + i;
          return MessageModel(
            id: 'msg_$idx',
            chatId: 'chat1',
            senderId: 'user1',
            text: 'Message $idx',
            createdAt:
                DateTime.utc(2024, 1, 1).subtract(Duration(minutes: idx)),
            updatedAt:
                DateTime.utc(2024, 1, 1).subtract(Duration(minutes: idx)),
          );
        });
      }

      /// Scrolls the reversed ListView past the 80% threshold
      /// to trigger pagination by directly jumping the scroll position.
      Future<void> scrollToTriggerPagination(WidgetTester tester) async {
        final scrollable = find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        );
        final state = tester.state<ScrollableState>(scrollable);
        state.position.jumpTo(state.position.maxScrollExtent * 0.9);
        await tester.pumpAndSettle();
      }

      testWidgets('zero results on initial load disables pagination',
          (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        int callCount = 0;
        when(() => mockService.authenticatedUser)
            .thenReturn(UserModel(username: 'testuser', avatarUrl: null));
        when(() => mockService.getMessages(any(),
                limit: any(named: 'limit'),
                offset: any(named: 'offset')))
            .thenAnswer((_) async {
          callCount++;
          return [];
        });
        RepositoryService.instance = mockService;

        await tester
            .pumpWidget(MaterialApp(home: ChatPage(chat: testChat)));
        await tester.pumpAndSettle();

        expect(find.text('No messages yet'), findsOneWidget);
        expect(callCount, 1);
      });

      testWidgets('one result on initial load disables pagination',
          (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        int callCount = 0;
        when(() => mockService.authenticatedUser)
            .thenReturn(UserModel(username: 'testuser', avatarUrl: null));
        when(() => mockService.getMessages(any(),
                limit: any(named: 'limit'),
                offset: any(named: 'offset')))
            .thenAnswer((_) async {
          callCount++;
          return generateMessages(1);
        });
        RepositoryService.instance = mockService;

        await tester
            .pumpWidget(MaterialApp(home: ChatPage(chat: testChat)));
        await tester.pumpAndSettle();

        expect(find.text('Message 0'), findsOneWidget);
        expect(callCount, 1);
      });

      testWidgets(
          'exactly page size results on initial load enables pagination',
          (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        int callCount = 0;
        when(() => mockService.authenticatedUser)
            .thenReturn(UserModel(username: 'testuser', avatarUrl: null));
        when(() => mockService.getMessages(any(),
                limit: any(named: 'limit'),
                offset: any(named: 'offset')))
            .thenAnswer((_) async {
          callCount++;
          if (callCount == 1) return generateMessages(pageSize);
          return generateMessages(5, startIndex: pageSize);
        });
        RepositoryService.instance = mockService;

        await tester
            .pumpWidget(MaterialApp(home: ChatPage(chat: testChat)));
        await tester.pumpAndSettle();

        expect(callCount, 1);

        // Scroll toward older messages to trigger pagination
        await scrollToTriggerPagination(tester);

        expect(callCount, 2);
      });

      testWidgets(
          'pagination uses correct offset matching loaded message count',
          (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final capturedOffsets = <int?>[];
        when(() => mockService.authenticatedUser)
            .thenReturn(UserModel(username: 'testuser', avatarUrl: null));
        when(() => mockService.getMessages(any(),
                limit: any(named: 'limit'),
                offset: any(named: 'offset')))
            .thenAnswer((invocation) async {
          final offset = invocation.namedArguments[#offset] as int?;
          capturedOffsets.add(offset);
          if (capturedOffsets.length == 1) {
            return generateMessages(pageSize);
          }
          return generateMessages(10, startIndex: pageSize);
        });
        RepositoryService.instance = mockService;

        await tester
            .pumpWidget(MaterialApp(home: ChatPage(chat: testChat)));
        await tester.pumpAndSettle();

        await scrollToTriggerPagination(tester);

        expect(capturedOffsets.length, 2);
        expect(capturedOffsets[0], 0); // initial load uses default offset
        expect(capturedOffsets[1], pageSize); // offset = loaded count
      });

      testWidgets(
          'pagination stops after receiving fewer results than page size',
          (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        int callCount = 0;
        when(() => mockService.authenticatedUser)
            .thenReturn(UserModel(username: 'testuser', avatarUrl: null));
        when(() => mockService.getMessages(any(),
                limit: any(named: 'limit'),
                offset: any(named: 'offset')))
            .thenAnswer((_) async {
          callCount++;
          if (callCount == 1) return generateMessages(pageSize);
          return generateMessages(10, startIndex: pageSize);
        });
        RepositoryService.instance = mockService;

        await tester
            .pumpWidget(MaterialApp(home: ChatPage(chat: testChat)));
        await tester.pumpAndSettle();

        // First scroll triggers second page load
        await scrollToTriggerPagination(tester);
        expect(callCount, 2);

        // Second scroll should NOT trigger a third load
        await scrollToTriggerPagination(tester);
        expect(callCount, 2);
      });

      testWidgets('no records are skipped or lost between pages',
          (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        int callCount = 0;
        when(() => mockService.authenticatedUser)
            .thenReturn(UserModel(username: 'testuser', avatarUrl: null));
        when(() => mockService.getMessages(any(),
                limit: any(named: 'limit'),
                offset: any(named: 'offset')))
            .thenAnswer((_) async {
          callCount++;
          if (callCount == 1) return generateMessages(pageSize);
          return generateMessages(10, startIndex: pageSize);
        });
        RepositoryService.instance = mockService;

        await tester
            .pumpWidget(MaterialApp(home: ChatPage(chat: testChat)));
        await tester.pumpAndSettle();

        await scrollToTriggerPagination(tester);

        // Total messages should be 25 + 10 = 35
        final listView =
            tester.widget<ListView>(find.byType(ListView));
        final delegate = listView.childrenDelegate
            as SliverChildBuilderDelegate;
        expect(delegate.estimatedChildCount, 35);
      });

      testWidgets(
          'duplicate messages from pagination are filtered out',
          (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        int callCount = 0;
        when(() => mockService.authenticatedUser)
            .thenReturn(UserModel(username: 'testuser', avatarUrl: null));
        when(() => mockService.getMessages(any(),
                limit: any(named: 'limit'),
                offset: any(named: 'offset')))
            .thenAnswer((_) async {
          callCount++;
          if (callCount == 1) return generateMessages(pageSize);
          // 5 overlapping (indices 20-24) + 5 new (indices 25-29)
          return [
            ...generateMessages(5, startIndex: 20),
            ...generateMessages(5, startIndex: pageSize),
          ];
        });
        RepositoryService.instance = mockService;

        await tester
            .pumpWidget(MaterialApp(home: ChatPage(chat: testChat)));
        await tester.pumpAndSettle();

        await scrollToTriggerPagination(tester);

        // Should have 30 unique messages (25 + 5 new), not 35
        final listView =
            tester.widget<ListView>(find.byType(ListView));
        final delegate = listView.childrenDelegate
            as SliverChildBuilderDelegate;
        expect(delegate.estimatedChildCount, 30);
      });

      testWidgets('new messages from stream are deduplicated',
          (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final initialMessages = generateMessages(5);
        when(() => mockService.authenticatedUser)
            .thenReturn(UserModel(username: 'testuser', avatarUrl: null));
        when(() => mockService.getMessages(any(),
                limit: any(named: 'limit'),
                offset: any(named: 'offset')))
            .thenAnswer((_) async => initialMessages);
        RepositoryService.instance = mockService;

        await tester
            .pumpWidget(MaterialApp(home: ChatPage(chat: testChat)));
        await tester.pumpAndSettle();

        // 5 messages loaded
        var listView =
            tester.widget<ListView>(find.byType(ListView));
        var delegate = listView.childrenDelegate
            as SliverChildBuilderDelegate;
        expect(delegate.estimatedChildCount, 5);

        // Send duplicate via stream
        messagesController.add([initialMessages.first]);
        await tester.pump();

        listView = tester.widget<ListView>(find.byType(ListView));
        delegate = listView.childrenDelegate
            as SliverChildBuilderDelegate;
        expect(delegate.estimatedChildCount, 5); // still 5

        // Send new message via stream
        final newMsg = MessageModel(
          id: 'brand_new',
          chatId: 'chat1',
          senderId: 'user1',
          text: 'Brand new!',
          createdAt: DateTime.utc(2024, 1, 2),
        );
        messagesController.add([newMsg]);
        await tester.pump();

        listView = tester.widget<ListView>(find.byType(ListView));
        delegate = listView.childrenDelegate
            as SliverChildBuilderDelegate;
        expect(delegate.estimatedChildCount, 6); // now 6
      });

      testWidgets(
          'page does not enter pagination loop after reaching end',
          (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        int callCount = 0;
        when(() => mockService.authenticatedUser)
            .thenReturn(UserModel(username: 'testuser', avatarUrl: null));
        when(() => mockService.getMessages(any(),
                limit: any(named: 'limit'),
                offset: any(named: 'offset')))
            .thenAnswer((_) async {
          callCount++;
          if (callCount == 1) return generateMessages(pageSize);
          return []; // empty second page
        });
        RepositoryService.instance = mockService;

        await tester
            .pumpWidget(MaterialApp(home: ChatPage(chat: testChat)));
        await tester.pumpAndSettle();

        // Scroll to trigger first pagination
        await scrollToTriggerPagination(tester);
        expect(callCount, 2);

        // Scroll again - should NOT trigger another load
        await scrollToTriggerPagination(tester);
        expect(callCount, 2);

        // Scroll once more - still no new load
        await scrollToTriggerPagination(tester);
        expect(callCount, 2);
      });

      testWidgets('shows loading indicator during pagination load',
          (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final completer = Completer<List<MessageModel>>();
        int callCount = 0;
        when(() => mockService.authenticatedUser)
            .thenReturn(UserModel(username: 'testuser', avatarUrl: null));
        when(() => mockService.getMessages(any(),
                limit: any(named: 'limit'),
                offset: any(named: 'offset')))
            .thenAnswer((_) async {
          callCount++;
          if (callCount == 1) return generateMessages(pageSize);
          return completer.future;
        });
        RepositoryService.instance = mockService;

        await tester
            .pumpWidget(MaterialApp(home: ChatPage(chat: testChat)));
        await tester.pumpAndSettle();

        // Scroll to trigger pagination
        final scrollable = find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        );
        final scrollState =
            tester.state<ScrollableState>(scrollable);
        scrollState.position
            .jumpTo(scrollState.position.maxScrollExtent * 0.9);
        await tester.pump();

        // itemCount should include loading indicator (+1)
        final listView =
            tester.widget<ListView>(find.byType(ListView));
        final delegate = listView.childrenDelegate
            as SliverChildBuilderDelegate;
        expect(delegate.estimatedChildCount, pageSize + 1);

        // Complete the load
        completer.complete(generateMessages(5, startIndex: pageSize));
        await tester.pumpAndSettle();

        // Loading indicator gone, total 30 messages
        final listView2 =
            tester.widget<ListView>(find.byType(ListView));
        final delegate2 = listView2.childrenDelegate
            as SliverChildBuilderDelegate;
        expect(delegate2.estimatedChildCount, 30);
      });

      testWidgets(
          'pagination remains disabled after reaching end even with new stream messages',
          (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        int callCount = 0;
        when(() => mockService.authenticatedUser)
            .thenReturn(UserModel(username: 'testuser', avatarUrl: null));
        when(() => mockService.getMessages(any(),
                limit: any(named: 'limit'),
                offset: any(named: 'offset')))
            .thenAnswer((_) async {
          callCount++;
          return generateMessages(10);
        });
        RepositoryService.instance = mockService;

        await tester
            .pumpWidget(MaterialApp(home: ChatPage(chat: testChat)));
        await tester.pumpAndSettle();

        // Initial load returned 10 < 25, so _hasMore = false
        expect(callCount, 1);

        // New messages arrive via stream
        messagesController.add(generateMessages(3, startIndex: 100));
        await tester.pump();

        // Even with new messages, _hasMore should remain false
        // No additional getMessages calls should be made
        expect(callCount, 1);
      });
    });
  });
}
