import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/incognito_welcome.dart';

Widget _host({String? model, VoidCallback? onSelect}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: IncognitoWelcome(
          selectedModelName: model,
          onSelectModel: onSelect ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the label, title, facts and a working CTA', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_host(onSelect: () => tapped = true));
    await tester.pumpAndSettle(); // let the one-shot entrance finish

    expect(find.text('PRIVATE SESSION'), findsOneWidget);
    expect(find.text('Incognito Mode'), findsOneWidget);
    expect(find.text('Your profile stays unknown'), findsOneWidget);
    expect(find.text("Chats won't build your memory"), findsOneWidget);
    expect(find.text('Agent memory is off here'), findsOneWidget);
    expect(find.text('Select a model to start'), findsOneWidget);

    await tester.tap(find.text('Select a model to start'));
    expect(tapped, isTrue);
  });

  testWidgets('shows the selected model name on the CTA', (tester) async {
    await tester.pumpWidget(_host(model: 'llama3.2'));
    await tester.pumpAndSettle();
    expect(find.text('llama3.2'), findsOneWidget);
    expect(find.text('Select a model to start'), findsNothing);
  });

  testWidgets('settles to a static screen (no continuous animation)',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'entrance is one-shot; idle incognito must not keep animating');
  });
}
