import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/page_fetch_outcome.dart';
import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Models/research_phase.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_think_block.dart';
import 'package:llamaseek/Utils/favicon_cache.dart';
import 'package:llamaseek/Widgets/research_activity_strip.dart';
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

  group('the live thinking block', () {
    testWidgets('an open block with nothing in it yet already says Thinking',
        (tester) async {
      // The empty moment matters: the header has to be on screen before the
      // first reasoning token, or the bubble is blank for the whole of
      // time-to-first-token. A COMPLETE empty segment is still skipped.
      final segment = ThinkingSegment('', isComplete: false, startedAt: DateTime.now());

      await tester.pumpWidget(_host(ChatBubble(
        message: OllamaMessage('', role: OllamaMessageRole.assistant),
        isStreaming: true,
        searchSegments: [segment],
      )));
      await tester.pump();

      expect(find.text('Thinking...'), findsOneWidget);
      expect(find.byKey(ObjectKey(segment)), findsOneWidget);
    });

    testWidgets('completing the block keeps the same widget and reads its time',
        (tester) async {
      final segment = ThinkingSegment('', isComplete: false, startedAt: DateTime.now());
      final bubble = ChatBubble(
        message: OllamaMessage('', role: OllamaMessageRole.assistant),
        isStreaming: true,
        searchSegments: [segment],
      );

      await tester.pumpWidget(_host(bubble));
      await tester.pump();
      final live = tester.element(find.byKey(ObjectKey(segment)));

      // Exactly what ChatPageViewModel does when the turn ends: the same
      // instance is filled in and closed, never replaced.
      segment.text = 'Weighed two sources.';
      segment.isComplete = true;
      segment.elapsedSeconds = 3;

      await tester.pumpWidget(_host(ChatBubble(
        message: OllamaMessage('', role: OllamaMessageRole.assistant),
        isStreaming: true,
        searchSegments: [segment],
      )));
      await tester.pump();

      // Same element: the block collapses in place, keeping its stopwatch
      // and its expand animation, instead of vanishing and reappearing as
      // a fresh "Thought" row below.
      expect(identical(tester.element(find.byKey(ObjectKey(segment))), live),
          isTrue);
      expect(find.text('Thought for 3 seconds'), findsOneWidget);
    });

    testWidgets('a reloaded message reads how long it thought for',
        (tester) async {
      await tester.pumpWidget(_host(ChatBubble(
        message: OllamaMessage('Answer.', role: OllamaMessageRole.assistant),
        searchSegments: [
          ThinkingSegment('Earlier reasoning.', elapsedSeconds: 5),
        ],
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Thought for 5 seconds'), findsOneWidget);
    });

    testWidgets('a complete block with no recorded time still just says Thought',
        (tester) async {
      // Every segment persisted before elapsedSeconds existed.
      await tester.pumpWidget(_host(ChatBubble(
        message: OllamaMessage('Answer.', role: OllamaMessageRole.assistant),
        searchSegments: [ThinkingSegment('Earlier reasoning.')],
      )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Thought'), findsOneWidget);
    });
  });

  group('the research activity strip', () {
    testWidgets('a streaming bubble says what the loop is doing right now',
        (tester) async {
      // Everything between "sent" and "first token of the answer" used to
      // look identical from the outside: a llama and nothing else.
      await tester.pumpWidget(_host(ChatBubble(
        message: OllamaMessage('', role: OllamaMessageRole.assistant),
        isStreaming: true,
        researchPhase: ResearchPhase.searching,
        researchPhaseStartedAt: DateTime.now(),
      )));
      await tester.pump();

      expect(find.byType(ResearchActivityStrip), findsOneWidget);
      expect(find.text('Searching'), findsOneWidget);

      // Drop the bubble so the strip's counter timer is cancelled.
      await tester.pumpWidget(_host(const SizedBox.shrink()));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a finished bubble has no strip', (tester) async {
      await tester.pumpWidget(_host(ChatBubble(
        message: OllamaMessage('Answer.', role: OllamaMessageRole.assistant),
        researchPhase: ResearchPhase.searching,
      )));
      await tester.pump();

      expect(find.byType(ResearchActivityStrip), findsNothing);
    });

    testWidgets('a run that has finished researching drops the strip',
        (tester) async {
      // `done` fires while the bubble is still streaming out the answer;
      // "Done" is not a thing worth a live pill.
      await tester.pumpWidget(_host(ChatBubble(
        message: OllamaMessage('Answer.', role: OllamaMessageRole.assistant),
        isStreaming: true,
        researchPhase: ResearchPhase.done,
      )));
      await tester.pump();

      expect(find.byType(ResearchActivityStrip), findsNothing);
    });

    testWidgets('no phase means no strip, so the legacy path is untouched',
        (tester) async {
      await tester.pumpWidget(_host(ChatBubble(
        message: OllamaMessage('Answer.', role: OllamaMessageRole.assistant),
        isStreaming: true,
      )));
      await tester.pump();

      expect(find.byType(ResearchActivityStrip), findsNothing);
    });
  });

  group('research ledger panel motion', () {
    // Not streaming: the panel is what these tests watch, and the streaming
    // llama would put its own permanent animation in every transition count.
    Widget ledgerBubble(ResearchLedgerSegment segment) => ChatBubble(
          message: OllamaMessage('', role: OllamaMessageRole.assistant),
          searchSegments: [segment],
        );

    /// Every transition inside the bubble, as raw values: 1.0 means
    /// "settled", anything less means "still moving". Scoped to the bubble
    /// so the Scaffold's own (permanently parked) FAB transition doesn't
    /// count as motion.
    Iterable<double> scaleValues(WidgetTester tester) => tester
        .widgetList<ScaleTransition>(find.descendant(
          of: find.byType(ChatBubble),
          matching: find.byType(ScaleTransition),
        ))
        .map((t) => t.scale.value);

    Iterable<double> fadeValues(WidgetTester tester) => tester
        .widgetList<FadeTransition>(find.descendant(
          of: find.byType(ChatBubble),
          matching: find.byType(FadeTransition),
        ))
        .map((t) => t.opacity.value);

    testWidgets('while the goal is being derived the objective shimmers',
        (tester) async {
      // The window between onPhase(framingGoal) and the derived goal
      // landing: the objective on screen is still the user's raw question,
      // so it reads as provisional instead of as the run's goal.
      final segment = ResearchLedgerSegment(objective: 'what is the 2024 GDP')
        ..isDeriving = true;

      await tester.pumpWidget(_host(ledgerBubble(segment)));
      await tester.pump();

      expect(find.byType(Shimmer), findsOneWidget);
      expect(find.text('Framing the research goal…'), findsOneWidget);
      expect(find.text('Next — drafting the answer'), findsNothing);
    });

    testWidgets('derivation is static and settled under reduced motion',
        (tester) async {
      final segment = ResearchLedgerSegment(objective: 'what is the 2024 GDP')
        ..isDeriving = true;

      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: ledgerBubble(segment)),
        ),
      ));
      await tester.pump();

      expect(find.byType(Shimmer), findsNothing);
      expect(find.text('Framing the research goal…'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('a sub-goal turning searched transitions its glyph and row',
        (tester) async {
      final segment = ResearchLedgerSegment(
        objective: 'goal',
        entries: const [
          LedgerEntryView(
            query: 'first query',
            searched: true,
            ranges: [SourceIdRange(1, 2)],
          ),
          LedgerEntryView(query: 'second query', searched: false),
        ],
      );

      await tester.pumpWidget(_host(ledgerBubble(segment)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Nothing moves before the flip: the panel was created with the first
      // row already searched, and rows decoded from history never animate.
      expect(scaleValues(tester).every((v) => v == 1.0), isTrue);
      expect(find.text('3'), findsNothing);

      segment.entries = const [
        LedgerEntryView(
          query: 'first query',
          searched: true,
          ranges: [SourceIdRange(1, 2)],
        ),
        LedgerEntryView(
          query: 'second query',
          searched: true,
          ranges: [SourceIdRange(3, 3)],
        ),
      ];

      await tester.pumpWidget(_host(ledgerBubble(segment)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      // The chip scales in over the dot it replaces...
      final glyphScales = tester
          .widgetList<ScaleTransition>(find.ancestor(
            of: find.text('3'),
            matching: find.byType(ScaleTransition),
          ))
          .map((t) => t.scale.value);
      expect(glyphScales, isNotEmpty);
      expect(glyphScales.any((v) => v < 1.0), isTrue,
          reason: 'the new chip should still be scaling in');

      // ...and the newly searched row fades in as a whole.
      final rowFades = tester
          .widgetList<FadeTransition>(find.ancestor(
            of: find.text('second query'),
            matching: find.byType(FadeTransition),
          ))
          .map((t) => t.opacity.value);
      expect(rowFades.any((v) => v < 1.0), isTrue,
          reason: 'the newly searched row should still be fading in');

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('3'), findsOneWidget);
      expect(scaleValues(tester).every((v) => v == 1.0), isTrue);
      expect(fadeValues(tester).every((v) => v == 1.0), isTrue);
    });

    testWidgets('a settled searched row does not re-animate on a later rebuild',
        (tester) async {
      final segment = ResearchLedgerSegment(
        objective: 'goal',
        entries: const [
          LedgerEntryView(query: 'only query', searched: false),
        ],
      );

      await tester.pumpWidget(_host(ledgerBubble(segment)));
      await tester.pump();

      segment.entries = const [
        LedgerEntryView(
          query: 'only query',
          searched: true,
          ranges: [SourceIdRange(1, 1)],
        ),
      ];
      await tester.pumpWidget(_host(ledgerBubble(segment)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // An unrelated rebuild (a sharper objective landing) must not replay
      // the row's entrance: the panel remembers what it has already shown.
      segment.objective = 'a sharper goal';
      await tester.pumpWidget(_host(ledgerBubble(segment)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final rowFades = tester
          .widgetList<FadeTransition>(find.ancestor(
            of: find.text('only query'),
            matching: find.byType(FadeTransition),
          ))
          .map((t) => t.opacity.value);
      expect(rowFades.every((v) => v == 1.0), isTrue);

      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the next-step line cross-fades when it changes',
        (tester) async {
      final segment = ResearchLedgerSegment(
        objective: 'goal',
        entries: const [
          LedgerEntryView(query: 'open query', searched: false),
        ],
      );

      await tester.pumpWidget(_host(ledgerBubble(segment)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Next — researching "open query"'), findsOneWidget);

      segment.entries = const [
        LedgerEntryView(
          query: 'open query',
          searched: true,
          ranges: [SourceIdRange(1, 1)],
        ),
      ];
      await tester.pumpWidget(_host(ledgerBubble(segment)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      // Both lines are on screen mid-cross-fade, the old one on its way out.
      expect(find.text('Next — researching "open query"'), findsOneWidget);
      expect(find.text('Next — drafting the answer'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Next — researching "open query"'), findsNothing);
      expect(find.text('Next — drafting the answer'), findsOneWidget);
    });

    testWidgets('a sub-goal turning searched is instant under reduced motion',
        (tester) async {
      final segment = ResearchLedgerSegment(
        objective: 'goal',
        entries: const [
          LedgerEntryView(query: 'open query', searched: false),
        ],
      );

      Widget host() => MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Scaffold(body: ledgerBubble(segment)),
            ),
          );

      await tester.pumpWidget(host());
      await tester.pump();

      segment.entries = const [
        LedgerEntryView(
          query: 'open query',
          searched: true,
          ranges: [SourceIdRange(7, 7)],
        ),
      ];
      await tester.pumpWidget(host());
      await tester.pump();

      expect(find.text('7'), findsOneWidget);
      expect(find.text('Next — drafting the answer'), findsOneWidget);
      expect(scaleValues(tester).every((v) => v == 1.0), isTrue);
      expect(fadeValues(tester).every((v) => v == 1.0), isTrue);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
