import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_first_hive_counter_example/main.dart';

void main() {
  testWidgets('Sign-in page renders expected inputs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(home: SignInPage()));

    expect(find.text('Offline Counter'), findsOneWidget);
    expect(find.text('Sign In'), findsWidgets); // title + button
    expect(find.widgetWithText(TextFormField, 'Username'), findsOneWidget);
  });

  testWidgets('Shows validation error when submitting empty username', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(home: SignInPage()));

    await tester.tap(find.text('Sign In').last);
    await tester.pumpAndSettle();

    expect(find.text('Please enter a username.'), findsOneWidget);
  });
}
