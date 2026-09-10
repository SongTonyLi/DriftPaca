import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/page_fetch_outcome.dart';
import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart';
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
  setUpAll(() {
    // Pumping a full ChatBubble (new in this file — the rest of it pumps
    // SearchCard/SearchDetailDialog directly) exercises markdown rendering,
    // which pulls a Google Font for code spans. Disable runtime fetching so
    // tests are deterministic offline, matching test/widgets/chat_bubble_test.dart.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

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

  group('SearchDetailDialog failed source reasons', () {
    testWidgets('shows a typed failure reason and keeps the URL tappable',
        (tester) async {
      final segment = SearchCardSegment(
        query: 'q',
        isComplete: true,
        urls: [
          SearchURLStatus(
            url: 'https://example.com/forbidden',
            domain: 'example.com',
            state: SearchURLState.failed,
            outcome: const PageFetchOutcome(
              state: PageFetchState.httpError,
              elapsed: Duration(milliseconds: 50),
              httpStatus: 403,
            ),
          ),
        ],
      );

      await tester.pumpWidget(_host(SearchDetailDialog(segment: segment)));
      await tester.pump();

      expect(find.text('Access denied (403)'), findsOneWidget);
      final row = find.ancestor(
        of: find.text('Access denied (403)'),
        matching: find.byType(InkWell),
      );
      expect(row, findsOneWidget);
      expect(tester.widget<InkWell>(row).onTap, isNotNull);
    });

    testWidgets('labels a legacy unknown failure without inventing a cause',
        (tester) async {
      final segment = SearchCardSegment(
        query: 'q',
        isComplete: true,
        urls: [
          SearchURLStatus(
            url: 'https://legacy.example.com',
            domain: 'legacy.example.com',
            state: SearchURLState.failed,
          ),
        ],
      );

      await tester.pumpWidget(_host(SearchDetailDialog(segment: segment)));
      await tester.pump();

      expect(find.text('Page text unavailable'), findsOneWidget);
    });
  });

  group('goal-directed research rendering', () {
    testWidgets(
        'renders multiple rounds, goal progress, and a termination banner',
        (tester) async {
      final message =
          OllamaMessage('Final answer text.', role: OllamaMessageRole.assistant);
      final segments = <MessageSegment>[
        SearchCardSegment(
          query: 'first query',
          isComplete: true,
          resultCount: 2,
          round: 1,
        ),
        SearchCardSegment(
          query: 'first query rephrased',
          skipReason: 'You already asked something very close to this.',
          isComplete: true,
          round: 2,
        ),
        SearchCardSegment(
          query: 'second query',
          isComplete: true,
          resultCount: 1,
          round: 3,
        ),
        ResearchLedgerSegment(
          objective: 'What is the objective of this research?',
          entries: const [
            LedgerEntryView(
              query: 'first query',
              searched: true,
              ranges: [SourceIdRange(1, 2)],
              excerpt: 'supporting evidence',
            ),
            LedgerEntryView(
              query: 'second query',
              searched: true,
              ranges: [SourceIdRange(3, 3)],
            ),
            LedgerEntryView(query: 'third query', searched: false),
          ],
          terminationReason: 'converged',
        ),
      ];

      await tester.pumpWidget(
          _host(ChatBubble(message: message, searchSegments: segments)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Every round is visible, in order, including the skipped one.
      expect(find.textContaining('Search 1'), findsOneWidget);
      expect(find.textContaining('Search 2'), findsOneWidget);
      expect(find.textContaining('Search 3'), findsOneWidget);
      expect(
          find.text('You already asked something very close to this.'),
          findsOneWidget);
      // Goal progress: objective, plus an open sub-goal never searched.
      expect(find.text('What is the objective of this research?'),
          findsOneWidget);
      expect(find.text('third query'), findsOneWidget);
      // Termination banner reflects convergence, not a safety-cap cutoff.
      expect(find.textContaining('Research complete'), findsOneWidget);
    });

    testWidgets(
        'renders a pre-existing (round/skipReason/ledger-less) segment list unchanged',
        (tester) async {
      // Exactly what step 10's decoder still produces for a chat persisted
      // before this work — no round, no skipReason, no ResearchLedgerSegment.
      final message =
          OllamaMessage('Old answer text.', role: OllamaMessageRole.assistant);
      final segments = <MessageSegment>[
        ThinkingSegment('Some earlier reasoning.'),
        SearchCardSegment(
          query: 'legacy query',
          isComplete: true,
          resultCount: 1,
          urls: [
            SearchURLStatus(
              url: 'https://example.com',
              domain: 'example.com',
              state: SearchURLState.success,
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
          _host(ChatBubble(message: message, searchSegments: segments)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      // Byte-identical to the pre-round/skip/ledger label format.
      expect(find.text('Searched: "legacy query"'), findsOneWidget);
      expect(find.textContaining('Search 1'), findsNothing);
      expect(find.text('Research goal'), findsNothing);
    });

    testWidgets('a re-searched sub-goal shows every id block it gathered',
        (tester) async {
      // The ids between the two blocks belong to other sub-goals, so the
      // chip lists the ranges instead of merging them into one span. Before
      // the ledger accumulated evidence this second block was dropped
      // outright — the panel jumped …17-24 straight to 33-40.
      await tester.pumpWidget(_host(ChatBubble(
        message: OllamaMessage('Answer.', role: OllamaMessageRole.assistant),
        searchSegments: [
          ResearchLedgerSegment(
            objective: 'goal',
            entries: const [
              LedgerEntryView(
                query: 'TikTok new grad offer timing',
                searched: true,
                ranges: [SourceIdRange(1, 8), SourceIdRange(25, 32)],
              ),
            ],
            terminationReason: 'converged',
          ),
        ],
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('1–8 · 25–32'), findsOneWidget);
      // Two searches produced this sub-goal, and the banner counts searches.
      expect(
          find.textContaining('across 2 searches'), findsOneWidget);
    });

    testWidgets('an in-progress run names the next thing it will research',
        (tester) async {
      await tester.pumpWidget(_host(ChatBubble(
        message: OllamaMessage('', role: OllamaMessageRole.assistant),
        searchSegments: [
          ResearchLedgerSegment(
            objective: 'goal',
            entries: const [
              LedgerEntryView(
                query: 'done query',
                searched: true,
                ranges: [SourceIdRange(1, 2)],
              ),
              LedgerEntryView(query: 'open query', searched: false),
            ],
          ),
        ],
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Next — researching "open query"'), findsOneWidget);
      // The termination banner is the finished-run counterpart; only one of
      // the two ever shows.
      expect(find.textContaining('Research complete'), findsNothing);
    });

    testWidgets('an in-progress run with nothing open says it is drafting',
        (tester) async {
      await tester.pumpWidget(_host(ChatBubble(
        message: OllamaMessage('', role: OllamaMessageRole.assistant),
        searchSegments: [
          ResearchLedgerSegment(
            objective: 'goal',
            entries: const [
              LedgerEntryView(
                query: 'done query',
                searched: true,
                ranges: [SourceIdRange(1, 2)],
              ),
            ],
          ),
        ],
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Next — drafting the answer'), findsOneWidget);
    });

    testWidgets('a run that never searched says so instead of claiming 0 searches',
        (tester) async {
      await tester.pumpWidget(_host(ChatBubble(
        message: OllamaMessage('Answer.', role: OllamaMessageRole.assistant),
        searchSegments: [
          ResearchLedgerSegment(
            objective: 'goal',
            entries: const [
              LedgerEntryView(query: 'never searched', searched: false),
            ],
            terminationReason: 'converged',
          ),
        ],
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Answered without searching'), findsOneWidget);
      expect(find.textContaining('0 searches'), findsNothing);
    });

    testWidgets('a finished run with no sub-goals at all hides the panel',
        (tester) async {
      // Web search was on, the model answered straight from the chat, and
      // the goal derivation opened nothing. There is no research to frame.
      await tester.pumpWidget(_host(ChatBubble(
        message: OllamaMessage('Answer.', role: OllamaMessageRole.assistant),
        searchSegments: [
          ResearchLedgerSegment(
            objective: 'goal',
            terminationReason: 'converged',
          ),
        ],
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Research goal'), findsNothing);
    });

    testWidgets('mid-run the panel shows the goal before any search lands',
        (tester) async {
      // The opening ledger update carries the goal and no entries. This is
      // the state the panel is created in now, and it is exactly when the
      // reader most needs to see what the run is going after.
      await tester.pumpWidget(_host(ChatBubble(
        message: OllamaMessage('', role: OllamaMessageRole.assistant),
        searchSegments: [
          ResearchLedgerSegment(objective: 'Establish the 2024 GDP figure'),
        ],
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Research goal'), findsOneWidget);
      expect(find.text('Establish the 2024 GDP figure'), findsOneWidget);
      expect(find.text('Next — drafting the answer'), findsOneWidget);
    });
  });
}
