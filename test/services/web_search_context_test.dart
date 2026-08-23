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
}
