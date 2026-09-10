# Search Retrieval Efficiency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce search retrieval delays while making evidence quality and fetch failures explicit.

**Architecture:** Keep DuckDuckGo discovery and the current research loop. Introduce typed fetch outcomes and a bounded candidate scheduler, then propagate evidence provenance into context and measure correctness independently of retrieval success.

**Tech Stack:** Flutter/Dart, existing package:http, flutter_inappwebview, flutter_test.

**Spec:** `docs/search_retrieval_audit_2026-09-09.md`, especially its requirements section.

## Execution status

Implementation is present on local branch `codex/search-retrieval-efficiency`.
Tasks 1–4's production changes and deterministic regressions are implemented.
Task 5's live retrieval run completed five searches before provider throttling;
device and model answer-quality evaluation remain unverified. See
`docs/search_retrieval_comparison_2026-09-09.md` for measurements and verification
limits. Latest `main` was merged into the feature branch for PR integration;
the post-merge relevant regression suite passed 571 tests. No phone installation
has been performed.

Implementation adjustments: use a URL-to-outcome scheduler map to avoid a model/
service import cycle; inject page-client factories so transport ownership is
explicit; keep source order after selecting extracted pages; preserve provenance
in ledger excerpts as well as tool messages. Retain available unattempted snippets
at the deadline, marked as page content not retrieved. No general early-stop rule
based solely on a small number of successful pages was enabled.

## Global Constraints

- Preserve citation ID-to-URL mapping and untrusted-source escaping.
- Preserve CJK query behavior and distinct sub-goal budgets.
- Keep the current provider, signing configuration, app version, and dependencies.
- Maintain partial evidence; identify snippets and unknown failures honestly.
- Treat budgets and quality targets below as proposed initial settings, not measured improvements.
- This is a plan; production changes have not been implemented.

## Task 1: Preserve fetch outcomes and establish the device baseline

**Files:** Create `lib/Models/page_fetch_outcome.dart`; modify `lib/Services/web_search_service.dart`; extend `test/integration/search_retrieval_diagnostic_live_test.dart`; create `test/services/page_fetch_outcome_test.dart`.

**Interface:** `PageFetchOutcome` carries `PageFetchState state`, `Duration elapsed`, nullable `int httpStatus`, nullable `String contentType`, nullable `String text`. `WebSearchResult` gains nullable `PageFetchOutcome fetchOutcome`. Existing constructors and bool progress callbacks remain compatible.

- [ ] Add the outcome model and a failing service test with injected `http.Client`, using `MockClient` from `package:http/testing.dart`.

```dart
enum PageFetchState {
  extracted, httpError, timedOut, networkError, unsupportedType,
  tooLarge, emptyText, cancelled, budgetExpired,
}

// Expose fetchPage(Uri) -> Future<PageFetchOutcome> on WebSearchService
// and inject the existing shared client as the default constructor argument.
test('403 preserves failure reason', () async {
  final service = WebSearchService(client: MockClient((_) async =>
      http.Response('Forbidden', 403, headers: {'content-type': 'text/html'})));
  final outcome = await service.fetchPage(Uri.parse('https://example.org'));
  expect(outcome.state, PageFetchState.httpError);
  expect(outcome.httpStatus, 403);
  expect(outcome.text, isNull);
});
```

- [ ] Run `flutter test test/services/page_fetch_outcome_test.dart`; confirm failure from the missing outcome API.
- [ ] Refactor the existing fetch method into that API. Preserve 200/MIME/size handling; map `TimeoutException` separately from transport exceptions. `_fetchPageContent` assigns both outcome and successful text. Add `fetchTimeout` constructor injection, default eight seconds, so a stalled mock can be checked quickly. Record download and extraction durations separately in diagnostic output; do not log credentials or entire fetched bodies.
- [ ] Add cases for 404, 429, plain text, unsupported PDF, empty HTML, timeout, and thrown `http.ClientException`. Run the new file and `flutter test test/services/web_search_extraction_test.dart test/services/web_search_retrieval_test.dart`.
- [ ] Capture the exact reported query on iPhone in release mode when available. Record discovery route, per-page reason, time to first useful evidence, and time to answer. Compare Wi-Fi/cellular only if the failure varies by network. Do not label a desktop result an iPhone reproduction.
- [ ] Review and commit only the scoped outcome/diagnostic changes: `git commit -m "feat: preserve search fetch outcomes"` after explicitly staging those files.

