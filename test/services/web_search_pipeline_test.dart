import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llamaseek/Models/page_fetch_outcome.dart';
import 'package:llamaseek/Services/web_search_service.dart';

class _FixtureSearch extends WebSearchService {
  final List<WebSearchResult> candidates;
  _FixtureSearch(this.candidates)
      : super(
            pageClientFactory: () => MockClient((request) async => request.url.path == '/blocked'
                ? http.Response('Forbidden', 403, headers: {'content-type': 'text/html'})
                : http.Response('<article>Evidence ${request.url.path}</article>', 200,
                    headers: {'content-type': 'text/html'})));
  @override
  Future<List<WebSearchResult>> search(String query, {int maxResults = 5, bool Function()? isCancelled}) async =>
      candidates.toList();
}

void main() {
  test('deadline keeps discovered snippets even when pages never started', () async {
    final results = await _TimedSearch().searchAndExtract('query');
    expect(results, hasLength(8));
    expect(results.map((r) => r.url), [for (var i = 0; i < 8; i++) 'https://example.org/$i']);
    expect(results.every((r) => r.pageContent == null), isTrue);
    expect(WebSearchService.formatResultsAsContext(results), contains('Search snippet only'));
  });
  test('failed first candidate is replaced without losing citation ordering', () async {
    final candidates = [
      for (final name in ['blocked', 'b', 'c', 'c'])
        WebSearchResult(title: name, snippet: 'Snippet $name', url: 'https://example.org/$name')
    ];
    final attempted = <String, WebSearchResult>{};
    final result = await _FixtureSearch(candidates).searchAndExtract('query', maxResults: 2, onUrlsKnown: (urls) {
      for (final r in urls) {
        attempted[r.url] = r;
      }
    });
    expect(result.map((r) => r.title), ['b', 'c']);
    expect(result.every((r) => r.chunks!.isNotEmpty), isTrue);
    expect(attempted['https://example.org/blocked']!.fetchOutcome!.httpStatus, 403);
    expect(WebSearchService.sourceUrlsFromResults(result, idOffset: 4),
        {5: 'https://example.org/b', 6: 'https://example.org/c'});
  });

  test('all failures retain snippets with explicit provenance', () async {
    final results = await _FixtureSearch([
      WebSearchResult(title: 'Blocked', snippet: 'Useful indexed summary', url: 'https://example.org/blocked'),
    ]).searchAndExtract('query');
    expect(results, hasLength(1));
    expect(results.single.fetchOutcome!.state, PageFetchState.httpError);
    expect(WebSearchService.formatResultsAsContext(results), contains('Search snippet only'));
  });
}

class _TimedSearch extends WebSearchService {
  _TimedSearch() : super(retrievalBudget: const Duration(milliseconds: 10));
  @override
  Future<List<WebSearchResult>> search(String query, {int maxResults = 5, bool Function()? isCancelled}) async => [
        for (var i = 0; i < 12; i++)
          WebSearchResult(title: 'Result $i', snippet: 'Indexed evidence', url: 'https://example.org/$i')
      ];
  @override
  Future<PageFetchOutcome> fetchPage(Uri url,
          {Duration timeout = const Duration(seconds: 8), Future<void>? cancelled}) =>
      Completer<PageFetchOutcome>().future;
}
