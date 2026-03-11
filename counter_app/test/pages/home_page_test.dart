import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:counter_app/pages/home_page.dart';
import 'package:counter_app/models/user_model.dart';
import 'package:counter_app/models/counter_log_model.dart';
import 'package:counter_app/services/repository_service.dart';
import 'package:mocktail/mocktail.dart';

class MockRepositoryService extends Mock implements RepositoryService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MyHomePage', () {
    late MockRepositoryService mockService;
    late StreamController<int> counterController;
    late StreamController<List<UserModel>> usersController;
    late StreamController<List<CounterLogModel>> logsController;
    late StreamController<bool> connectionController;

    setUp(() {
      mockService = MockRepositoryService();
      counterController = StreamController<int>.broadcast();
      usersController = StreamController<List<UserModel>>.broadcast();
      logsController = StreamController<List<CounterLogModel>>.broadcast();
      connectionController = StreamController<bool>.broadcast();

      // Setup mock streams
      when(() => mockService.watchCounter()).thenAnswer((_) => counterController.stream);
      when(() => mockService.watchUsers()).thenAnswer((_) => usersController.stream);
      when(() => mockService.watchRecentLogs(limit: any(named: 'limit')))
          .thenAnswer((_) => logsController.stream);
      when(() => mockService.connectionState).thenAnswer((_) => connectionController.stream);
      when(() => mockService.isConnected).thenReturn(false);
      when(() => mockService.incrementCounter()).thenAnswer((_) async {});
      when(() => mockService.decrementCounter()).thenAnswer((_) async {});
      when(() => mockService.signOut()).thenAnswer((_) async {});
      when(() => mockService.updateAvatarUrl(any())).thenAnswer(
        (_) async => UserModel(username: 'testuser', avatarUrl: 'https://example.com'),
      );
    });

    tearDown(() {
      counterController.close();
      usersController.close();
      logsController.close();
      connectionController.close();
      // Reset singleton to avoid test interference
      RepositoryService.instance = null;
    });

    testWidgets('returns empty widget when no authenticated user', (tester) async {
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(null);

      // Mock the singleton to return our mock
      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );

      // Should show nothing
      expect(find.byType(Scaffold), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('renders scaffold when user is authenticated', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      // Should show scaffold
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('displays user greeting with username', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      // Emit data to streams
      usersController.add([user]);
      await tester.pump();

      // Should display greeting
      expect(find.text('Hello, testuser!'), findsOneWidget);
    });

    testWidgets('displays counter value from stream', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      // Emit counter value
      usersController.add([user]);
      counterController.add(42);
      await tester.pump();

      // Should display counter
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('shows loading indicator when counter stream is waiting', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user]);
      await tester.pump();

      // Counter stream hasn't emitted yet, should show loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('displays connection status badge', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);
      when(() => mockService.isConnected).thenReturn(true);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user]);
      connectionController.add(true);
      await tester.pump();

      // Should show connected status
      expect(find.text('Connected'), findsOneWidget);
    });

    testWidgets('displays disconnected status when not connected', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);
      when(() => mockService.isConnected).thenReturn(false);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user]);
      connectionController.add(false);
      await tester.pump();

      // Should show disconnected status
      expect(find.text('Disconnected'), findsOneWidget);
    });

    testWidgets('has increment and decrement floating action buttons', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user]);
      await tester.pump();

      // Should have two FABs
      expect(find.byType(FloatingActionButton), findsNWidgets(2));
      expect(find.widgetWithIcon(FloatingActionButton, Icons.add), findsOneWidget);
      expect(find.widgetWithIcon(FloatingActionButton, Icons.remove), findsOneWidget);
    });

    testWidgets('increment button calls incrementCounter', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user]);
      await tester.pump();

      // Tap increment button
      await tester.tap(find.widgetWithIcon(FloatingActionButton, Icons.add));
      await tester.pump();

      // Should call incrementCounter
      verify(() => mockService.incrementCounter()).called(1);
    });

    testWidgets('decrement button calls decrementCounter', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user]);
      await tester.pump();

      // Tap decrement button
      await tester.tap(find.widgetWithIcon(FloatingActionButton, Icons.remove));
      await tester.pump();

      // Should call decrementCounter
      verify(() => mockService.decrementCounter()).called(1);
    });

    testWidgets('logout button calls signOut', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user]);
      await tester.pump();

      // Tap logout button
      await tester.tap(find.byIcon(Icons.logout));
      await tester.pump();

      // Should call signOut
      verify(() => mockService.signOut()).called(1);
    });

    testWidgets('displays users list', (tester) async {
      final user1 = UserModel(username: 'user1', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final user2 = UserModel(username: 'user2', avatarUrl: null);
      when(() => mockService.authenticatedUser).thenReturn(user1);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user1, user2]);
      await tester.pump();

      // Should show both users
      expect(find.text('user1'), findsOneWidget);
      expect(find.text('user2'), findsOneWidget);
    });

    testWidgets('displays recent activities section', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user]);
      await tester.pump();

      // Should show recent activities section
      expect(find.text('Recent activities:'), findsOneWidget);
    });

    testWidgets('displays counter logs in animated list', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final log = CounterLogModel(
        username: 'testuser',
        increment: 5,
        sessionId: 'session1',
      );
      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user]);
      logsController.add([log]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should show log message
      expect(find.textContaining('Increased by 5'), findsOneWidget);
    });

    testWidgets('shows users section title', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user]);
      await tester.pump();

      // Should show users title
      expect(find.text('Users:'), findsOneWidget);
    });

    testWidgets('shows global counter title', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user]);
      await tester.pump();

      // Should show global counter title
      expect(find.text('Global counter updated by all users:'), findsOneWidget);
    });

    testWidgets('disposes stream subscription on dispose', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
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

    testWidgets('floating action buttons have correct hero tags', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user]);
      await tester.pump();

      // Find FABs
      final fabs = tester.widgetList<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );

      // Check hero tags
      expect(fabs.first.heroTag, 'increment_button');
      expect(fabs.last.heroTag, 'decrement_button');
    });

    testWidgets('floating action buttons have correct tooltips', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user]);
      await tester.pump();

      // Find FABs
      final fabs = tester.widgetList<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );

      // Check tooltips
      expect(fabs.first.tooltip, 'Increment');
      expect(fabs.last.tooltip, 'Decrement');
    });

    testWidgets('app bar shows logout icon', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user]);
      await tester.pump();

      // Should show logout icon
      expect(find.byIcon(Icons.logout), findsOneWidget);
    });

    testWidgets('uses Column layout for main content', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user]);
      await tester.pump();

      // Should have Column widgets
      expect(find.byType(Column), findsWidgets);
    });

    testWidgets('handles multiple log updates', (tester) async {
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final log1 = CounterLogModel(
        id: 'log1',
        username: 'testuser',
        increment: 5,
        sessionId: 'session1',
      );
      final log2 = CounterLogModel(
        id: 'log2',
        username: 'testuser',
        increment: -3,
        sessionId: 'session1',
      );
      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user]);

      // Add first log
      logsController.add([log1]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Increased by 5'), findsOneWidget);

      // Add second log
      logsController.add([log1, log2]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Decreased by 3'), findsOneWidget);
    });

    testWidgets('displays avatar preview with edit indicator', (tester) async {
      // Use null avatar to avoid network image loading issues in tests
      final user = UserModel(username: 'testuser', avatarUrl: null);
      // Set larger viewport to avoid overflow errors
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      when(() => mockService.authenticatedUser).thenReturn(user);

      RepositoryService.instance = mockService;

      await tester.pumpWidget(
        const MaterialApp(
          home: MyHomePage(),
        ),
      );
      await tester.pump();

      usersController.add([user]);
      connectionController.add(true);
      await tester.pump();

      // Should show avatar preview (with default icon when no avatar URL)
      expect(find.byType(GestureDetector), findsWidgets);
    });
  });
}
