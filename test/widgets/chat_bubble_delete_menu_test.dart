import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_menu.dart';

Widget _app(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

GestureDetector _detector(WidgetTester tester) => tester.widget<GestureDetector>(
      find.descendant(
        of: find.byType(ChatBubbleMenu),
        matching: find.byType(GestureDetector),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('long-press reveals a Delete exchange item that fires', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_app(
      ChatBubbleMenu(
        menuChildren: [
          MenuItemButton(
            onPressed: () => tapped = true,
            child: const Text('Delete exchange'),
          ),
        ],
        child: const SizedBox(width: 200, height: 60, child: Text('bubble')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Delete exchange'), findsNothing);

    _detector(tester).onLongPressStart!(
      const LongPressStartDetails(localPosition: Offset(20, 20)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete exchange'), findsOneWidget);

    await tester.tap(find.text('Delete exchange'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('a disabled (streaming) Delete item does not fire', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_app(
      ChatBubbleMenu(
        menuChildren: [
          MenuItemButton(
            onPressed: null, // streaming -> disabled
            child: const Text('Delete exchange'),
          ),
        ],
        child: const SizedBox(width: 200, height: 60, child: Text('bubble')),
      ),
    ));
    await tester.pumpAndSettle();

    _detector(tester).onLongPressStart!(
      const LongPressStartDetails(localPosition: Offset(20, 20)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete exchange'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tapped, isFalse);
  });
}
