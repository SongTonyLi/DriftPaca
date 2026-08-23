import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Services/web_search_service.dart';

List<WebSearchResult> twoResults() => [
      WebSearchResult(
        title: 'Alpha',
        snippet: 'alpha snippet',
        url: 'https://example.com/a',
        pageContent: 'Alpha page',
      ),
      WebSearchResult(
        title: 'Beta',
        snippet: 'beta snippet',
        url: 'https://example.com/b',
        pageContent: 'Beta page',
      ),
    ];

void main() {
  test('idOffset 0 starts source ids at 1 and 2', () {
    final ctx = WebSearchService.formatResultsAsContext(twoResults());
    expect(ctx, contains('<source id="1" name="https://example.com/a"'));
    expect(ctx, contains('<source id="2" name="https://example.com/b"'));
    expect(ctx, isNot(contains('<source id="0"')));
  });

  test('idOffset 8 starts source ids at 9 and 10', () {
    final ctx = WebSearchService.formatResultsAsContext(
      twoResults(),
      idOffset: 8,
    );
    expect(ctx, contains('<source id="9" name="https://example.com/a"'));
    expect(ctx, contains('<source id="10" name="https://example.com/b"'));
    expect(ctx, isNot(contains('<source id="1"')));
  });

  test('does not force an immediate answer', () {
    final ctx = WebSearchService.formatResultsAsContext(twoResults());
    expect(
      ctx,
      isNot(contains('Respond to the user query using the provided sources')),
    );
    expect(ctx.toLowerCase(), contains('untrusted'));
    expect(ctx, contains('web_search'));
  });

  test('sourceUrlsFromResults uses the same offset', () {
    expect(
      WebSearchService.sourceUrlsFromResults(twoResults()),
      {1: 'https://example.com/a', 2: 'https://example.com/b'},
    );
    expect(
      WebSearchService.sourceUrlsFromResults(twoResults(), idOffset: 8),
      {9: 'https://example.com/a', 10: 'https://example.com/b'},
    );
  });

  group('deprioritizeVisited', () {
    test('moves an already-visited URL after the not-yet-visited ones, dropping nothing', () {
      final reordered = WebSearchService.deprioritizeVisited(
          twoResults(), {'https://example.com/a'});
      expect(reordered.map((r) => r.url).toList(),
          ['https://example.com/b', 'https://example.com/a']);
    });

    test('preserves relative order within each group', () {
      final results = [
        WebSearchResult(title: 'A', snippet: '', url: 'https://example.com/1'),
        WebSearchResult(title: 'B', snippet: '', url: 'https://example.com/2'),
        WebSearchResult(title: 'C', snippet: '', url: 'https://example.com/3'),
      ];
      final reordered =
          WebSearchService.deprioritizeVisited(results, {'https://example.com/2'});
      expect(reordered.map((r) => r.url).toList(), [
        'https://example.com/1',
        'https://example.com/3',
        'https://example.com/2',
      ]);
    });

    test('is a no-op for an empty set', () {
      final results = twoResults();
      final reordered = WebSearchService.deprioritizeVisited(results, {});
      expect(reordered.map((r) => r.url).toList(),
          results.map((r) => r.url).toList());
    });

    // The actual regression: a refined query's top hits often legitimately
    // overlap with a broader round's (the same authoritative domain answers
    // several sub-goals). Dropping those to zero starved the round of
    // results it actually has and made it look unproductive — see
    // SearchAgent's madeProgress/anyNonEmptyResults convergence signal.
    test('never drops a result even when every URL is already visited', () {
      final results = twoResults();
      final reordered = WebSearchService.deprioritizeVisited(
        results,
        {'https://example.com/a', 'https://example.com/b'},
      );
      expect(reordered.length, 2);
      expect(reordered.map((r) => r.url).toSet(),
          results.map((r) => r.url).toSet());
    });
  });

  test('a page longer than 4000 but under the raised ceiling is no longer truncated at 4000', () {
    final longText = 'x' * 6000;
    final truncated = WebSearchService.truncatePageContent(longText);
    expect(truncated.length, 6000);
  });

  test('a page much longer than the ceiling is still truncated', () {
    final veryLongText = 'y' * 50000;
    final truncated = WebSearchService.truncatePageContent(veryLongText);
    expect(truncated.length, lessThan(50000));
  });

  test('formatResultsAsContext prefers the query-relevant chunk over the positionally-first one', () {
    // Deliberately rare letter sequences in the query so the "irrelevant"
    // chunks can't accidentally share a trigram with it the way ordinary
    // English words often do (e.g. "-ing"/"-tion").
    final result = WebSearchResult(
      title: 'Result',
      snippet: 'snippet',
      url: 'https://example.com/x',
      chunks: [
        'A general overview of the topic with background history.',
        'Unrelated details about something else entirely, filler text.',
        'The reading of xqzv wbjk was confirmed by three independent labs.',
      ],
    );
    final ctx = WebSearchService.formatResultsAsContext(
      [result],
      query: 'xqzv wbjk',
    );
    expect(
        ctx,
        contains(
            'The reading of xqzv wbjk was confirmed by three independent labs.'));
    expect(ctx,
        isNot(contains('Unrelated details about something else entirely, filler text.')));
  });

  test('formatResultsAsContext without a query behaves exactly as before (positional first 2 chunks)', () {
    final result = WebSearchResult(
      title: 'Result',
      snippet: 'snippet',
      url: 'https://example.com/x',
      chunks: ['first chunk', 'second chunk', 'third chunk most relevant'],
    );
    final ctx = WebSearchService.formatResultsAsContext([result]);
    expect(ctx, contains('first chunk'));
    expect(ctx, contains('second chunk'));
    expect(ctx, isNot(contains('third chunk most relevant')));
  });
}
