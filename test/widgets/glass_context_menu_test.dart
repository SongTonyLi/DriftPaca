import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Widgets/glass_context_menu.dart';

Widget _harness(void Function(BuildContext) onOpen) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => onOpen(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the header + actions, fires onTap, then dismisses',
      (tester) async {
    var fired = false;
    await tester.pumpWidget(_harness((context) {
      showGlassContextMenu(
        context: context,
        position: const Offset(100, 300),
        header: 'My Chat',
        actions: [
          GlassMenuAction(
            icon: Icons.delete_outline,
            label: 'Delete exchange',
            isDestructive: true,
            onTap: () => fired = true,
          ),
        ],
      );
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('My Chat'), findsOneWidget);
    expect(find.text('Delete exchange'), findsOneWidget);

    await tester.tap(find.text('Delete exchange'));
    await tester.pumpAndSettle();

    expect(fired, isTrue);
    expect(find.text('Delete exchange'), findsNothing); // menu dismissed
  });

  testWidgets('tapping the barrier dismisses without firing any action',
      (tester) async {
    var fired = false;
    await tester.pumpWidget(_harness((context) {
      showGlassContextMenu(
        context: context,
        position: const Offset(100, 300),
        actions: [
          GlassMenuAction(
            icon: Icons.delete_outline,
            label: 'Delete exchange',
            onTap: () => fired = true,
          ),
        ],
      );
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete exchange'), findsOneWidget);

    // Tap the modal barrier in the corner, away from the menu.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(fired, isFalse);
    expect(find.text('Delete exchange'), findsNothing);
  });
}
