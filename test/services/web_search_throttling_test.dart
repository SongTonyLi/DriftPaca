import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Services/web_search_service.dart';

/// Verbatim fragments of a real DuckDuckGo response, captured by issuing
/// eight rapid searches against `html.duckduckgo.com`: the first three
/// returned HTTP 200 with ten results each, and every request from the
/// fourth on returned **HTTP 202** — a success status — carrying this
/// interstitial and zero results.
///
/// That 202 is the whole reason this detector exists. The service used to
/// treat any non-200 as "no results" and only special-cased 429, which
/// DuckDuckGo never actually sends, so being throttled was indistinguishable
/// from a genuine miss.
const _challengeBody =
    '<form id="challenge-form" action="//duckduckgo.com/anomaly.js?sv=html'
    '&cc=sre&st=1787500750&gk=d4cd0dabcf4caa22ad92fab40844c786" '
    'method="POST"> <div class="anomaly-modal__mask"> <div '
    'class="anomaly-modal__modal is-ie" data-testid="anomaly-modal"> <div '
    'class="anomaly-modal__title">Unfortunately, bots use DuckDuckGo too.'
    '</div> <div class="anomaly-modal__description">Please complete the '
    'following challenge to confirm this search was made by a human.</div>';

/// Same capture, from one of the healthy HTTP 200 responses.
const _resultsBody =
    '<div class="links_main links_deep result__body"> <h2 '
    'class="result__title"> <a rel="nofollow" class="result__a" '
    'href="https://github.com/probelabs/probe/blob/main/docs/probe-cli/'
    'query.md">probe/docs/probe-cli/query.md at main</a> </h2> <div '
    'class="result__extras"> <div class="result__extras__url">';

void main() {
  group('WebSearchService.isChallengePage', () {
    test('recognises the interstitial DuckDuckGo serves while throttling', () {
      expect(WebSearchService.isChallengePage(_challengeBody), isTrue);
    });

    test('does not fire on an ordinary results page', () {
      expect(WebSearchService.isChallengePage(_resultsBody), isFalse);
    });

    test('does not fire on an empty or unrelated body', () {
      expect(WebSearchService.isChallengePage(''), isFalse);
      expect(
        WebSearchService.isChallengePage('<html><body>Hello</body></html>'),
        isFalse,
      );
    });

    test('matches on structure, not on the user-facing prose', () {
      // The wording is copy — it can be reworded or localised — so each
      // structural marker has to stand on its own.
      for (final marker in [
        '<div class="anomaly-modal__mask">',
        'action="//duckduckgo.com/anomaly.js?sv=html"',
        '<form id="challenge-form">',
      ]) {
        expect(WebSearchService.isChallengePage(marker), isTrue,
            reason: '$marker should be enough on its own');
      }
      expect(
        WebSearchService.isChallengePage(
            'Unfortunately, bots use DuckDuckGo too.'),
        isFalse,
        reason: 'prose alone is too fragile to key on',
      );
    });
  });
}
