import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Widgets/search_card.dart';
import 'package:shimmer/shimmer.dart';

/// Motion of a search card as a run progresses: the query reveal, the
/// staggered URL rows, the fetch progress line, and the completion
/// transitions (icon swap + counting "N sources").
///
/// These cards are pumped directly, the way
/// `test/regression/g10_search_ui_test.dart` does. An in-progress card holds
/// a spinner and a `Shimmer`, neither of which ever settles, so every test
/// here advances the clock with explicit `pump(Duration)` calls instead of
/// `pumpAndSettle`.

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _reducedMotionHost(Widget child) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: child),
      ),
    );

/// Pumps a card whose segment is mutated in place by the test, exactly as
/// the view model mutates it during a run: the same `SearchCardSegment`
/// instance is handed to a freshly built `SearchCard` on every rebuild.
Future<StateSetter> _pumpLiveCard(
  WidgetTester tester,
  SearchCardSegment segment, {
  bool reducedMotion = false,
}) async {
  late StateSetter rebuild;
  final card = StatefulBuilder(
    builder: (context, setState) {
      rebuild = setState;
      return SearchCard(segment: segment);
    },
  );
  await tester.pumpWidget(
      reducedMotion ? _reducedMotionHost(card) : _host(card));
  await tester.pump();
  return rebuild;
}

SearchURLStatus _url(String url,
        [SearchURLState state = SearchURLState.pending]) =>
    SearchURLStatus(
      url: url,
      domain: Uri.parse(url).host,
      title: '',
      state: state,
    );

double _rowOpacity(WidgetTester tester, String url) => tester
    .widget<FadeTransition>(find.byKey(ValueKey('search-card-url-fade-$url')))
    .opacity
    .value;

double _queryReveal(WidgetTester tester) => tester
    .widget<Align>(find.byKey(const ValueKey('search-card-query-clip')))
    .widthFactor!;

/// The progress line's *target* fill — what the card is animating towards.
double _progressTarget(WidgetTester tester) => tester
    .widget<AnimatedFractionallySizedBox>(
        find.byKey(const ValueKey('search-card-progress')))
    .widthFactor!;

/// The progress line's *rendered* fill this frame.
double _progressRendered(WidgetTester tester) => tester
    .widget<FractionallySizedBox>(find.descendant(
      of: find.byKey(const ValueKey('search-card-progress')),
      matching: find.byType(FractionallySizedBox),
    ))
    .widthFactor!;

double _progressOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
        find.byKey(const ValueKey('search-card-progress-fade')))
    .opacity
    .value;

/// The count rendered in the header's "N sources" label this frame.
int _sourceCount(WidgetTester tester) {
  final label = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .whereType<String>()
      .firstWhere((s) => s.endsWith(' source') || s.endsWith(' sources'));
  return int.parse(label.split(' ').first);
}

/// Lets the card's pre-existing 500 ms auto-collapse timer fire and its
/// collapse finish, so a completed card leaves no pending timer behind.
Future<void> _settleAutoCollapse(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 260));
}

