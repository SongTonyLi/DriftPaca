# Search retrieval implementation and verification

## Implemented

- Page fetching retains typed HTTP, timeout, network, MIME, size, empty-text,
  cancellation, and batch-deadline outcomes. Each page owns its transport;
  timeout/cancellation closes it without affecting other requests. Body size is
  checked while streaming, not just after allocating the full response.
- Three fetch slots share a ten-second page-batch budget. Failed candidates are
  replaced from the discovery pool, targeting eight extracted pages. Final source
  ordering follows discovery order, independent of completion order. Available
  snippets survive even if the deadline prevents their page request starting.
- Model context and saved UI previews identify snippet-only evidence. The ledger
  preserves this provenance after context compaction, prefers retrieved excerpts,
  upgrades a prior snippet when page text arrives, and does not clear a reopened
  coverage gap on snippets alone.
- UI rows preserve specific failure reasons, including cancellation, across
  incremental updates and persistence. Replaced failed attempts remain inspectable.
- Chunk-ranking scores are calculated once per chunk instead of inside each sort
  comparison. Selection and tie order are unchanged.

The ten-second bound applies to page retrieval after discovery. WebView search,
HTTP discovery retries, model generation, and coverage assessment have separate
budgets. This change does not promise a ten-second complete answer.

## Live retrieval measurements

Same desktop HTTP-fallback diagnostic and queries as the investigation. Timings
include discovery and extraction, but no model. These are independent live runs,
not a controlled before/after experiment; network and returned URLs varied.

| Query | Original | After, run 1 | After, run 2 |
|---|---|---|---|
| Brunson college | 7.470s, 7/8 extracted | 7.377s, 8/8 | 2.963s, 8/8 |
| Four cities' populations | 9.411s, 6/8 | 2.442s, 8/8 | 2.646s, 8/8 |
| Vietnam GDP, Chinese | 3.460s, 6/8 | 9.515s, 7/8 | Search provider throttled |

The five completed searches retrieved text for 39/40 final sources. Backfill was
observed: these searches attempted 9, 9, 10, 9, and 9 pages respectively. The
Chinese query was slower on its one completed rerun, so a consistent speedup or
the proposed 30% median device-latency target has not been established.

Five repetitions per query were requested. DuckDuckGo rate-limited search six;
the diagnostic stopped without further searches. Raw records are in the local,
ignored `build/search_retrieval_diagnostic.json`. No paid model sweep was run.

## Verification

- Final search/services, models, providers, regression UI and view-model suite:
  538 tests passed after all source-preview/cancellation changes.
- Final focused UI/persistence suite: 95 tests passed, including regression tests
  for snippet preview labeling and cancellation without a completion callback.
- Static analysis of all changed production files and new diagnostic/test files:
  no issues. Full-project analysis reports 177 warnings/info findings outside this
  clean targeted check; it is not a clean project-wide analyzer run.
- Independent review identified snippet provenance, discarded unattempted snippets,
  timeout classification, and cancellation persistence issues. All were addressed
  and re-reviewed; no remaining findings in the reviewed changes.
- Broader offline discovery also encounters unrelated database-options and color
  palette assertion failures, plus a server-settings migration test that does not
  finish. These tests and their database/palette/settings implementations were not
  changed. The full repository suite is therefore not claimed green. A legacy live
  Ollama endpoint test also lives outside `test/integration`; it is not an offline
  verification target. The broad run's JSON is in
  `build/offline_search_change_tests.json`.

The user's exact 4/8 query and model were not supplied. iPhone release-mode timing,
paired supported-claim audits, and end-to-end model accuracy remain unverified.
Nonempty page text is not proof that a source answers the question. No provider,
dependency, app version, bundle identifier, or signing configuration was changed.
The app has not been installed on the phone as part of this implementation.
