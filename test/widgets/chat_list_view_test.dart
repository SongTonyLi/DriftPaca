import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_list_view.dart';

void main() {
  Widget buildTestApp(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
    );
  }

  testWidgets('positions the scroll-to-bottom button above the composer gutter', (tester) async {
    final messages = List.generate(
      30,
      (index) => OllamaMessage(
        'Message $index\nSecond line\nThird line',
        role: OllamaMessageRole.assistant,
      ),
    );

    await tester.pumpWidget(
      buildTestApp(
        SizedBox.expand(
          child: ChatListView(
            messages: messages,
            isAwaitingReply: false,
            bottomPadding: 110,
          ),
        ),
      ),
    );
    await tester.pump();

    final scrollableFinder = find.byWidgetPredicate(
      (widget) => widget is Scrollable && widget.axisDirection == AxisDirection.up,
      description: 'reversed chat scrollable',
    );
    expect(scrollableFinder, findsOneWidget);

    final scrollable = tester.state<ScrollableState>(scrollableFinder);
    scrollable.position.jumpTo(200);
    await tester.pumpAndSettle();

    final buttonFinder = find.byIcon(Icons.keyboard_arrow_down_rounded);
    expect(buttonFinder, findsOneWidget);

    final buttonRect = tester.getRect(find.byTooltip('Scroll to latest'));
    final scaffoldRect = tester.getRect(find.byType(Scaffold));

    expect(buttonRect.center.dx, greaterThan(scaffoldRect.width * 0.75));
    expect(scaffoldRect.bottom - buttonRect.bottom, greaterThanOrEqualTo(110));
  });
}
