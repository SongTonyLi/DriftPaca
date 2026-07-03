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

  testWidgets('prunes bubble cache entries for messages removed by in-place mutation', (tester) async {
    // Small enough that every message is laid out in the viewport, so the
    // SliverList.builder actually constructs (and caches) all non-newest ones.
    final messages = List.generate(
      6,
      (index) => OllamaMessage(
        'Message $index',
        role: OllamaMessageRole.assistant,
      ),
    );
    // Remove the last two (mirroring regenerateMessage's removeRange). Only the
    // *newest* message (last in the list, reversed index 0) is rendered via the
    // uncached ObserveSize path; every earlier message goes through _bubbleCache.
    // So messages[4] is a genuinely-cached entry that must be pruned once removed
    // (messages[5] was the newest and was never cached — asserting its absence is
    // harmless, but messages[4] is the real proof).
    final removedIds = [messages[4].id, messages[5].id];
    final cachedRemovedId = messages[4].id;

    await tester.pumpWidget(
      buildTestApp(
        SizedBox.expand(
          child: ChatListView(
            messages: messages,
            isAwaitingReply: false,
          ),
        ),
      ),
    );
    await tester.pump();

    // Sanity: the removed non-newest message must have been cached, otherwise
    // the test proves nothing about pruning.
    dynamic state = tester.state(find.byType(ChatListView));
    final Set<String> cachedBefore = state.debugCachedBubbleIds;
    expect(cachedBefore, contains(cachedRemovedId),
        reason: 'the removed non-newest message should have been cached before removal');

    // Mirror ChatProvider.regenerateMessage/deleteMessage: mutate the SAME
    // List object in place (removeRange) so the list reference stays identical
    // and ChatListView treats it as "same list, just updated".
    messages.removeRange(4, messages.length);

    await tester.pumpWidget(
      buildTestApp(
        SizedBox.expand(
          child: ChatListView(
            messages: messages,
            isAwaitingReply: false,
          ),
        ),
      ),
    );
    await tester.pump();

    state = tester.state(find.byType(ChatListView));
    final Set<String> cachedAfter = state.debugCachedBubbleIds;
    for (final id in removedIds) {
      expect(cachedAfter, isNot(contains(id)),
          reason: 'stale bubble cache entry for a removed message should be pruned');
    }
  });
}
