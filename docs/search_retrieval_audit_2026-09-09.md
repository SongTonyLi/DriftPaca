# Search retrieval investigation — 2026-09-09

## Scope and method

User reports four of eight sources unreachable and slow searches. The exact query,
model, and iPhone network are not yet known. Three queries were run once through
the current checkout's `WebSearchService.searchAndExtract`, default eight results.
No model calls, app changes, installation, or paid search services were involved.
Desktop Flutter tests exercise HTTP fallback; they cannot measure the iPhone
WebView discovery path. Numbers below are retrieval time, not answer latency.

Command:

```sh
RUN_SEARCH_DIAGNOSTIC=1 flutter test --reporter expanded test/integration/search_retrieval_diagnostic_live_test.dart
```

The first diagnostic attempt initialized the widget test binding, which substitutes
HTTP responses. Its zero-result measurements were invalid and discarded. Removing
that binding allowed real network requests. The corrected run exited 0 in 20s.
This is a measurement harness, not an assertion that search quality passes.

## Measured results

| Query | Discovery | Total retrieval | Nonempty extracted pages | Snippet-only sources |
|---|---:|---:|---:|---:|
| Jalen Brunson college basketball Villanova | 0.990s | 7.470s | 7/8 | 1 |
| Tokyo Delhi Shanghai Sao Paulo population 2025 | 0.816s | 9.411s | 6/8 | 2 |
| 越南 2025 GDP 世界银行 | 0.577s | 3.460s | 6/8 | 2 |

19/24 pages yielded text (79.2%). This small sample does not reproduce 4/8 or
establish a population success rate. Nonempty text does not establish relevance,
factual correctness, complete article access, or citation support.

In the population query, five extracted pages finished by 1.413s and six by
3.194s, but the final failed CEOWORLD fetch finished at 9.408s. In the Brunson
query, six extracted pages finished by 2.687s, but jalenbrunson.com finished at
7.458s. These demonstrate tail latency, not a claim that those early pages
already answered every part of the questions.

Follow-up GETs used the app's User-Agent and Accept headers, followed redirects,
and had an eight-second limit. These were separate curl requests, not diagnostic
details from the original Dart requests:

| Failed host | Follow-up | Time | Interpretation |
|---|---:|---:|---|
| basketballnetwork.net | 403 | 0.168s | Server refuses this request |
| wionews.com | 403 | 0.183s | Server refuses this request |
| zhuanlan.zhihu.com | 403 | 0.519s | Server refuses this request |
| ceoworld.biz | 200 HTML | 0.264s | Later reachable; original timing is consistent with fetch timeout, not proven |
| vn.mofcom.gov.cn | 200 HTML | 1.596s | Later reachable; original failure cause unknown |

Exact URLs are in the diagnostic output and reproducible queries. Do not treat
403 as evidence a URL is dead or attempt to circumvent access restrictions.

## Findings in current code

1. `web_search_service.dart:640`: `_fetchPageContent` drops non-200 responses,
   unsupported MIME, oversized bodies, empty extraction, and all exceptions into
   the same absent `pageContent`. No original failure reason survives.
2. `web_search_service.dart:219`: candidates beyond the first eight are discarded
   before fetching. Overfetching twelve discovery hits does not replace failed
   page fetches. `Future.wait` waits for all selected fetches with three slots
   and eight-second individual timeouts. No overall retrieval deadline exists.
3. `web_search_service.dart:188,333`: snippets survive failed fetches and receive
   normal citation IDs, without an explicit snippet-only marker in model context.
   `search_agent.dart:1238` records evidence whenever results are nonempty;
   `research_ledger.dart:527` clears outstanding gaps on that event. The coverage
   gate still exists, so this is a weak evidence signal, not proof of wrong answers.
4. `_fetchPageContent` accepts any nonempty extracted HTML text as success. A chart
   shell or access interstitial can satisfy that check. The World Bank indicator
   pages returned only 650/996 characters in this sample; this merits content
   inspection, and is not proof that either page is incorrect.
5. `_selectTopChunks` recomputes trigram coverage inside sort comparisons. Scoring
   once per chunk is an output-preserving optimization; CPU cost has not yet been
   measured on iPhone. Retrieval failures and tail latency have stronger evidence.
6. Search discovery uses WebView first (12s timer), then HTTP (10s timeout with one
   retry and 2s delay for selected errors). Model goal derivation, research turns,
   sequential tool searches, and a coverage gate add separate latency. The older
   search-loop audit predates its fixes; its timings are historical, not a fresh
   baseline for this checkout.

## Requirements for the proposed work

- Preserve citation ID-to-URL mapping and untrusted-source escaping.
- Preserve CJK query behavior and distinct sub-goal budgets.
- Keep the current provider, signing configuration, app version, and dependencies.
- Maintain partial evidence; identify snippets and unknown failures honestly.
- Bound retrieval work, replace failed candidates within the budget, and measure
  evidence quality before enabling early completion for all searches.
- Compare the same queries and device/network before and after; measure supported
  claims and sub-question coverage, not merely nonempty text or valid citations.
- First investigate the user's exact 4/8 query when available; do not infer its
  failure causes from unrelated queries.
