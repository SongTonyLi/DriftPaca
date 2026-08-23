import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Services/search_agent.dart';
import 'package:llamaseek/Services/web_search_service.dart';

final history = [
  OllamaMessage('What is Vietnam GDP?', role: OllamaMessageRole.user),
];

OllamaMessage answerChunk(String content, {String? thinking}) => OllamaMessage(
      content,
      role: OllamaMessageRole.assistant,
      thinking: thinking,
    );

OllamaMessage searchChunk(String query, {String? thinking}) => OllamaMessage(
      '',
      role: OllamaMessageRole.assistant,
      thinking: thinking,
      toolCalls: [
        OllamaToolCall(name: 'web_search', arguments: {'query': query}),
      ],
    );

WebSearchResult hit(String url, {String title = 'T'}) => WebSearchResult(
      title: title,
      snippet: 'S',
      url: url,
      pageContent: 'body',
    );

/// Lexically unrelated query phrases (max pairwise trigram similarity
/// ~0.26 — well under the ledger's 0.40 grouping threshold) for tests
/// that need many rounds' worth of genuinely distinct, non-grouping
/// sub-goals. A naive "topic $n" numbering scheme doesn't work here: those
/// strings share a long common prefix and score up to 0.83 against each
/// other, so the ledger would group (and eventually budget-block) them —
/// exactly the near-duplicate behavior under test elsewhere, not what
/// these convergence-cap tests want to exercise.
const distinctTopics = [
  'kangaroo diet facts',
  'printer ink cartridge types',
  'medieval sword forging',
  'volcanic eruption warning signs',
  'coral reef bleaching causes',
  'jazz music history',
  'electric vehicle battery chemistry',
  'ancient Roman aqueducts',
  'sourdough bread starter',
  'glacier melting rate',
  'spider silk strength',
  'coffee bean roasting process',
  'lighthouse construction methods',
  'beekeeping honey extraction',
  'meteor shower viewing tips',
  'cheese aging process',
  'bamboo growth speed',
  'arctic fox camouflage',
];

SearchAgent agent({
  required Stream<OllamaMessage> Function(SearchAgentRequest) streamTurn,
  Future<List<WebSearchResult>> Function(SearchAgentSearchRequest)? search,
  int maxSearches = 3,
  int? maxRounds,
  int? stallLimit,
  int? perSubGoalBudget,
}) {
  return SearchAgent(
    maxSearches: maxSearches,
    maxRounds: maxRounds ?? SearchAgent.defaultMaxRounds,
    stallLimit: stallLimit ?? SearchAgent.defaultStallLimit,
    perSubGoalBudget: perSubGoalBudget ?? SearchAgent.defaultPerSubGoalBudget,
    streamTurn: streamTurn,
    search: search ??
        (req) async => [hit('https://example.com/${req.query}')],
  );
}

