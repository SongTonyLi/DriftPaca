import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/normal_welcome.dart';

Widget _host({String? model, VoidCallback? onSelect}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: NormalWelcome(
          selectedModelName: model,
          onSelectModel: onSelect ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the brand label, title and a working CTA', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_host(onSelect: () => tapped = true));
    await tester.pumpAndSettle(); // let the one-shot entrance finish

    expect(find.text('WELCOME'), findsOneWidget);
    expect(find.text('Start a conversation'), findsOneWidget);
    expect(find.text('Select a model to start'), findsOneWidget);

    await tester.tap(find.text('Select a model to start'));
    expect(tapped, isTrue);
  });

  testWidgets('shows the selected model name on the CTA', (tester) async {
    await tester.pumpWidget(_host(model: 'qwen'));
    await tester.pumpAndSettle();
    expect(find.text('qwen'), findsOneWidget);
    expect(find.text('Select a model to start'), findsNothing);
  });

  testWidgets('settles to a static screen (no continuous animation)',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'entrance is one-shot; idle welcome must not keep animating');
  });
}
