import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:chat_app/pages/home_page.dart';
import 'package:chat_app/models/chat_model.dart';
import 'package:chat_app/models/user_model.dart';
import 'package:chat_app/services/repository_service.dart';

class MockRepositoryService extends Mock implements RepositoryService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomePage', () {
    late MockRepositoryService mockService;
    late StreamController<List<ChatModel>> chatsController;
    late StreamController<bool> connectionController;
    late StreamController<Map<String, int>> unreadCountsController;

    setUp(() {
      mockService = MockRepositoryService();
      chatsController = StreamController<List<ChatModel>>.broadcast();
      connectionController = StreamController<bool>.broadcast();
      unreadCountsController = StreamController<Map<String, int>>.broadcast();

      // Setup mock streams and methods
      when(() => mockService.getChats()).thenAnswer((_) async => []);
      when(() => mockService.watchChats()).thenAnswer((_) => chatsController.stream);
      when(() => mockService.connectionState).thenAnswer((_) => connectionController.stream);
      when(() => mockService.isConnected).thenReturn(false);
      when(() => mockService.getUnreadCountsMap()).thenAnswer((_) async => {});
      when(() => mockService.watchUnreadCounts()).thenAnswer((_) => unreadCountsController.stream);
      when(() => mockService.signOut()).thenAnswer((_) async {});
      when(() => mockService.updateAvatarUrl(any())).thenAnswer(
        (_) async => UserModel(username: 'testuser', avatarUrl: 'https://example.com'),
      );
      when(() => mockService.createChat(chatName: any(named: 'chatName'))).thenAnswer(
        (_) async => ChatModel(name: 'Test', createdBy: 'testuser'),
      );
    });

    tearDown(() {
      chatsController.close();
      connectionController.close();
      unreadCountsController.close();
      RepositoryService.instance = null;
    });

    testWidgets('renders scaffold when user is null', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(null);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('renders basic structure with authenticated user', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pump();

      expect(find.byType(Scaffold), findsWidgets);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('displays Local First Chat in app bar', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pump();

      expect(find.text('Local First Chat'), findsWidgets);
    });

    testWidgets('displays user greeting with username', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pump();

      expect(find.text('Welcome, testuser'), findsOneWidget);
    });

    testWidgets('has logout button in app bar', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.logout), findsOneWidget);
    });

    testWidgets('has floating action button', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pump();

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows loading indicator initially', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      // Make getChats never complete to keep loading
      when(() => mockService.getChats()).thenAnswer((_) => Completer<List<ChatModel>>().future);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows empty state when no chats after loading', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No chats yet'), findsOneWidget);
      expect(find.text('Tap the + button to create a chat'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    });

    testWidgets('displays chats when available', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      final chat = ChatModel(id: 'chat1', name: 'Test Chat', createdBy: 'testuser');
      when(() => mockService.authenticatedUser).thenReturn(user);
      when(() => mockService.getChats()).thenAnswer((_) async => [chat]);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pumpAndSettle();

      chatsController.add([chat]);
      await tester.pump();

      expect(find.text('Test Chat'), findsOneWidget);
    });

    testWidgets('FAB opens create chat dialog', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Create Chat'), findsOneWidget);
      expect(find.text('Chat name'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
    });

    testWidgets('create chat dialog has text field', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('cancel button closes create chat dialog', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Create Chat'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Create Chat'), findsNothing);
    });

    testWidgets('create button does nothing with empty chat name', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Tap create with empty name
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      // Dialog should still be open
      expect(find.text('Create Chat'), findsOneWidget);
    });

    testWidgets('logout button shows confirmation dialog', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();

      expect(find.text('Sign Out'), findsOneWidget);
      expect(find.text('Are you sure you want to sign out?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Confirm'), findsOneWidget);
    });

    testWidgets('cancel button closes logout dialog', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Sign Out'), findsNothing);
    });

    testWidgets('confirm logout calls signOut', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      verify(() => mockService.signOut()).called(1);
    });

    testWidgets('connection status shows cloud_off when disconnected', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      when(() => mockService.isConnected).thenReturn(false);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pump();

      connectionController.add(false);
      await tester.pump();

      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });

    testWidgets('connection status shows cloud_done when connected', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      when(() => mockService.isConnected).thenReturn(true);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pump();

      connectionController.add(true);
      await tester.pump();

      expect(find.byIcon(Icons.cloud_done), findsOneWidget);
    });

    testWidgets('can enter chat name in create dialog', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'My New Chat');
      await tester.pump();

      expect(find.text('My New Chat'), findsOneWidget);
    });

    testWidgets('create chat calls createChat method', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'My New Chat');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      verify(() => mockService.createChat(chatName: 'My New Chat')).called(1);
    });

    testWidgets('submitting text field in create dialog works', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'My New Chat');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Dialog should close after submitting
      expect(find.text('Create Chat'), findsNothing);
    });

    testWidgets('disposes stream subscription on dispose', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pump();

      // Navigate away to trigger dispose
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Other')),
        ),
      );

      // If we get here without errors, dispose worked correctly
      expect(find.text('Other'), findsOneWidget);
    });

    testWidgets('chat list has bottom padding to prevent FAB overlap',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user = UserModel(username: 'testuser', avatarUrl: null);
      final chat =
          ChatModel(id: 'chat1', name: 'Test Chat', createdBy: 'testuser');
      when(() => mockService.authenticatedUser).thenReturn(user);
      when(() => mockService.getChats()).thenAnswer((_) async => [chat]);
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: HomePage(),
        ),
      );
      await tester.pumpAndSettle();

      chatsController.add([chat]);
      await tester.pump();

      // Verify ListView has bottom padding to prevent FAB overlap
      // Standard FAB is 56dp tall + 16dp margin = 72dp minimum
      final listView = tester.widget<ListView>(find.byType(ListView));
      final padding = listView.padding as EdgeInsets?;
      expect(padding, isNotNull,
          reason: 'ListView should have padding to prevent FAB overlap');
      expect(padding!.bottom, greaterThanOrEqualTo(72.0),
          reason:
              'Bottom padding should be at least 72dp (FAB height 56dp + margin 16dp)');
    });
  });
}
