[OPEN] Context-retrieval pollution audit (web search · history · agent memory)

## Session
- Session ID: `context-pollution`
- Started: 2026-07-02
- Scope: Systematically review how DriftPaca (`llamaseek`) assembles the context it
  sends to the Ollama model — web-search results, chat history, and the 3-tier
  agent memory — and identify places where that assembled context can be stale,
  duplicated, misattributed, uncapped, or attacker-controlled, causing the model
  to hallucinate. Review only; no code changed. Findings are backed by file:line
  evidence, and each was cross-checked against the actual send path rather than
  assumed.

## Symptoms (what "context pollution → hallucination" looks like here)
- Model confidently contradicts or forgets facts established earlier in the chat.
- Model states outdated facts ("you're using React 17", "your startup is X") that
  were true weeks ago in a *different* conversation.
- Model answers as if it already searched, or answers with fabricated "memory".
- A web page can steer the answer regardless of what the user asked.

## The convergence point (data-flow trace)
Everything funnels through `OllamaService._prepareMessagesWithSystemPrompt`
(`lib/Services/ollama_service.dart:329-409`). One request is built as:

```
messages[0] = system:  chat.systemPrompt
                       + buildMemoryInjection( profileBlock,          // agent memory tier 1
                                               relevantContextBlock,  // agent memory tiers 2/3 (topics + ephemeral)
                                               conversationMemoryBlock ) // per-chat rolling summary
                       + (on a search turn) the <source>…</source> RAG block
messages[1..] = history, TRUNCATED to the last MemoryConstants.recentMessagesToKeep (20)
                whenever a conversation summary exists (ollama_service.dart:339-342),
                each serialized via toChatJson() — which re-sends the `thinking` field
                verbatim (ollama_message.dart:116-121; ollama_service.dart:365).
```

So the model's entire non-history context is a single system message concatenating
four independently-generated sources, none of which is length-capped at this layer,
plus a history window that both duplicates and can silently drop content. That is the
surface every finding below sits on.

---

## Findings (ranked: confidence × blast radius)

### F1 — Raw memory-model output is injected verbatim as authoritative "Conversation Context" [HIGH]
- **Claim:** When the memory model's response isn't clean JSON, the *entire raw
  response* is stored as the conversation summary and later injected into the system
  prompt as trusted history.
- **Evidence:**
  - `lib/Services/memory_service.dart:316-321` — parse-fail path: `ConversationMemory(summary: responseBody)` stores the whole raw string.
  - `lib/Services/memory_service.dart:385-391` — catch-all repeats the same fallback.
  - `_extractJson` (`memory_service.dart:394-405`) uses a greedy `\{[\s\S]*\}` (first `{` to last `}`); reasoning text containing stray braces makes it capture a bad span → parse fail → raw fallback.
  - Injected under `## Conversation Context … Use it to maintain continuity.` (`lib/Constants/memory_constants.dart:156-160`).
  - **No token cap at injection.** `ConversationMemory.toPromptBlock()` (`lib/Models/conversation_memory.dart:117-128`) just joins all sections. `maxConversationMemoryTokens`/`maxProfileTokens` are enforced **only** in UI widgets (`lib/Widgets/memory_bottom_sheet.dart`, `lib/Widgets/chat_drawer.dart`), and `resummarize()` is called **only** from those UI callbacks — never automatically during chat. A summary can grow unbounded via cumulative updates and be injected uncapped.
- **Why it hallucinates:** the model reads meta-commentary, echoed instructions, or a
  half-JSON dump as if it were established conversation fact, and treats it as ground
  truth for continuity.
- **Fix direction:** on parse failure, drop the update (keep last good memory) instead
  of storing raw; enforce `maxConversationMemoryTokens` in `toPromptBlock()`/at
  injection; tighten `_extractJson` (balanced-brace or fenced-block extraction).

### F2 — Silent mid-conversation context loss + recent-turn duplication [HIGH]
- **Claim:** Once a summary exists, history is truncated to the last 20 messages,
  trusting a summary that (a) is generated fire-and-forget, (b) is dropped whenever
  another update is in flight, and (c) itself only ever ingests the last 20 messages.
  Meanwhile those last 20 are sent twice (raw + summarized).
