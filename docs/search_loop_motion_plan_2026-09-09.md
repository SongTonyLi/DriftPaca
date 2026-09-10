# Research Loop Motion Plan — 2026-09-09

Design plan for making the agentic search loop UI (the research bubble
rendered by `_AssistantBubble` when a tool-enabled chat runs `SearchAgent`)
feel alive while it works. Today the bubble is static for most of a run and
every phase change is a cut; this document says why, what should move, and
how to ship it in four independent pull requests.

An animated before/after prototype of the proposed bubble accompanies this
plan (published as a claude.ai artifact from the same session). The
prototype is driven by the same events the app already emits plus the one
new phase hook described below.

## Method

Traced one native-tools research run end to end:

- `SearchAgent.run` → `SearchAgentListener` → `ChatProvider._streamWithSearchAgent`
  → `ChatPageViewModel._beginWebSearch` callbacks → `_searchSegments`
  → `ChatListView` (index-0 bubble) → `_AssistantBubble._buildMessageContent`
  → `SearchCard`, `ThinkBlockWidget`, `_ResearchLedgerPanel`, `ClarificationCard`.
- Timed each phase against the kimi-k3 multihop row of
  `docs/search_loop_audit_2026-09-08_runs.txt` (47 s, 2 searches).
- Checked every existing animation against the reduced-motion guarantees in
  `docs/ui_animation_audit_2026-07-19.md`; the plan keeps them.

## Diagnosis

| # | Finding | Where | Effect on screen |
|---|---|---|---|
| 1 | **First-turn thinking is hidden.** `_displayThinking` returns `''` whenever `searchSegments` is non-empty and the thinking has no `searchThinkingSeparator`. The ledger panel is published before the goal call, so the segments list is never empty during turn 1, and every `onThinking` delta of that turn is dropped. | `chat_bubble.dart` `_displayThinking`; `chat_provider.dart` `onThinking` | 10–30 s of a static panel on a reasoning model, then a collapsed "Thought" row appears all at once. |
| 2 | **Goal derivation and the coverage gate are silent.** Both are whole model calls with no listener hook. The ledger shows the raw question with "Next — drafting the answer" while deriving (wrong). During the gate the draft sits still; a rejected draft is cleared to blank by `onResetContent` with no transition. | `search_agent.dart` `_deriveGoal`, `assessCoverage`; `chat_bubble.dart` `_NextStepLine` | 6 s + 4 s of the run with nothing but the llama moving; the draft "answer vanishes" cut. |
| 3 | **Each turn's thinking is swapped, not finished.** `onSearchThinking` appends a *new* `ThinkingSegment` (rendered `isComplete: true`) and the live block's text is reset. The live "Thinking… 8s" widget is disposed; the stopwatch, pulse and collapse animation are lost, and persisted rows never show a duration. | `chat_page_view_model.dart` `onSearchThinking`; `chat_bubble_think_block.dart` | Visible jump at the end of every turn; "Thought" rows with no time. |
| 4 | **The ledger re-renders instead of transitioning.** A sub-goal flipping open → searched is an instant re-layout inside one `AnimatedSize`; the bullet, chip and "Next —" line change without motion. | `chat_bubble.dart` `_ResearchLedgerPanel`, `_LedgerEntryRow`, `_NextStepLine` | The moment the run makes progress is the least visible moment. |
| 5 | **Search cards animate arrival, not progress.** Rows fade in as one block; the only progress signal is per-row spinner → check. No fetched/total signal, no query reveal, static completion icon. | `search_card.dart` `_UrlRow`, `_StatusGlyph`, `_buildIcon` | Fetch phase reads as "waiting" rather than "working". |
| 6 | **Skeleton and composer stop helping too early.** `isAwaitingReply` is gated on `searchSegments.isEmpty`, so the shimmer skeleton disappears when the ledger lands; the search-button pulse carries no phase meaning. | `chat_page.dart` | After the first 500 ms the llama is the only continuous signal on screen. |

Phase coverage on the 47 s reference run:

| Phase | Duration | Today | Proposed |
|---|---|---|---|
| Goal derivation | 6 s | nothing moves | live |
| Turn 1 thinking | 9 s | nothing moves (hidden) | live tokens |
| Search 1 + read | 6 s | live (row glyphs) | live + progress |
| Turn 2 thinking | 8 s | partial (text streams, then swap) | live tokens |
| Search 2 + read | 6 s | live | live + progress |
| Draft answer | 8 s | partial (text streams, no phase) | live |
| Coverage gate | 4 s | nothing moves | live |

Today: 19 s with no signal, 16 s with a partial one. Proposed: 0 s.

## Design principles

1. **Always something alive, and always true.** One activity strip names
   the current phase, driven by real agent state, never by a timer guess.
2. **Transitions, not swaps.** A widget that changes state keeps its
   identity (keyed) so its animation controllers carry through.
3. **Motion tracks progress.** Fetched-of-total, tokens as they arrive,
   sub-goals ticking off. Decorative loops are limited to the phase glyph.
4. **Cheap.** Tickers only on live segments; plain `Text` for thinking so
   token reveal never re-parses markdown; keep the 32 ms notify throttle.
5. **Reduced motion resolves to the final state** through the existing
   `motionDuration` / `animationsDisabled` helpers, with no continuous frames.

## Motion spec

