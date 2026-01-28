import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat_app/widgets/avatar_preview.dart';

void main() {
  group('AvatarPreview', () {
    testWidgets('displays default avatar when avatarUrl is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AvatarPreview(avatarUrl: ''),
          ),
        ),
      );

      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget);
    });

    testWidgets('displays edit indicator when showEditIndicator is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AvatarPreview(
              avatarUrl: '',
              showEditIndicator: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('does not display edit indicator when showEditIndicator is false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AvatarPreview(
              avatarUrl: '',
              showEditIndicator: false,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.edit), findsNothing);
    });

    testWidgets('displays green ring when connection status is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AvatarPreview(
              avatarUrl: '',
              connectionStatus: true,
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.byType(Container).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.border?.top.color, Colors.green);
    });

    testWidgets('displays red ring when connection status is false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AvatarPreview(
              avatarUrl: '',
              connectionStatus: false,
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.byType(Container).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.border?.top.color, Colors.red);
    });

    testWidgets('does not display ring when connection status is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AvatarPreview(
              avatarUrl: '',
              connectionStatus: null,
            ),
          ),
        ),
      );

      // When connectionStatus is null, no Container with border should exist
      final containers = tester.widgetList<Container>(find.byType(Container));
      final hasRingContainer = containers.any((container) {
        final decoration = container.decoration;
        return decoration is BoxDecoration &&
            decoration.shape == BoxShape.circle &&
            decoration.border != null;
      });
      expect(hasRingContainer, false);
    });

    testWidgets('respects custom radius', (tester) async {
      const customRadius = 100.0;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AvatarPreview(
              avatarUrl: '',
              radius: customRadius,
            ),
          ),
        ),
      );

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.radius, customRadius);
    });

    testWidgets('uses default radius when not specified', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AvatarPreview(
              avatarUrl: '',
            ),
          ),
        ),
      );

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.radius, 50.0);
    });

    testWidgets('adjusts avatar radius when connection status is provided', (tester) async {
      const baseRadius = 50.0;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AvatarPreview(
              avatarUrl: '',
              radius: baseRadius,
              connectionStatus: true,
            ),
          ),
        ),
      );

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      // Radius should be reduced by 4 when connection indicator is shown
      expect(avatar.radius, baseRadius - 4);
    });

    testWidgets('positions edit indicator at bottom right', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AvatarPreview(
              avatarUrl: '',
              showEditIndicator: true,
            ),
          ),
        ),
      );

      final positioned = tester.widget<Positioned>(
        find.byType(Positioned),
      );

      expect(positioned.bottom, 0);
      expect(positioned.right, 0);
    });

    testWidgets('sizes icon proportionally to radius', (tester) async {
      const customRadius = 100.0;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AvatarPreview(
              avatarUrl: '',
              radius: customRadius,
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.person));
      expect(icon.size, customRadius);
    });
  });
}
