import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_menu.dart';

Widget buildTestApp(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: child),
    ),
  );
}

GestureDetector menuGestureDetector(WidgetTester tester) {
  return tester.widget<GestureDetector>(
    find.descendant(
      of: find.byType(ChatBubbleMenu),
      matching: find.byType(GestureDetector),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bug 1: held double-tap does not re-open the menu at a jumped position',
      () {
    testWidgets('onLongPressStart is a no-op while the menu is already open',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ChatBubbleMenu(
            menuChildren: [Text('menu item', key: Key('menu-item'))],
            child: SizedBox(width: 200, height: 60, child: Text('bubble')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final detector = menuGestureDetector(tester);

      // Open the menu at position A. (Long-press is the primary open gesture;
      // double-tap-to-open on a closed bubble was removed because its
      // DoubleTapGestureRecognizer starved citation-link taps — see
      // test/citation_tap_routing_test.dart.)
      detector.onLongPressStart!(
        const LongPressStartDetails(localPosition: Offset(10, 10)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('menu-item')), findsOneWidget);
      final positionAfterOpen =
          tester.getTopLeft(find.byKey(const Key('menu-item')));

      // The user keeps the pointer held after the second tap, so the long-press
      // deadline is crossed and onLongPressStart fires at a different position.
      menuGestureDetector(tester).onLongPressStart!(
        const LongPressStartDetails(localPosition: Offset(120, 40)),
      );
      await tester.pumpAndSettle();

      // The menu must not have snapped to the long-press position.
      expect(find.byKey(const Key('menu-item')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('menu-item'))),
        positionAfterOpen,
      );
    });

    testWidgets('onLongPressStart still opens the menu when it is closed',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          const ChatBubbleMenu(
            menuChildren: [Text('menu item', key: Key('menu-item'))],
            child: SizedBox(width: 200, height: 60, child: Text('bubble')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('menu-item')), findsNothing);

      menuGestureDetector(tester).onLongPressStart!(
        const LongPressStartDetails(localPosition: Offset(30, 20)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('menu-item')), findsOneWidget);
    });
  });
}