void main() {
  test('no tool_calls answers directly with tools and memory on first turn', () async {
    final requests = <SearchAgentRequest>[];
    final outcome = await agent(
      streamTurn: (req) {
        requests.add(req);
        return Stream.fromIterable([answerChunk('plain answer')]);
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(outcome.content, 'plain answer');
    expect(outcome.searchCount, 0);
    expect(outcome.cancelled, isFalse);
    expect(requests, hasLength(1));
    expect(requests.single.toolsEnabled, isTrue);
    expect(requests.single.includeMemory, isTrue);
  });

  test('one search then answer; transcript is assistant+tool; memory off', () async {
    final requests = <SearchAgentRequest>[];
    var turn = 0;
    final outcome = await agent(
      streamTurn: (req) {
        requests.add(req);
        turn++;
        if (turn == 1) {
          return Stream.fromIterable(
              [searchChunk('Vietnam GDP', thinking: 'need search')]);
        }
        return Stream.fromIterable([answerChunk('GDP is X [1]')]);
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(outcome.searchCount, 1);
    expect(outcome.content, 'GDP is X [1]');
    expect(requests, hasLength(2));
    expect(requests[0].includeMemory, isTrue);
    expect(requests[0].toolsEnabled, isTrue);
    expect(requests[1].includeMemory, isFalse);
    expect(requests[1].transcript, hasLength(2));
    expect(requests[1].transcript[0].role, OllamaMessageRole.assistant);
    expect(requests[1].transcript[0].toolCalls, isNotEmpty);
    expect(requests[1].transcript[0].thinking, 'need search');
    expect(requests[1].transcript[1].role, OllamaMessageRole.tool);
    expect(requests[1].transcript[1].toolName, 'web_search');
  });

  test('two sequential searches accumulate source ids 1 then 2', () async {
    final requests = <SearchAgentRequest>[];
    var turn = 0;
    final outcome = await agent(
      streamTurn: (req) {
        requests.add(req);
        turn++;
        if (turn == 1) return Stream.fromIterable([searchChunk('Vietnam')]);
        if (turn == 2) return Stream.fromIterable([searchChunk('Thailand')]);
        return Stream.fromIterable([answerChunk('done')]);
      },
      search: (req) async => [
        hit(req.query == 'Vietnam'
            ? 'https://example.com/vn'
            : 'https://example.com/th'),
      ],
    ).run(history: history, listener: const SearchAgentListener());

    expect(outcome.searchCount, 2);
    expect(outcome.sourceUrls[1], 'https://example.com/vn');
    expect(outcome.sourceUrls[2], 'https://example.com/th');
    expect(requests[1].transcript.last.content, contains('id="1"'));
    expect(requests[2].transcript.last.content, contains('id="2"'));
  });

  test('two tool_calls in one turn run start-then-search in order', () async {
    final events = <String>[];
    var turn = 0;
    final outcome = await agent(
      streamTurn: (req) {
        turn++;
        if (turn == 1) {
          return Stream.fromIterable([
            OllamaMessage(
              '',
              role: OllamaMessageRole.assistant,
              toolCalls: [
                const OllamaToolCall(
                    name: 'web_search', arguments: {'query': 'Vietnam GDP'}),
                const OllamaToolCall(
                    name: 'web_search', arguments: {'query': 'Thailand GDP'}),
              ],
            ),
          ]);
        }
        return Stream.fromIterable([answerChunk('both')]);
      },
      search: (req) async {
        events.add('search:${req.query}');
        await Future<void>.delayed(const Duration(milliseconds: 15));
        return [hit('https://example.com/${req.query}', title: req.query)];
      },
    ).run(
      history: history,
      listener: SearchAgentListener(
        onSearchStart: (q) => events.add('start:$q'),
        onSearchComplete: (r, ids) => events.add('complete:${r.single.title}'),
      ),
    );

    expect(events, [
      'start:Vietnam GDP',
      'search:Vietnam GDP',
      'complete:Vietnam GDP',
      'start:Thailand GDP',
      'search:Thailand GDP',
      'complete:Thailand GDP',
    ]);
    expect(outcome.searchCount, 2);
    expect(outcome.sourceUrls.keys.toList()..sort(), [1, 2]);
  });

  test('dedupes identical queries case-insensitively', () async {
    final queries = <String>[];
    var turn = 0;
    final outcome = await agent(
      streamTurn: (req) {
        turn++;
        if (turn == 1) {
          return Stream.fromIterable([
            OllamaMessage(
              '',
              role: OllamaMessageRole.assistant,
              toolCalls: [
                const OllamaToolCall(
                    name: 'web_search', arguments: {'query': 'Vietnam GDP'}),
                const OllamaToolCall(
                    name: 'web_search', arguments: {'query': 'vietnam gdp'}),
              ],
            ),
          ]);
        }
        return Stream.fromIterable([answerChunk('one search')]);
      },
      search: (req) async {
        queries.add(req.query);
        return [hit('https://example.com/vn')];
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(queries, ['Vietnam GDP']);
    expect(outcome.searchCount, 1);
  });

  test('every tool_call gets exactly one tool-role response, including an empty-query call', () async {
    final requests = <SearchAgentRequest>[];
    var turn = 0;
    await agent(
      streamTurn: (req) {
        requests.add(req);
        turn++;
        if (turn == 1) {
          return Stream.fromIterable([
            OllamaMessage(
              '',
              role: OllamaMessageRole.assistant,
              toolCalls: [
                const OllamaToolCall(
                    name: 'web_search', arguments: {'query': 'Vietnam GDP'}),
                const OllamaToolCall(
                    name: 'web_search', arguments: {'query': ''}),
              ],
            ),
          ]);
        }
        return Stream.fromIterable([answerChunk('done')]);
      },
    ).run(history: history, listener: const SearchAgentListener());

    final toolMessages = requests[1]
        .transcript
        .where((m) => m.role == OllamaMessageRole.tool)
        .toList();
    expect(toolMessages, hasLength(2));
    expect(toolMessages[1].content, isNotEmpty);
  });

  test('a call beyond the remaining budget still gets a tool-role response', () async {
    final requests = <SearchAgentRequest>[];
    final skipped = <String>[];
    var turn = 0;
    final outcome = await agent(
      maxSearches: 1,
      streamTurn: (req) {
        requests.add(req);
        turn++;
        if (turn == 1) {
          return Stream.fromIterable([
            OllamaMessage(
              '',
              role: OllamaMessageRole.assistant,
              toolCalls: [
                const OllamaToolCall(
                    name: 'web_search', arguments: {'query': 'Vietnam GDP'}),
                const OllamaToolCall(
                    name: 'web_search', arguments: {'query': 'Thailand GDP'}),
              ],
            ),
          ]);
        }
        return Stream.fromIterable([answerChunk('done')]);
      },
    ).run(
      history: history,
      listener: SearchAgentListener(
        onSearchSkipped: (query, reason) => skipped.add(query),
      ),
    );

    expect(outcome.searchCount, 1);
    final toolMessages = requests[1]
        .transcript
        .where((m) => m.role == OllamaMessageRole.tool)
        .toList();
    expect(toolMessages, hasLength(2));
    expect(toolMessages[1].content, contains('budget'));
    expect(skipped, ['Thailand GDP']);
  });

  test('a model that only ever emits an empty-query tool call terminates within the round cap', () async {
    var turns = 0;
    final outcome = await agent(
      maxRounds: 5,
      // Isolates the round cap: every empty-query round is ALSO
      // unproductive by the step-4 stall definition, so a default
      // stallLimit would stop this earlier and the round cap would never
      // be exercised. See the stall-specific tests below for that case.
      stallLimit: 1000,
      streamTurn: (req) {
        turns++;
        return Stream.fromIterable([
          OllamaMessage(
            '',
            role: OllamaMessageRole.assistant,
            toolCalls: [
              const OllamaToolCall(
                  name: 'web_search', arguments: {'query': ''}),
            ],
          ),
        ]);
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(outcome.searchCount, 0);
    expect(outcome.cancelled, isFalse);
    // maxRounds + 1 tools-disabled turn + 1 forced-answer retry, since this
    // fake only ever emits tool calls and never any prose.
    expect(turns, 7);
  });

  test('a near-duplicate query in a later round is redirected without a real network search', () async {
    var searchCalls = 0;
    var turn = 0;
    final outcome = await agent(
      streamTurn: (req) {
        turn++;
        if (turn == 1) {
          return Stream.fromIterable([searchChunk('Tesla stock price today')]);
        }
        if (turn == 2) {
          // A trivial rephrasing of round 1's query — a genuine
          // near-duplicate, not just a topically-related follow-up.
          return Stream.fromIterable(
              [searchChunk('Tesla stock price today USD')]);
        }
        return Stream.fromIterable([answerChunk('done')]);
      },
      search: (req) async {
        searchCalls++;
        return [hit('https://example.com/${req.query}')];
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(searchCalls, 1);
    expect(outcome.searchCount, 1);
  });

  test('a cross-round exact-duplicate query gets a non-empty tool message', () async {
    final requests = <SearchAgentRequest>[];
    var turn = 0;
    await agent(
      streamTurn: (req) {
        requests.add(req);
        turn++;
        if (turn == 1) return Stream.fromIterable([searchChunk('Vietnam GDP')]);
        if (turn == 2) {
          return Stream.fromIterable([searchChunk('vietnam gdp')]);
        }
        return Stream.fromIterable([answerChunk('done')]);
      },
    ).run(history: history, listener: const SearchAgentListener());

    // requests[2] is the outgoing request after round 2's (blocked) search.
    final lastToolMessage = requests[2]
        .transcript
        .lastWhere((m) => m.role == OllamaMessageRole.tool);
    expect(lastToolMessage.content, isNotEmpty);
    expect(lastToolMessage.content, contains('already asked'));
  });

  test('a per-round batch cap limits accepted searches even with distinct fresh queries', () async {
    final requests = <SearchAgentRequest>[];
    var turn = 0;
    final outcome = await agent(
      streamTurn: (req) {
        requests.add(req);
        turn++;
        if (turn == 1) {
          return Stream.fromIterable([
            OllamaMessage(
              '',
              role: OllamaMessageRole.assistant,
              toolCalls: [
                const OllamaToolCall(
                    name: 'web_search', arguments: {'query': 'Vietnam GDP'}),
                const OllamaToolCall(
                    name: 'web_search', arguments: {'query': 'Thailand GDP'}),
                const OllamaToolCall(
                    name: 'web_search', arguments: {'query': 'Laos GDP'}),
              ],
            ),
          ]);
        }
        return Stream.fromIterable([answerChunk('done')]);
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(outcome.searchCount, 2); // default round batch cap is 2
    final toolMessages = requests[1]
        .transcript
        .where((m) => m.role == OllamaMessageRole.tool)
        .toList();
    expect(toolMessages, hasLength(3));
    expect(toolMessages[2].content, contains('Not run this round'));
  });

  test('round 2 request transcript carries the round-1 query and marks it searched', () async {
    final requests = <SearchAgentRequest>[];
    var turn = 0;
    await agent(
      streamTurn: (req) {
        requests.add(req);
        turn++;
        if (turn == 1) {
          return Stream.fromIterable([searchChunk('Vietnam GDP 2024')]);
        }
        return Stream.fromIterable([answerChunk('done')]);
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(requests[1].transcript.last.content, contains('Vietnam GDP 2024'));
    expect(requests[1].transcript.last.content, contains('Searched'));
  });

  test('a query grouped onto a sub-goal that already hit its search budget is redirected', () async {
    // Four phrasings that all cluster around one underlying question but
    // aren't so similar to each other that any single pair alone would
    // trip a near-duplicate gate — this is the mechanism that catches the
    // measured thrash pattern the trigram gate alone misses.
    const queries = [
      'best hiking trails in Colorado for beginners',
      'best hiking trails in Colorado for families',
      'beginner-friendly hiking trails Colorado',
      'Colorado beginner hiking trail guide',
    ];
    final requests = <SearchAgentRequest>[];
    var searchCalls = 0;
    var turn = 0;
    final outcome = await agent(
      // Deliberately well above defaultPerSubGoalBudget(3) and above
      // queries.length(4) — this helper's own maxSearches default is
      // ALSO 3, which would make this test pass purely from the unrelated
      // global search cap regardless of whether the per-sub-goal budget
      // exists at all. Only a cap this generous proves the redirect below
      // is caused by the per-sub-goal budget, not by maxSearches.
      maxSearches: 15,
      // Also isolate from roundsSinceNewSubGoal: with the default
      // stallLimit(2), 2 consecutive grouped-without-opening-new rounds
      // (rounds 2 and 3 here) already disable tools before the model's 4th
      // attempt is ever evaluated, so the per-sub-goal budget would never
      // get a chance to fire at all. That's a real, separate convergence
      // path — see the roundsSinceNewSubGoal-isolation test above — not
      // what THIS test targets.
      stallLimit: 100,
      streamTurn: (req) {
        requests.add(req);
        turn++;
        if (turn <= queries.length) {
          return Stream.fromIterable([searchChunk(queries[turn - 1])]);
        }
        return Stream.fromIterable([answerChunk('done')]);
      },
      search: (req) async {
        searchCalls++;
        return [hit('https://example.com/$searchCalls')];
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(searchCalls, 3); // budget exhausted after 3 searches
    expect(outcome.searchCount, 3);
    expect(outcome.searchCount, lessThan(15));

    // Pin the MECHANISM, not just the count: the 4th query's tool message
    // must carry the per-sub-goal redirect text, not merely happen to stop
    // at 3 for some unrelated reason.
    final fourthRoundToolMessage = requests[4]
        .transcript
        .where((m) => m.role == OllamaMessageRole.tool)
        .last;
    expect(fourthRoundToolMessage.content,
        contains('You already asked something very close to this'));
  });

  test('onLedgerUpdate fires once per search round with the objective and snapshot', () async {
    final objectives = <String>[];
    var turn = 0;
    await agent(
      streamTurn: (req) {
        turn++;
        if (turn == 1) {
          return Stream.fromIterable([searchChunk('Vietnam GDP 2024')]);
        }
        return Stream.fromIterable([answerChunk('done')]);
      },
    ).run(
      history: history,
      listener: SearchAgentListener(
        onLedgerUpdate: (objective, snapshot) => objectives.add(objective),
      ),
    );

    expect(objectives, hasLength(1));
    expect(objectives.single, 'What is Vietnam GDP?');
  });

  test('two consecutive unproductive rounds stop the loop well under the hard cap', () async {
    var turn = 0;
    final outcome = await agent(
      maxSearches: 15,
      streamTurn: (req) {
        turn++;
        if (turn == 1) {
          return Stream.fromIterable([searchChunk('Tesla stock price today')]);
        }
        // A stubborn near-duplicate every subsequent turn, regardless of
        // whether tools are still enabled on the request.
        return Stream.fromIterable(
            [searchChunk('Tesla stock price today USD')]);
      },
      search: (req) async => [hit('https://example.com/${Uri.encodeComponent(req.query)}')],
    ).run(history: history, listener: const SearchAgentListener());

    expect(outcome.searchCount, 1);
    expect(outcome.reason, SearchTerminationReason.unproductiveRounds);
    // round 1 (real search) + 2 unproductive + tools-withdrawn turn +
    // 1 forced-answer retry (this fake never emits prose).
    expect(turn, 5);
  });

  test(
      'rounds that keep grouping onto the same sub-goal without ever opening a new one stop the loop, even though every round made real progress',
      () async {
    // Measured against the shipped trigramJaccard implementation: each of
    // these scores between the ledger's 0.40 grouping threshold and the
    // 0.75 near-duplicate block threshold versus the FIRST phrasing (0.694,
    // then 0.743 — see the near-identical measured Washington/Paris trace),
    // so every one groups onto the SAME sub-goal without ever being
    // blocked outright. perSubGoalBudget is set high so that mechanism
    // can't independently end the run either: only roundsSinceNewSubGoal
    // can, isolating it from roundsSinceProgress (which every other
    // "unproductive" test above leaves conflated — see this fix's second
    // reviewed issue).
    const phrasings = [
      'Washington D.C. population 2026 estimate',
      'Washington, D.C. population 2025',
      'Washington DC population 2026',
    ];
    var urlCounter = 0;
    var turn = 0;
    final outcome = await agent(
      maxSearches: 6,
      perSubGoalBudget: 100,
      streamTurn: (req) {
        turn++;
        // Deliberately stubborn: keeps asking regardless of toolsEnabled,
        // so the assertions below can only pass because the HARNESS
        // stopped accepting searches, not because the fake model
        // cooperated.
        final phrase = phrasings[turn - 1 < phrasings.length ? turn - 1 : phrasings.length - 1];
        return Stream.fromIterable([searchChunk(phrase)]);
      },
      search: (req) async {
        urlCounter++;
        // A fresh URL every call — this round always "makes progress" by
        // the harness's own definition, so roundsSinceProgress never trips.
        return [hit('https://example.com/$urlCounter')];
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(outcome.reason, SearchTerminationReason.unproductiveRounds);
    expect(outcome.searchCount, 3);
    // round 1 (opens) + 2 grouped rounds + tools-withdrawn turn +
    // 1 forced-answer retry (this fake never emits prose).
    expect(turn, 5);
  });

  test('a sub-goal that never returns results stops the loop as unproductive, not converged', () async {
    var turn = 0;
    final outcome = await agent(
      streamTurn: (req) {
        turn++;
        // Fresh, unrelated topics every round — nothing for the ledger to
        // group or redirect — but every search comes back empty.
        return Stream.fromIterable([searchChunk(distinctTopics[turn - 1])]);
      },
      search: (req) async => [],
    ).run(history: history, listener: const SearchAgentListener());

    expect(outcome.reason, SearchTerminationReason.unproductiveRounds);
    expect(turn, lessThan(10));
  });

  test('a model that always requests a fresh search regardless of toolsEnabled still terminates', () async {
    var turn = 0;
    final outcome = await agent(
      maxSearches: SearchAgent.defaultMaxSearches,
      streamTurn: (req) {
        turn++;
        return Stream.fromIterable([searchChunk(distinctTopics[turn - 1])]);
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(outcome.cancelled, isFalse);
    expect(outcome.searchCount, SearchAgent.defaultMaxSearches);
    expect(outcome.reason, SearchTerminationReason.hardCapReached);
    // +1 tools-disabled turn, +1 forced-answer retry: this fake keeps
    // requesting searches and never volunteers prose.
    expect(turn, SearchAgent.defaultMaxSearches + 2);
  });

  test('the round cap terminates a run that never stalls and never exhausts the search budget', () async {
    var turn = 0;
    final outcome = await agent(
      maxSearches: 15,
      maxRounds: 3,
      streamTurn: (req) {
        turn++;
        // Every round opens a fresh, productive, unrelated sub-goal, so
        // neither stall counter nor the (much higher) search cap trips.
        return Stream.fromIterable([searchChunk(distinctTopics[turn - 1])]);
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(outcome.cancelled, isFalse);
    expect(outcome.searchCount, 3);
    expect(outcome.reason, SearchTerminationReason.roundCapReached);
  });

  test('the loop converges on its own once the model stops requesting searches', () async {
    var turn = 0;
    final outcome = await agent(
      streamTurn: (req) {
        turn++;
        if (turn <= 2) {
          return Stream.fromIterable([searchChunk(distinctTopics[turn - 1])]);
        }
        return Stream.fromIterable([answerChunk('final answer')]);
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(outcome.searchCount, 2);
    expect(outcome.content, 'final answer');
    expect(outcome.reason, SearchTerminationReason.converged);
  });

  test('after max 3 searches the last turn disables tools', () async {
    final requests = <SearchAgentRequest>[];
    final outcome = await agent(
      streamTurn: (req) {
        requests.add(req);
        if (req.toolsEnabled) {
          return Stream.fromIterable([searchChunk('q${requests.length}')]);
        }
        return Stream.fromIterable([answerChunk('must answer')]);
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(outcome.searchCount, 3);
    expect(requests, hasLength(4));
    expect(requests.take(3).every((r) => r.toolsEnabled), isTrue);
    expect(requests.last.toolsEnabled, isFalse);
    expect(outcome.content, 'must answer');
    expect(outcome.reason, SearchTerminationReason.hardCapReached);
  });

  test('cancel during search skips the next model turn', () async {
    var cancelled = false;
    var turns = 0;
    final outcome = await agent(
      streamTurn: (req) {
        turns++;
        return Stream.fromIterable([searchChunk('Vietnam GDP')]);
      },
      search: (req) async {
        cancelled = true;
        return [hit('https://example.com/vn')];
      },
    ).run(
      history: history,
      listener: const SearchAgentListener(),
      isCancelled: () => cancelled,
    );

    expect(outcome.cancelled, isTrue);
    expect(outcome.reason, SearchTerminationReason.cancelled);
    expect(turns, 1);
  });

  test('preamble content then tool_calls resets streamed content', () async {
    var resets = 0;
    var turn = 0;
    final contents = <String>[];
    final outcome = await agent(
      streamTurn: (req) {
        turn++;
        if (turn == 1) {
          return Stream.fromIterable([
            answerChunk('Let me look that up.'),
            searchChunk('Vietnam GDP'),
          ]);
        }
        return Stream.fromIterable([answerChunk('Final [1]')]);
      },
    ).run(
      history: history,
      listener: SearchAgentListener(
        onResetContent: () => resets++,
        onContent: contents.add,
      ),
    );

    expect(resets, greaterThanOrEqualTo(1));
    expect(outcome.content, 'Final [1]');
    expect(contents.last, 'Final [1]');
  });

  test('a URL returned in round 1 is passed as excludeUrls on round 2\'s search request', () async {
    final excludeUrlsSeen = <Set<String>>[];
    var turn = 0;
    await agent(
      streamTurn: (req) {
        turn++;
        if (turn == 1) return Stream.fromIterable([searchChunk('Vietnam GDP')]);
        if (turn == 2) return Stream.fromIterable([searchChunk('Thailand GDP')]);
        return Stream.fromIterable([answerChunk('done')]);
      },
      search: (req) async {
        excludeUrlsSeen.add(req.excludeUrls);
        return [hit('https://example.com/${req.query}')];
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(excludeUrlsSeen[0], isEmpty);
    expect(excludeUrlsSeen[1], contains('https://example.com/Vietnam GDP'));
  });

  test('a search with no results still invites a retry, not a bare "no results" string', () async {
    final requests = <SearchAgentRequest>[];
    var turn = 0;
    await agent(
      streamTurn: (req) {
        requests.add(req);
        turn++;
        if (turn == 1) {
          return Stream.fromIterable(
              [searchChunk('Nonexistent Widget Corp revenue')]);
        }
        return Stream.fromIterable([answerChunk('done')]);
      },
      search: (req) async => [],
    ).run(history: history, listener: const SearchAgentListener());

    final toolMessage = requests[1].transcript.last;
    expect(toolMessage.role, OllamaMessageRole.tool);
    // The bare old message was just 'No results found for "<query>".' with
    // no guidance. This pins a specific retry/ledger-check phrase so the
    // assertion can't be satisfied by the (unrelated) ledger block's own
    // "### Research ledger" boilerplate that gets appended after it.
    expect(toolMessage.content, contains('Try a different phrasing'));
  });

  test('stale rounds are compacted to a citation-only line once the transcript exceeds budget, keeping the last 2 rounds raw', () async {
    final requests = <SearchAgentRequest>[];
    var turn = 0;
    const roundCount = 8;
    await SearchAgent(
      maxSearches: roundCount + 2,
      maxRounds: roundCount + 2,
      transcriptBudgetChars: 1, // force compaction as soon as it's allowed
      streamTurn: (req) {
        requests.add(req);
        turn++;
        if (turn <= roundCount) {
          return Stream.fromIterable([searchChunk(distinctTopics[turn - 1])]);
        }
        return Stream.fromIterable([answerChunk('done')]);
      },
      search: (req) async =>
          [hit('https://example.com/${Uri.encodeComponent(req.query)}')],
    ).run(history: history, listener: const SearchAgentListener());

    final finalToolMessages = requests[roundCount]
        .transcript
        .where((m) => m.role == OllamaMessageRole.tool)
        .toList();
    expect(finalToolMessages, hasLength(roundCount));

    // Only the last 2 rounds (current + previous) stay raw; everything
    // older is compacted to a short citation-only line that still names
    // the query and its source ids.
    for (var i = 0; i < roundCount - 2; i++) {
      expect(finalToolMessages[i].content, isNot(contains('body')));
      expect(finalToolMessages[i].content, contains(distinctTopics[i]));
      expect(finalToolMessages[i].content, contains('[${i + 1}]'));
    }
    expect(finalToolMessages[roundCount - 2].content, contains('body'));
    expect(finalToolMessages[roundCount - 1].content, contains('body'));

    // Prove growth is actually bounded, not just that one message shrank:
    // 8 uncompacted rounds would be roughly 8x a single raw round.
    final oneRoundRaw = WebSearchService.formatResultsAsContext(
      [hit('https://example.com/x')],
      query: distinctTopics[0],
    ).length;
    final totalToolTextLength = finalToolMessages
        .fold<int>(0, (sum, m) => sum + m.content.length);
    expect(totalToolTextLength, lessThan(oneRoundRaw * roundCount / 2));
  });

  test('onSearchComplete receives the exact id-to-URL map for that call, not the cumulative one', () async {
    final maps = <Map<int, String>>[];
    var turn = 0;
    await agent(
      streamTurn: (req) {
        turn++;
        if (turn == 1) return Stream.fromIterable([searchChunk('Vietnam')]);
        if (turn == 2) return Stream.fromIterable([searchChunk('Thailand')]);
        return Stream.fromIterable([answerChunk('done')]);
      },
      search: (req) async => [
        hit(req.query == 'Vietnam'
            ? 'https://example.com/vn'
            : 'https://example.com/th'),
      ],
    ).run(
      history: history,
      listener: SearchAgentListener(
        onSearchComplete: (results, sourceUrls) => maps.add(sourceUrls),
      ),
    );

    expect(maps, hasLength(2));
    expect(maps[0].keys.toList(), [1]);
    expect(maps[0][1], 'https://example.com/vn');
    expect(maps[1].keys.toList(), [2]);
    expect(maps[1][2], 'https://example.com/th');
  });

  test('SearchAgent defaults to more than 3 searches when maxSearches is not specified', () async {
    var turn = 0;
    // Constructed directly (not via the agent() test helper, which always
    // forwards its own maxSearches:3 default) so this exercises
    // SearchAgent's own class default, decoupled from any caller-supplied
    // value.
    final outcome = await SearchAgent(
      streamTurn: (req) {
        turn++;
        if (turn <= 4) {
          return Stream.fromIterable([searchChunk(distinctTopics[turn - 1])]);
        }
        return Stream.fromIterable([answerChunk('done')]);
      },
      search: (req) async => [hit('https://example.com/${req.query}')],
    ).run(history: history, listener: const SearchAgentListener());

    expect(outcome.searchCount, greaterThan(3));
    expect(outcome.searchCount, 4);
  });

  group('transcriptLimitsFor', () {
    test('a default-sized (2048) context window derives a much smaller budget and raw-round floor than a generous one', () {
      final small = SearchAgent.transcriptLimitsFor(2048);
      final large = SearchAgent.transcriptLimitsFor(65536);

      expect(small.transcriptBudgetChars,
          lessThan(SearchAgent.defaultTranscriptBudgetChars));
      expect(small.minRawRounds, lessThan(SearchAgent.defaultMinRawRounds));
      expect(large.transcriptBudgetChars,
          greaterThan(SearchAgent.defaultTranscriptBudgetChars));
      expect(large.minRawRounds, SearchAgent.defaultMinRawRounds);
    });

    test('clamps a pathologically tiny or huge context window to a workable budget', () {
      expect(SearchAgent.transcriptLimitsFor(0).transcriptBudgetChars, 4000);
      expect(SearchAgent.transcriptLimitsFor(1000000).transcriptBudgetChars,
          200000);
    });
  });

  test(
      'a small configured context window compacts far more aggressively than the flat default would, using realistic result sizes',
      () async {
    // ~1500-char chunks and 8 results/search mirror production defaults
    // (WebSearchService.searchAndExtract's chunkSize/maxResults) — the
    // point of this test is that a small window's DERIVED limits actually
    // change behavior, unlike a flat pair of constants untethered from it.
    String filler(int length) {
      final buffer = StringBuffer();
      while (buffer.length < length) {
        buffer.write('lorem ipsum dolor sit amet consectetur adipiscing ');
      }
      return buffer.toString().substring(0, length);
    }

    WebSearchResult realisticHit(String url) => WebSearchResult(
          title: 'T',
          snippet: 'S',
          url: url,
          chunks: [filler(1500), filler(1500)],
        );

    final limits = SearchAgent.transcriptLimitsFor(2048);
    final requests = <SearchAgentRequest>[];
    var turn = 0;
    const roundCount = 2;
    await SearchAgent(
      maxSearches: 100,
      maxRounds: roundCount + 2,
      transcriptBudgetChars: limits.transcriptBudgetChars,
      minRawRounds: limits.minRawRounds,
      streamTurn: (req) {
        requests.add(req);
        turn++;
        if (turn <= roundCount) {
          return Stream.fromIterable([
            OllamaMessage('', role: OllamaMessageRole.assistant, toolCalls: [
              OllamaToolCall(
                  name: 'web_search',
                  arguments: {'query': distinctTopics[2 * (turn - 1)]}),
              OllamaToolCall(
                  name: 'web_search',
                  arguments: {'query': distinctTopics[2 * (turn - 1) + 1]}),
            ]),
          ]);
        }
        return Stream.fromIterable([answerChunk('done')]);
      },
      search: (req) async => [
        for (var i = 0; i < 8; i++)
          realisticHit(
              'https://example.com/${Uri.encodeComponent(req.query)}/$i'),
      ],
    ).run(history: history, listener: const SearchAgentListener());

    final finalToolMessages = requests[roundCount]
        .transcript
        .where((m) => m.role == OllamaMessageRole.tool)
        .toList();
    expect(finalToolMessages, hasLength(roundCount * 2));

    // A window this small (2048) derives minRawRounds:1, so only the
    // single most recent round (last 2 messages) stays raw; a flat,
    // context-oblivious 2-round floor would have kept all 4 raw here.
    for (var i = 0; i < finalToolMessages.length - 2; i++) {
      expect(finalToolMessages[i].content, isNot(contains('lorem')));
    }
    expect(finalToolMessages[finalToolMessages.length - 2].content,
        contains('lorem'));
    expect(finalToolMessages[finalToolMessages.length - 1].content,
        contains('lorem'));
  });

  group('a model that will not stop searching still answers', () {
    // Observed against gpt-oss:120b: handed a request with `tools` omitted
    // after its budget ran out, it emitted another tool call and no prose,
    // which surfaced to the user as a completely blank message.
    test('is told research is closed and given one more turn to answer',
        () async {
      final requests = <SearchAgentRequest>[];
      var turn = 0;

      final outcome = await agent(
        maxSearches: 1,
        streamTurn: (req) {
          requests.add(req);
          turn++;
          // Never volunteers prose — only ever asks to search again, even
          // once tools have been withdrawn.
          if (turn <= 2) {
            return Stream.fromIterable([searchChunk(distinctTopics[turn - 1])]);
          }
          return Stream.fromIterable([answerChunk('answer from what I have')]);
        },
      ).run(history: history, listener: const SearchAgentListener());

      expect(outcome.content, 'answer from what I have',
          reason: 'a blank answer means the forced-answer turn did not run');

      // Turn 2 is the tools-withdrawn turn whose tool call gets refused.
      expect(requests[1].toolsEnabled, isFalse);

      // That refusal must be visible to the model as a tool-role reply, or
      // the follow-up request dangles an unanswered tool_call.
      final closing = requests.last.transcript
          .where((m) => m.role == OllamaMessageRole.tool)
          .last;
      expect(closing.content, contains('Research is closed'));
      expect(requests.last.toolsEnabled, isFalse);
    });

    test('gives up after one forced-answer attempt rather than looping',
        () async {
      var turn = 0;
      final outcome = await agent(
        maxSearches: 1,
        // Pathological: only ever emits tool calls, never any prose.
        streamTurn: (req) {
          turn++;
          return Stream.fromIterable([
            searchChunk(distinctTopics[(turn - 1) % distinctTopics.length]),
          ]);
        },
      ).run(history: history, listener: const SearchAgentListener());

      expect(outcome.content, isEmpty);
      // 1 search turn + 1 withdrawn turn + exactly 1 forced-answer retry.
      expect(turn, 3, reason: 'the forced-answer turn must fire only once');
    });
  });
}