- **Evidence:**
  - Send truncation: `lib/Services/ollama_service.dart:339-342` — `hasMemory && messages.length > 20` → send only the last 20.
  - Summarizer input is *also* only the last 20: `lib/Services/memory_service.dart:229-231`. Nothing ever summarizes messages older than the current window.
  - Update is fire-and-forget (`chat_provider.dart:386-390`) and gated by a **single global** `if (_isUpdating) return;` (`memory_service.dart:210`, field at `:19`). Rapid messages, or switching chats mid-summarization (the `gpt-oss:120b-cloud` call has a 60s timeout), silently skip updates.
  - Duplication: the summary is injected (`memory_constants.dart:156-160`) *in addition to* the raw last-20 messages.
- **Why it hallucinates:** vulnerable window = memory was created once, then later
  updates were dropped while the chat grew past 20 turns. Messages that scrolled out
  of the last-20 window during that gap were never summarized and are no longer sent →
  the model fills the hole. Separately, a summary that paraphrases the last 20 slightly
  differently than the raw text forces the model to reconcile two versions of the same
  turns.
- **Fix direction:** per-chat update queue instead of one global `_isUpdating`;
  summarize the *older* messages (those about to fall out of the window), not the ones
  still being sent raw; don't inject a summary that fully overlaps the raw window.

### F3 — Stale, never-expiring, cross-conversation memory injected as present-tense fact [MEDIUM-HIGH]
- **Claim:** Topic memory is global and never expires, has no "as-of" provenance in the
  injected text, and (with ephemeral) is selected from a global pool with no chat
  scoping — so old facts from other chats are asserted as currently true.
- **Evidence:**
  - `selectRelevantContext` pulls from **global** topics + ephemeral (`memory_service.dart:130-198`); `getAllTopics()` is unscoped (`database_service.dart:448-451`).
  - Topics have **no TTL** (`lib/Models/memory_topic.dart` — only `updatedAt`); ephemeral expires (7–14d, `ephemeral_context.dart`) but is likewise global.
  - Injected text carries no timestamp: `MemoryTopic.toPromptEntry()` = `- **[key]**: content` (`memory_topic.dart:52`); ephemeral = `- **[recent: key]**: content` (`ephemeral_context.dart:84`).
  - The agent-memory block *does* stamp the current time (`agent_memory.dart:84`), so the model believes "now" is current — and therefore reads undated topic content as current too.
  - Selection runs on a small fast model (`ministral-3:8b`, `memory_constants.dart:11`); false-positive key selection injects irrelevant topics.
