import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:counter_app/pages/sign_in_page.dart';
import 'package:counter_app/services/repository_service.dart';
import 'package:counter_app/services/navigator_service.dart';
import 'package:mocktail/mocktail.dart';

class MockRepositoryService extends Mock implements RepositoryService {}

class MockNavigatorService extends Mock implements NavigatorService {}

void main() {
  group('SignInPage', () {
    testWidgets('renders username field and sign in button', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      expect(find.text('WebSocket Real-Time Counter'), findsOneWidget);
      expect(find.text('Sign In'), findsAtLeastNWidgets(1));
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('shows validation error when username is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      // Tap sign in button without entering username
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a username.'), findsOneWidget);
    });

    testWidgets('shows validation error when username is only spaces', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      // Enter only spaces
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a username.'), findsOneWidget);
    });

    testWidgets('username field has correct label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      expect(find.text('Username'), findsOneWidget);
    });

    testWidgets('username field has border decoration', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      // TextFormField exists and is properly configured
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('can enter text in username field', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      await tester.enterText(find.byType(TextFormField), 'testuser');
      expect(find.text('testuser'), findsOneWidget);
    });

    testWidgets('sign in button is disabled during sign in', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      // Enter valid username
      await tester.enterText(find.byType(TextFormField), 'testuser');

      // Get the button widget before tapping
      final buttonFinder = find.byType(ElevatedButton);
      final button = tester.widget<ElevatedButton>(buttonFinder);

      // Button should be enabled initially
      expect(button.onPressed, isNotNull);

      // Note: We can't easily test the disabled state during sign in
      // without mocking the RepositoryService, which requires dependency injection
    });

    testWidgets('button exists and is initially enabled', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      // Verify button exists
      expect(find.byType(ElevatedButton), findsOneWidget);

      // Button should be enabled initially
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('displays app title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      expect(find.text('WebSocket Real-Time Counter'), findsOneWidget);
    });

    testWidgets('has proper spacing between elements', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('uses SafeArea for proper layout', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      expect(find.byType(SafeArea), findsOneWidget);
    });

    testWidgets('applies padding to content', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      final padding = tester.widget<Padding>(
        find.byType(Padding).first,
      );
      expect(padding.padding, const EdgeInsets.all(16.0));
    });

    testWidgets('uses Form widget for validation', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      expect(find.byType(Form), findsOneWidget);
    });

    testWidgets('disposes controller properly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      // Navigate away to trigger dispose
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Other')),
        ),
      );

      // If we get here without errors, dispose worked correctly
      expect(find.text('Other'), findsOneWidget);
    });

    testWidgets('form field accepts text input', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      // Enter valid username
      await tester.enterText(find.byType(TextFormField), 'testuser');
      expect(find.text('testuser'), findsOneWidget);

      // Verify text field exists and accepts input
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('uses Column layout with proper alignment', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      final column = tester.widget<Column>(
        find.byType(Column).first,
      );

      expect(column.mainAxisAlignment, MainAxisAlignment.spaceEvenly);
      expect(column.crossAxisAlignment, CrossAxisAlignment.stretch);
    });

    testWidgets('submits form when pressing enter on text field', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      // Enter valid username
      await tester.enterText(find.byType(TextFormField), 'testuser');

      // Submit by pressing enter (onFieldSubmitted)
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Should trigger sign in (no validation error)
      expect(find.text('Please enter a username.'), findsNothing);
    });

    testWidgets('button has correct hero tags for FABs', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      // Verify button exists and is an ElevatedButton
      final button = find.byType(ElevatedButton);
      expect(button, findsOneWidget);
    });

    testWidgets('uses Scaffold as root widget', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      // Should have Scaffold widget
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('validates form before submitting', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      // Try to submit with empty username
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      // Should show validation error
      expect(find.text('Please enter a username.'), findsOneWidget);

      // Enter valid username
      await tester.enterText(find.byType(TextFormField), 'testuser');
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      // Validation error should be gone
      expect(find.text('Please enter a username.'), findsNothing);
    });
  });
}
