import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_text_field.dart';

Widget _host(TextEditingController controller, FocusNode focusNode) {
  return MaterialApp(
    home: Scaffold(
      body: ChatTextField(
        controller: controller,
        focusNode: focusNode,
      ),
    ),
  );
}

Future<void> _pressShiftEnter(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

void main() {
  group('ChatTextField Shift+Enter', () {
    testWidgets('inserts a newline at the cursor and keeps the cursor there',
        (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(_host(controller, focusNode));
      await tester.pumpAndSettle();

      controller.value = const TextEditingValue(
        text: 'hello world',
        selection: TextSelection.collapsed(offset: 5),
      );
      focusNode.requestFocus();
      await tester.pump();

      await _pressShiftEnter(tester);

      expect(controller.text, 'hello\n world');
      expect(controller.selection.isCollapsed, isTrue);
      expect(controller.selection.baseOffset, 6);
    });

    testWidgets('replaces an active selection with the newline',
        (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(_host(controller, focusNode));
      await tester.pumpAndSettle();

      controller.value = const TextEditingValue(
        text: 'abcXYZdef',
        selection: TextSelection(baseOffset: 3, extentOffset: 6),
      );
      focusNode.requestFocus();
      await tester.pump();

      await _pressShiftEnter(tester);

      expect(controller.text, 'abc\ndef');
      expect(controller.selection.isCollapsed, isTrue);
      expect(controller.selection.baseOffset, 4);
    });

    testWidgets('appends when there is no valid selection', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(_host(controller, focusNode));
      await tester.pumpAndSettle();

      controller.text = 'line';
      focusNode.requestFocus();
      await tester.pump();

      await _pressShiftEnter(tester);

      expect(controller.text, 'line\n');
    });
  });
}