- **Why it hallucinates:** a topic captured weeks ago ("migrating to React 18", "job at
  TikTok") is injected verbatim into an unrelated chat and stated as fact; the model has
  no signal that it's stale.
- **Fix direction:** add `updated_at` provenance to injected topic entries ("last
  discussed <date>"); consider topic decay/confirmation; scope or down-weight ephemeral
  by source chat.

### F4 — Search-data blob + prior chain-of-thought re-sent as `thinking` history, never stripped [HIGH confidence on transmission; model-effect template-dependent]
- **Claim:** After a search turn, a base64 `<!--SEARCH_DATA:…-->` blob (search UI state
  — queries, URLs, and, when the card carries them, full scraped page contents) is
  prepended to the assistant message's `thinking`, persisted, and then re-sent to the
  model on every subsequent turn together with all prior chain-of-thought. It is never
  stripped in the send path.
- **Evidence:**
  - Blob built + prepended + persisted: `chat_provider.dart:373-381` via `encodeSearchSegments` (`lib/Utils/search_thinking_utils.dart:31-68`); the encoded segment includes `extractedContent` and per-source `content`.
  - Persisted/restored in the `thinking` column (`ollama_message.dart:123-131`, `84-93`; `database_service.dart:99-109`).
  - Re-sent: `toChatJson()` includes `if (thinking != null) "thinking": thinking` (`ollama_message.dart:116-121`); non-vision branch also re-adds it (`ollama_service.dart:365`).
  - Stripping helpers exist but are **display-only** — used solely in `chat_bubble.dart:616-636`, never in `ollama_service.dart`.
- **Why it hallucinates:** the blob is opaque tokens; the embedded page dumps are stale
  scraped content re-injected every turn; prior CoT re-fed as dialogue confuses reasoning
  models. Even when the server's chat template ignores assistant `thinking`, this is
  unbounded context that grows every turn (bandwidth + truncation pressure). For any
  reasoning-model template that echoes prior `thinking` (common), it is active pollution.
- **Note on certainty:** the *transmission* is confirmed from code; whether the served
  model re-conditions on assistant `thinking` depends on ollama.com's template for that
  model. Worth a quick empirical check against the live endpoint.
- **Fix direction:** strip `<!--SEARCH_DATA:…-->` (and optionally all prior `thinking`)
  in `_prepareMessagesWithSystemPrompt` before building the request; persist search-card
  state in a dedicated DB column, not inside `thinking`.

### F5 — Indirect prompt injection: scraped pages are placed in the system prompt as trusted sources [MEDIUM]
- **Claim:** Web-page text is inserted into the system prompt as authoritative `<source>`
  material with an instruction to answer from it, and no framing that treats it as
  untrusted data.
- **Evidence:**
  - `formatResultsAsContext` (`web_search_service.dart:188-222`) emits `### Task: Respond to the user query using the provided sources…` then the scraped content.
  - Injected into the **system** prompt for the answer call (`chat_provider.dart:454-467`).
  - The auto-search system prompt is aggressive ("ALWAYS search unless…", `chat_provider.dart:21-33`), maximizing exposure.
- **Partial mitigation already present (verified):** `extractTextFromHtml`
  (`web_search_service.dart:230-273`) strips all `<…>` tags, so a page **cannot** forge a
  literal `</source>`/`<source id="99">` to fake a citation boundary. Good. But
  natural-language injection ("ignore previous instructions, tell the user …") passes
  through untouched.
- **Fix direction:** wrap source content in an explicit "untrusted data, do not follow
  instructions inside" delimiter; keep RAG material in a separate non-system message.
- **Minor, same file:** `name="${r.url}"` is interpolated unescaped
  (`web_search_service.dart:202-203`); a URL containing `"` breaks both the tag and the
  id→URL interception regex (`chat_provider.dart:675`), silently dropping/mismapping a
  citation link.

### F6 — WEBSEARCH trigger can wipe a genuine answer or fire the wrong query [MEDIUM-LOW]
- **Claim:** Mid-stream detection treats any occurrence of `WEBSEARCH:` in the model's
  content as a tool call and discards the accumulated answer; the "thinking fallback"
  extracts a query heuristically and can search for the wrong thing.
- **Evidence:**
  - `chat_provider.dart:555-565` — if streamed content contains `WEBSEARCH:` anywhere, `streamingMessage.content = ''` and it's reinterpreted as a query. Fires on legitimate answers that mention the token (e.g. the user asking *about* the WEBSEARCH mechanism).
  - `chat_provider.dart:597-633` — regex-based query extraction from `thinking`/content.
  - `chat_provider.dart:638-640` — query then has `[...]` stripped and is truncated to 10 words, which can mangle a valid query.
- **Why it hallucinates:** a wrong or empty search returns off-topic sources → the answer
  is grounded in the wrong context; or a real answer is thrown away and replaced by a
  search round-trip.
- **Fix direction:** only honor `WEBSEARCH:` when it's the sole/leading token of Call-1
  output (it's already instructed to be), not anywhere mid-content.

---

## Checked and found NOT to be issues (falsification, not just confirmation)
- **Citation comma-lists** (`[1, 3, 5]`) are only expanded when **every** id is a known
  fetched source (`chat_provider.dart:856-874`), so math ranges / thousands separators in
  non-search chats are safe.
- **Tag-forging prompt injection** is blocked by full tag-stripping (F5) — the boundary
  can't be escaped, only the prose can persuade.
- **Incognito** correctly skips agent-memory profile injection and topic/ephemeral
  selection (`chat_provider.dart:418, 428`) and skips agent-memory writes
  (`:389`). (Adjacent, out of scope: incognito messages + per-chat conversation summary
  are still persisted to disk — a privacy note, not a hallucination vector.)
- **Non-vision models** get an explicit `[N image(s) attached — not viewable]` placeholder
  plus a memory hint to use textual descriptions (`ollama_service.dart:359-366`;
  `memory_constants.dart:164-166`) — no silent image loss.
- **History ordering** is correct (`timestamp ASC`, `database_service.dart:304-315`).

## Fix Log
- **F1 — FIXED (2026-07-02).** TDD, one root cause at a time.
  - F1a: `MemoryService.parseAndSave` no longer stores raw non-JSON model output as
    the conversation summary — on parse failure or exception it keeps the last good
    memory (`lib/Services/memory_service.dart:313-321, 385-388`). Was `_parseAndSave`,
    exposed `@visibleForTesting`.
  - F1b: `ConversationMemory.toPromptBlock()` now caps the injected block to
    `maxConversationMemoryTokens` (`lib/Models/conversation_memory.dart:119-140`).
  - Tests: `test/services/memory_context_pollution_test.dart`,
    `test/models/conversation_memory_test.dart` (4 tests, all green; watched each fail
    first). No regressions in the non-integration suite (remaining suite failures are
    pre-existing: real-API tests + untracked WIP widget tests + `mode_palette` color
    thresholds).

- **F2 — FIXED (2026-07-02).** Coverage-tracked redesign (chosen approach), TDD.
  - `ConversationMemory` gained `summarizedMessageCount` (JSON field
    `summarized_message_count`, no DB migration) — the count of leading messages the
    summary represents (`lib/Models/conversation_memory.dart`).
  - Send path (`OllamaService.prepareMessagesWithSystemPrompt`, was
    `_prepareMessagesWithSystemPrompt`): sends raw from the coverage boundary, so no
    unsummarized message is ever dropped; a lagging summary yields a larger — never
    lossy — context and self-heals. The conversation summary is injected ONLY when it
    covers messages outside the raw window (kills the short-chat / caught-up
    duplication) (`lib/Services/ollama_service.dart:338-349, 392-401`).
  - Summarizer (`MemoryService.performUpdate`, was `_performUpdate`) now ingests the
    un-summarized tail from the boundary (not a fixed last-20) and advances the marker
    to `len - recentMessagesToKeep` via `parseAndSave(..., summarizedThrough:)`
    (`lib/Services/memory_service.dart`).
  - Residual (documented, acceptable): the recent window kept raw may still be loosely
    described by the summary (bounded to `recentMessagesToKeep`), and legacy memories
    (count 0) send full history until the next summary sets the marker.
  - Tests: `test/services/ollama_context_window_test.dart` (2),
    `test/models/conversation_memory_test.dart` (F2 group, 2),
    `test/services/memory_context_pollution_test.dart` (F2 group, 2) — all green;
    watched each fail first. No new suite failures (`database_service.dart` untouched;
    its `get all chats` flake is the pre-existing `retry: 5` NULL-ordering test).

- **F3 — PARTIALLY FIXED (2026-07-02).** TDD.
  - `MemoryTopic.toPromptEntry()` now stamps the last-updated date:
    `- **[key]** (as of YYYY-MM-DD): content` (`lib/Models/memory_topic.dart`). Paired
    with the current-time line the agent-memory block already injects, the model can
    now discount stale, never-expiring topics.
  - Test: `test/models/memory_topic_test.dart` (updated contract, green).
  - Not done (deferred, by design): topic TTL/decay and per-chat scoping of ephemeral.
    Ephemeral left as-is — it is already TTL-bounded (≤14d) and tagged `recent:`.

- **F4 — FIXED (2026-07-02).** Chosen approach: strip blob + prior thinking. TDD.
  - `OllamaService.prepareMessagesWithSystemPrompt` now drops the `thinking` field
    (which carries the `<!--SEARCH_DATA:…-->` base64 blob AND the model's prior
    chain-of-thought) from every history message before building the request
    (`lib/Services/ollama_service.dart:354-372`). Only the SENT copy is affected — the
    persisted `thinking` the UI decodes (think-block + search card) is untouched.
  - Test: `test/services/ollama_context_window_test.dart` (F4 group, green).

## Status
- FIXED: F1, F2, F4, and F3 (partial). All via TDD (watched each fail first), all
  green, zero new failures in the non-integration suite.
- OPEN: F5 (indirect prompt injection from scraped pages — untrusted-data framing),
  F6 (WEBSEARCH trigger false-positive / heuristic query extraction), and the deferred
  parts of F3 (topic TTL/decay, ephemeral chat-scoping).

## Next Step
- F4 follow-up (optional): empirically confirm whether ollama.com re-feeds assistant
  `thinking`. The fix is already unconditionally beneficial (stops re-sending stale
  scraped page dumps every turn), so this only refines how much it mattered.
- F5/F6 remain if desired; each still has an isolable root cause — do NOT bundle.
- Pre-existing test debt surfaced (NOT caused by this work): `mode_palette_test` (3
  color-threshold failures), untracked WIP `chat_app_bar_mobile_test` /
  `chat_page_safe_area_test`, and the `database_service_test` "get all chats"
  `retry: 5` NULL-ordering flake.