| Surface | Trigger | Motion | Timing | Reduced motion |
|---|---|---|---|---|
| **Activity strip** (new `ResearchActivityStrip`) | `onPhase` | Pill under the segments while the run is live: phase glyph with its own loop (orbit / sparkle / sweep / page-flip / tick / pen), label cross-fades on change, elapsed-in-phase counter | label 240 ms ease-out; glyph loops 0.7–1.6 s | static glyph, label swaps, counter ticks |
| **Think block** (live `ThinkingSegment`) | `onThinking` deltas appended into one mutable segment | Tokens fade in on arrival, sparkle pulses, "Thinking… Ns" ticks; turn end keeps the same widget: label → "Thought for N s", then collapses | token fade 160 ms; collapse 400 ms easeOutCubic after 300 ms | text in full, instant collapse |
| **Ledger objective** | `onLedgerUpdate` before/after `deriveGoal` | Raw question shimmers while deriving, cross-fades to the derived statement; next-step line reads "Framing the research goal…" | shimmer 1.6 s; cross-fade 260 ms | plain text |
| **Ledger rows** | entry open → searched | Bullet scales into a tick (same `AnimatedSwitcher` idiom as `_StatusGlyph`), chip pops, row moves to Findings; "Next —" cross-fades | glyph 280 ms easeOutBack; move 220 ms | instant |
| **Search card** | `onSearchStart`, `onUrlsKnown`, `onUrlFetched`, `onSearchComplete` | Query clip-reveals; rows stagger in; 2 px progress line fills fetched/total; header check pops; source count counts up; existing 500 ms collapse | reveal 320 ms; stagger 40 ms/row capped at 8; progress 260 ms/step | rows at once, static hourglass (existing) |
| **Draft answer** | gate rejection (`onResetContent`) | Draft fades and shrinks out; strip reads "Answer left a gap — searching again" | fade 220 ms, size 300 ms | instant clear |
| **Composer** | same `onPhase` | Search-button pulse only while searching/reading; hint text mirrors the strip | existing pulse | static |

## Plumbing

### `SearchAgentListener.onPhase(ResearchPhase)`

```dart
enum ResearchPhase {
  framingGoal, awaitingClarification, thinking, searching, reading,
  updatingLedger, checkingCoverage, drafting, done,
}
```

Fired at seams that already exist in `SearchAgent`:

- `framingGoal` before `_deriveGoal`; `awaitingClarification` inside `_clarify`.
- `thinking` on a turn's first `onThinking` delta (in `_ingestChunk`).
- `searching` when `_executeToolCalls` issues a query; `reading` when the
  search callback's `onUrlsKnown` fires; `updatingLedger` after
  `recordEvidence`.
- `checkingCoverage` before `assessCoverage`; `drafting` alongside
  `onAnswerStart`; `done` alongside `onResearchDone`.

`ChatPageViewModel` exposes `researchPhase` and a phase stopwatch. The
strip, the composer hint and the search-button pulse read that instead of
the coarse `isSearching || isStreaming` pair.

### `ThinkingSegment` becomes live-then-complete

- Add `bool isComplete` and `int? elapsedSeconds`; persist both.
- `onThinking` appends into the open (incomplete) segment in place, creating
  one if none is open; `onSearchThinking` marks it complete with its
  elapsed time instead of appending a second segment.
- `_buildSearchSegmentsFrom` renders it with `ValueKey(identityHashCode(segment))`
  so the `ThinkBlockWidget` State (stopwatch, pulse, expand controller)
  survives the transition.
- `_displayThinking` stops hiding the first turn; live model thinking no
  longer needs the merged-string separator to be visible. The persisted
  `thinking` blob keeps the same encoding.

### `ThinkBlockWidget` owns its token reveal

- New `TokenReveal` text widget: a single ticker that advances a reveal
  cursor at the observed arrival rate (smoothing bursty 32 ms chunks), plain
  `Text`, so it runs at 60 fps without touching the bubble's 30 fps markdown
  throttle. Reused by the strip label if useful.
- Completed rows read "Thought for N s" from the stored elapsed value.

### Performance budget

- `RepaintBoundary` per search card and think block.
- Replace the ledger body's whole-panel `AnimatedSize` with per-row
  transitions; keep `AnimatedSize` only for expand/collapse.
- Only live segments hold tickers; everything else settles and releases
  (same discipline `StreamingLlama` already follows).
- Strip counters and think stopwatches update from their own 250 ms / 1 s
  timers, not from `notifyListeners`.

## Delivery

| PR | Scope | Tests |
|---|---|---|
| **1 · plumbing** | `onPhase` in the agent; `researchPhase` in the view model; mutable live `ThinkingSegment`; fix hidden first-turn thinking | `search_agent_test` (phase order for single / multihop / gate-rejected / cancelled runs); `chat_page_view_model_test` (segment appended in place, completed once); `g05_bubble_stream_test` (turn-1 thinking visible) |
| **2 · strip + think** | `ResearchActivityStrip` with glyph set; `ThinkBlockWidget` token reveal, keyed identity, duration on persisted rows | new `research_activity_strip_test` (label per phase, reduced motion static, ticker released on `done`); `g10_search_ui_test` (same State across complete) |
| **3 · search card** | query reveal, staggered rows, progress line, completion pop and count-up | `g10_search_ui_test` additions; stagger cap; hourglass path unchanged |
| **4 · ledger + draft** | row tick transition, chip pop, next-step cross-fade, deriving shimmer; draft fade-out on gate rejection | `g10` ledger tests; `docs/ui_animation_audit` addendum |

Each PR is shippable alone; PR 1 already removes the worst dead phase
(hidden first-turn thinking) with no visual redesign.

## Out of scope

- No change to how the loop decides to search or stop.
- No new persisted fields beyond `isComplete` / `elapsedSeconds` on
  thinking segments.
- The legacy `WEBSEARCH:` (no native tools) path keeps its current rendering.