## Task 2: Bound retrieval and use remaining candidates

**Files:** Create `lib/Services/page_fetch_scheduler.dart`, `test/services/page_fetch_scheduler_test.dart`; modify `lib/Services/web_search_service.dart`.

**Interface:** `PageFetchScheduler.run(List<WebSearchResult> candidates, {required Future<PageFetchOutcome> Function(Uri) fetch, required bool Function() isCancelled}) -> Future<List<WebSearchResult>>`. Constructor parameters: `int concurrency = 3`, `int targetPages = 8`, `Duration budget = const Duration(seconds: 10)`. Return results in discovery order, regardless of completion order.

- [ ] Write a test using controlled Completers: first three candidates start; one 403 releases a slot and the fourth starts; a completed result remains available when the overall budget expires. Assert `maximumActive <= 3`, no starts after cancellation/deadline, and stable result ordering. Use `testWidgets` only for these fake-network timer tests, never the live diagnostic.

```dart
final pending = <Uri, Completer<PageFetchOutcome>>{};
Future<PageFetchOutcome> fetch(Uri uri) =>
    (pending[uri] = Completer<PageFetchOutcome>()).future;
// Complete selected entries in reverse order; returned source order must
// still match candidates, and late completions must not mutate the return.
```

- [ ] Run `flutter test test/services/page_fetch_scheduler_test.dart` and confirm failure before adding scheduler behavior.
- [ ] Replace the first-eight `Future.wait` with three workers consuming the retained candidate list (up to the existing twelve). Stop scheduling at target extracted-page count, exhausted candidates, cancellation, or overall deadline. Keep snippet-only candidates after successful pages when filling remaining result slots; assign citation IDs only after the final selection. Notify the UI when replacement URLs are scheduled. Keep a terminal snapshot so late completions cannot change returned results or emit stale UI callbacks.
- [ ] Give each fetch the lesser of its normal timeout and the remaining scheduler budget. Verify whether the installed HTTP client supports request abort; use a request-scoped client closed at cancellation/deadline if necessary, without closing the shared discovery client. A Future timeout alone is not sufficient transport cleanup.
- [ ] Run scheduler tests plus `flutter test test/services/search_agent_test.dart test/services/web_search_context_test.dart`. Include all-failed, fewer-than-eight, repeated URLs, and cancellation fixtures. Do not raise concurrency until device measurements show benefit without throttling.
- [ ] Re-run the three live queries and compare candidate success and tail latency. Commit the scheduler change separately after reviewing those measurements.

## Task 3: Expose evidence provenance and avoid treating fetch success as answer support

**Files:** Modify `lib/Services/web_search_service.dart`, `lib/Services/search_agent.dart`, `lib/Models/search_event.dart`, `lib/Models/research_ledger.dart`, `lib/Utils/search_thinking_utils.dart`, `lib/Providers/chat_provider.dart`, `lib/Pages/chat_page/chat_page_view_model.dart`, `lib/Widgets/search_detail_dialog.dart`; extend `test/services/web_search_context_test.dart`, `test/models/research_ledger_test.dart`, `test/services/search_agent_test.dart`, `test/regression/g10_search_ui_test.dart`.

**Interfaces:** Keep `SearchURLState`'s existing serialized values. Add optional outcome information to `SearchURLStatus` and its persistence mapping. Extend `recordEvidence` with `bool hasExtractedEvidence = true`; production callers explicitly compute it from returned page content/outcomes. A snippet-only result may count as searched but must not itself clear `outstandingGaps`.

- [ ] Add a failing context test:

```dart
test('snippet-only evidence is identified', () {
  final context = WebSearchService.formatResultsAsContext([
    WebSearchResult(title: 'Result', snippet: 'An indexed summary',
      url: 'https://example.org'),
  ]);
  expect(context, contains('Search snippet only; page content not retrieved'));
  expect(context, contains('id="1"'));
});
```