void main() {
  group('SearchCard query reveal', () {
    testWidgets('a live card clips its query open', (tester) async {
      await _pumpLiveCard(tester, SearchCardSegment(query: 'quantum foam'));

      expect(_queryReveal(tester), 0.0);

      await tester.pump(const Duration(milliseconds: 160));
      final mid = _queryReveal(tester);
      expect(mid, greaterThan(0.0));
      expect(mid, lessThan(1.0));

      await tester.pump(const Duration(milliseconds: 300));
      expect(_queryReveal(tester), 1.0);
    });

    testWidgets('a card created complete shows its query at once',
        (tester) async {
      await tester.pumpWidget(_host(SearchCard(
        segment: SearchCardSegment(
            query: 'quantum foam', isComplete: true, resultCount: 2),
      )));

      expect(_queryReveal(tester), 1.0);
    });
  });

  group('SearchCard url rows', () {
    testWidgets('rows stagger in when the first urls land', (tester) async {
      final segment = SearchCardSegment(query: 'q');
      final rebuild = await _pumpLiveCard(tester, segment);
      await tester.pump(const Duration(milliseconds: 400));

      segment.urls = [
        _url('https://a.example'),
        _url('https://b.example'),
        _url('https://c.example'),
      ];
      rebuild(() {});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 24));

      final first = _rowOpacity(tester, 'https://a.example');
      expect(first, greaterThan(0.0));
      expect(first, lessThan(1.0));
      // Later rows are still behind the first one's interval.
      expect(_rowOpacity(tester, 'https://c.example'), lessThan(first));

      await tester.pump(const Duration(milliseconds: 600));
      expect(_rowOpacity(tester, 'https://a.example'), 1.0);
      expect(_rowOpacity(tester, 'https://c.example'), 1.0);
    });

    testWidgets('a card created complete renders its rows settled',
        (tester) async {
      await tester.pumpWidget(_host(SearchCard(
        segment: SearchCardSegment(
          query: 'q',
          isComplete: true,
          resultCount: 2,
          urls: [
            _url('https://a.example', SearchURLState.success),
            _url('https://b.example', SearchURLState.failed),
          ],
        ),
      )));

      expect(_rowOpacity(tester, 'https://a.example'), 1.0);
      expect(_rowOpacity(tester, 'https://b.example'), 1.0);
    });
  });

  group('SearchCard progress line', () {
    testWidgets('fills fetched/total and fades out when the card completes',
        (tester) async {
      final segment = SearchCardSegment(
        query: 'q',
        urls: [
          _url('https://a.example'),
          _url('https://b.example'),
          _url('https://c.example'),
          _url('https://d.example'),
        ],
      );
      final rebuild = await _pumpLiveCard(tester, segment);
      await tester.pump(const Duration(milliseconds: 600));

      expect(_progressTarget(tester), 0.0);
      expect(_progressOpacity(tester), 1.0);

      segment.urls[0].state = SearchURLState.success;
      rebuild(() {});
      await tester.pump();
      expect(_progressTarget(tester), 0.25);

      segment.urls[1].state = SearchURLState.failed;
      rebuild(() {});
      await tester.pump();
      expect(_progressTarget(tester), 0.5);

      segment.urls[2].state = SearchURLState.success;
      segment.urls[3].state = SearchURLState.success;
      rebuild(() {});
      await tester.pump();
      expect(_progressTarget(tester), 1.0);

      segment.isComplete = true;
      segment.resultCount = 4;
      rebuild(() {});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));

      expect(_progressOpacity(tester), 0.0);

      await _settleAutoCollapse(tester);
    });

    testWidgets('a card created complete never shows a progress line',
        (tester) async {
      await tester.pumpWidget(_host(SearchCard(
        segment: SearchCardSegment(
          query: 'q',
          isComplete: true,
          resultCount: 1,
          urls: [_url('https://a.example', SearchURLState.success)],
        ),
      )));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('search-card-progress')), findsNothing);
    });
  });

  group('SearchCard completion', () {
    testWidgets('the source count counts up when completion happens live',
        (tester) async {
      final segment = SearchCardSegment(
        query: 'q',
        urls: [_url('https://a.example')],
      );
      final rebuild = await _pumpLiveCard(tester, segment);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('sources'), findsNothing);

      segment.urls[0].state = SearchURLState.success;
      segment.isComplete = true;
      segment.resultCount = 12;
      rebuild(() {});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final mid = _sourceCount(tester);
      expect(mid, greaterThan(0));
      expect(mid, lessThan(12));

      // Stay under the existing 500 ms auto-collapse so this asserts the
      // count-up, not the collapse.
      await tester.pump(const Duration(milliseconds: 300));
      expect(_sourceCount(tester), 12);

      await _settleAutoCollapse(tester);
    });

    testWidgets('a card created complete shows its final count immediately',
        (tester) async {
      await tester.pumpWidget(_host(SearchCard(
        segment: SearchCardSegment(
            query: 'q', isComplete: true, resultCount: 3),
      )));

      expect(find.text('3 sources'), findsOneWidget);
    });

    testWidgets('the header icon swaps through a transition', (tester) async {
      final segment = SearchCardSegment(query: 'q');
      final rebuild = await _pumpLiveCard(tester, segment);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byIcon(Icons.check_circle_outline), findsNothing);

      segment.isComplete = true;
      segment.resultCount = 1;
      rebuild(() {});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Mid-swap the incoming glyph is scaled/faded in, not simply present.
      final scale = tester.widget<ScaleTransition>(find.ancestor(
        of: find.byIcon(Icons.check_circle_outline),
        matching: find.byType(ScaleTransition),
      ));
      expect(scale.scale.value, lessThan(1.0));

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

      await _settleAutoCollapse(tester);
    });
  });

  group('SearchCard reduced motion', () {
    testWidgets('a live card renders every progress state on the first frame',
        (tester) async {
      final segment = SearchCardSegment(
        query: 'q',
        urls: [
          _url('https://a.example'),
          _url('https://b.example', SearchURLState.success),
        ],
      );
      final rebuild =
          await _pumpLiveCard(tester, segment, reducedMotion: true);

      expect(_queryReveal(tester), 1.0);
      expect(_rowOpacity(tester, 'https://a.example'), 1.0);
      expect(_rowOpacity(tester, 'https://b.example'), 1.0);
      expect(_progressRendered(tester), 0.5);
      expect(_progressOpacity(tester), 1.0);
      // The existing static in-progress paths are untouched.
      expect(find.byType(Shimmer), findsNothing);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsWidgets);
      expect(tester.binding.hasScheduledFrame, isFalse);

      segment.urls[0].state = SearchURLState.success;
      segment.isComplete = true;
      segment.resultCount = 7;
      rebuild(() {});
      await tester.pump();

      expect(find.text('7 sources'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(_progressOpacity(tester), 0.0);

      await _settleAutoCollapse(tester);
    });
  });
}
