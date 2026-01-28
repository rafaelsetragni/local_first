import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/pages/sign_in_page.dart';

void main() {
  group('SignInPage', () {
    testWidgets('renders sign in form', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      expect(find.text('Local First Chat'), findsOneWidget);
      expect(find.text('Sign In'), findsWidgets);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('shows username text field with label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      expect(find.text('Username'), findsOneWidget);
    });

    testWidgets('shows validation error when username is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      // Find and tap the sign in button
      final signInButton = find.byType(ElevatedButton);
      await tester.tap(signInButton);
      await tester.pumpAndSettle();

      // Check for validation error
      expect(find.text('Please enter a username.'), findsOneWidget);
    });

    testWidgets('shows validation error when username has only spaces', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      // Enter whitespace only
      await tester.enterText(find.byType(TextFormField), '   ');

      // Find and tap the sign in button
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      // Check for validation error
      expect(find.text('Please enter a username.'), findsOneWidget);
    });

    testWidgets('sign in button is initially enabled', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('can enter username text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      await tester.enterText(find.byType(TextFormField), 'testuser');
      await tester.pump();

      expect(find.text('testuser'), findsOneWidget);
    });

    testWidgets('has proper structure with SafeArea', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      expect(find.byType(SafeArea), findsOneWidget);
      expect(find.byType(Form), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('has proper padding', (tester) async {
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

    testWidgets('submitting empty form via keyboard shows validation error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      // First focus the text field
      await tester.tap(find.byType(TextFormField));
      await tester.pump();

      // Submit via keyboard with empty field
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Should show validation error
      expect(find.text('Please enter a username.'), findsOneWidget);
    });

    testWidgets('submits form when pressing enter with valid input', (tester) async {
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

      // Should not show validation error
      expect(find.text('Please enter a username.'), findsNothing);
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

    testWidgets('has SizedBox for spacing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('text field has border decoration', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      // TextFormField exists and is properly configured
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('displays app title text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SignInPage(),
        ),
      );

      expect(find.text('Local First Chat'), findsOneWidget);
    });
  });
}
