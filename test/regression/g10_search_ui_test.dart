import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_think_block.dart';
import 'package:llamaseek/Utils/favicon_cache.dart';
import 'package:llamaseek/Widgets/search_card.dart';
import 'package:llamaseek/Widgets/search_detail_dialog.dart';
import 'package:shimmer/shimmer.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

class _RecordingObserver extends NavigatorObserver {
  TransitionRoute<dynamic>? pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is TransitionRoute<dynamic>) {
      pushed = route;
    }
  }
}

void main() {
  group('search source preview truncation', () {
    testWidgets('does not split a surrogate pair at the boundary',
        (tester) async {
      // 299 ASCII characters followed by an astral-plane emoji so that the
      // emoji straddles the 300th UTF-16 code unit.
      final content = '${'a' * 299}😀${'b' * 100}';
      final segment = SearchCardSegment(
        query: 'q',
        isComplete: true,
        resultCount: 1,
        sources: [
          SearchSource(
            url: 'https://example.com',
            domain: 'example.com',
            title: '',
            content: content,
          ),
        ],
      );

      await tester.pumpWidget(_host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => SearchDetailDialog.show(context, segment),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final preview = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .firstWhere((s) => s.startsWith('aaa'));

      expect(preview.runes.contains(0xFFFD), isFalse);
      expect(preview.codeUnits.any((u) => u >= 0xD800 && u <= 0xDBFF),
          isTrue,
          reason: 'the emoji should be kept intact, not split');
      expect(preview.endsWith('…'), isTrue);

      // Dismiss so the shared open-guard resets for later tests.
      Navigator.of(tester.element(find.text('open'))).pop();
      await tester.pumpAndSettle();
    });
  });

  group('SearchDetailDialog.show', () {
    testWidgets('two calls in one frame open only one bottom sheet',
        (tester) async {
      final segment = SearchCardSegment(
        query: 'flutter',
        isComplete: true,
        resultCount: 2,
      );

      await tester.pumpWidget(_host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () {
              SearchDetailDialog.show(context, segment);
              SearchDetailDialog.show(context, segment);
            },
            child: const Text('open'),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchDetailDialog), findsOneWidget);

      Navigator.of(tester.element(find.text('open'))).pop();
      await tester.pumpAndSettle();
    });
  });

  group('ThinkBlockParser.tryParse', () {
    test('closes at the final </think>, not one mentioned in reasoning', () {
      const content =
          '<think>The user asked about the </think> tag in markup.</think>'
          'Here is the answer.';

      final parsed = ThinkBlockParser.tryParse(content);

      expect(parsed, isNotNull);
      expect(parsed!.isThinkingComplete, isTrue);
      expect(parsed.thinkContent,
          'The user asked about the </think> tag in markup.');
      expect(parsed.responseContent, 'Here is the answer.');
    });

    testWidgets('manual expand wins over pending thinking auto-collapse',
        (tester) async {
      var complete = false;
      late StateSetter rebuild;

      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return ThinkBlockWidget(
                content: 'Reasoning',
                isComplete: complete,
                isStreaming: !complete,
              );
            },
          ),
        ),
      );

      complete = true;
      rebuild(() {});
      await tester.pump();
      await tester.tap(find.textContaining('Thought'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 100));

      final transition =
          tester.widget<SizeTransition>(find.byType(SizeTransition));
      expect(transition.sizeFactor.value, 1.0);
    });
  });

  group('SearchCard result count label', () {
    testWidgets('uses the singular for a single source', (tester) async {
      final segment = SearchCardSegment(
        query: 'q',
        isComplete: true,
        resultCount: 1,
      );
      await tester.pumpWidget(_host(SearchCard(segment: segment)));
      await tester.pumpAndSettle();

      expect(find.text('1 source'), findsOneWidget);
      expect(find.text('1 sources'), findsNothing);
    });

    testWidgets('uses the plural for multiple sources', (tester) async {
      final segment = SearchCardSegment(
        query: 'q',
        isComplete: true,
        resultCount: 3,
      );
      await tester.pumpWidget(_host(SearchCard(segment: segment)));
      await tester.pumpAndSettle();

      expect(find.text('3 sources'), findsOneWidget);
    });

    testWidgets('pending rows are static when animations are disabled',
        (tester) async {
      final segment = SearchCardSegment(
        query: 'q',
        urls: [
          SearchURLStatus(
            url: 'https://example.com',
            domain: 'example.com',
            state: SearchURLState.pending,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(body: SearchCard(segment: segment)),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Shimmer), findsNothing);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsWidgets);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('tapping an in-progress card collapses its source list',
        (tester) async {
      final segment = SearchCardSegment(
        query: 'q',
        urls: [
          SearchURLStatus(
            url: 'https://example.com',
            domain: 'example.com',
            state: SearchURLState.pending,
          ),
        ],
      );

      await tester.pumpWidget(_host(SearchCard(segment: segment)));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.textContaining('Searching:'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final transition =
          tester.widget<SizeTransition>(find.byType(SizeTransition));
      expect(transition.sizeFactor.value, 0.0);
    });
  });

  group('SearchDetailDialog reduced motion', () {
    testWidgets('full source dialog has zero transition duration',
        (tester) async {
      final observer = _RecordingObserver();
      final segment = SearchCardSegment(
        query: 'q',
        isComplete: true,
        sources: [
          SearchSource(
            url: 'https://example.com',
            domain: 'example.com',
            title: 'Example source',
            content: 'Full source content',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [observer],
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(body: SearchDetailDialog(segment: segment)),
          ),
        ),
      );
      await tester.drag(
        find.text('Example source'),
        const Offset(-100, 0),
      );
      await tester.pump();

      expect(observer.pushed!.transitionDuration, Duration.zero);
      expect(observer.pushed!.reverseTransitionDuration, Duration.zero);
    });

    testWidgets('source favicon pop is settled immediately', (tester) async {
      FaviconCache.instance.clearForTest();
      final segment = SearchCardSegment(
        query: 'q',
        isComplete: true,
        sources: [
          SearchSource(
            url: 'https://reduced-motion.invalid',
            domain: 'reduced-motion.invalid',
            title: 'Example source',
            content: 'Full source content',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Scaffold(body: SearchDetailDialog(segment: segment)),
            ),
          ),
        ),
      );

      final fade = tester.widget<FadeTransition>(
        find.byKey(const ValueKey('source-favicon-fade')),
      );
      expect(fade.opacity.value, 1.0);

      await tester.pumpWidget(const SizedBox.shrink());
      FaviconCache.instance.clearForTest();
    });
  });
}