- [ ] Run `flutter test test/services/web_search_context_test.dart`; confirm failure. Add the provenance sentence inside the source block before escaped snippet content. Add a guideline that snippet-only evidence cannot establish a claim requiring unavailable page details. Preserve IDs and source markup neutralization.
- [ ] Add a ledger test that reopens a gap and records only snippets; the gap must remain. Add an agent test showing that snippets still reach the model and budget exhaustion still terminates. Implement the optional `hasExtractedEvidence` behavior; do not claim extracted text alone proves coverage. Keep the completeness gate responsible for judging the draft.
- [ ] Show concise reasons such as `Access denied (403)`, `Timed out`, `Unsupported format`, or `Page text unavailable`, preserving clickable URLs. Load old persisted records without new fields and keep their status as unknown failure rather than inventing a reason. Round-trip test new optional fields.
- [ ] Run the four listed test files and the existing loophole suite with `flutter test test/services/loopholes test/services/search_loop_loophole_test.dart`. Review source framing, citation mapping, and old-record rendering before committing.

## Task 4: Remove repeated ranking computation without changing selected evidence

**Files:** Modify `lib/Services/web_search_service.dart`; extend `test/services/web_search_context_test.dart`.

**Interface:** Keep `_selectTopChunks(List<String>, String?)` and all returned ordering identical.

- [ ] Pin selection fixtures with score ties, CJK, irrelevant chunks, and the answer in a late chunk. Run `flutter test test/services/web_search_context_test.dart` for the baseline.
- [ ] Compute each score once, then sort indices by the cached score and original index:

```dart
final scores = [for (final chunk in chunks) queryCoverage(query, chunk)];
final ranked = [for (var i = 0; i < chunks.length; i++) i]
  ..sort((a, b) {
    final comparison = scores[b].compareTo(scores[a]);
    return comparison != 0 ? comparison : a.compareTo(b);
  });
```

- [ ] Preserve the existing null-query/short-list early return and final document-order restoration. Re-run the context fixtures and measure ranking duration on a 200,000-character page in release mode. Report the actual savings separately from network latency; commit only this optimization.

## Task 5: Evaluate accuracy and decide whether early completion is justified

**Files:** Extend `test/integration/search_retrieval_diagnostic_live_test.dart`, `test/integration/openrouter_search_loop_live_test.dart`; create `docs/search_retrieval_comparison_2026-09-09.md` when executing.

- [ ] Re-run the three retrieval queries five times with sequential, spaced requests, stopping on rate limits. Add the user's exact query when supplied. Save per-run route/timing/outcome records; do not summarize a single run as p95.
- [ ] Evaluate simple facts, multi-entity comparisons, CJK, unavailable future facts, and conflicting historical/current values. For each answer, record every factual claim, supporting passage and citation ID, date/unit/entity match, unanswered sub-questions, and correctly disclosed uncertainty. Manually audit claim support against passages; citation syntax and keyword presence alone are not accuracy tests.
- [ ] Run the existing live model sweep narrowly using its environment knobs after selecting the user's actual model from available configuration; record model ID and costs. Never infer model latency from the model-free diagnostic.
- [ ] Initial release gates: no citation/persistence/loophole regression; all deterministic cancellation/budget tests pass; no decline in audited supported-claim fraction or sub-question coverage; aim for at least 30% lower median retrieval latency and improved usable-page yield on the paired device benchmark. Five repeats are directional evidence, not robust tail estimates.
- [ ] Only if paired evidence supports it, design a later early-completion policy with query-specific coverage. Do not stop every query after three pages: the four-city query requires four distinct answers and mutually copied sources are not independent corroboration. Provider replacement, browser-based page rendering, structured data adapters, and cross-run caching remain separate decisions requiring evidence from the typed outcomes.
- [ ] Run `flutter analyze` and `flutter test test/services test/models test/providers test/regression` after implementation, investigate failures, and write the comparison report before any completion claim.

## Plan review

The tasks cover measured tail latency, lost failure reasons, unused replacement
candidates, ambiguous snippet provenance, and repeated ranking work. Actual 4/8
reproduction and on-device answer accuracy remain explicit validation work.
No claim of a fixed search engine follows from the live diagnostic exiting 0.
