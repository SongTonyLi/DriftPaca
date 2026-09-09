import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Models/research_ledger.dart';
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
  Future<List<String>> Function(CoverageRequest)? assessCoverage,
  int? maxCoverageChecks,
}) {
  return SearchAgent(
    maxSearches: maxSearches,
    maxRounds: maxRounds ?? SearchAgent.defaultMaxRounds,
    stallLimit: stallLimit ?? SearchAgent.defaultStallLimit,
    perSubGoalBudget: perSubGoalBudget ?? SearchAgent.defaultPerSubGoalBudget,
    maxCoverageChecks:
        maxCoverageChecks ?? SearchAgent.defaultMaxCoverageChecks,
    assessCoverage: assessCoverage,
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

  test('OpenRouter-style q alias is treated as the search query', () async {
    final started = <String>[];
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
                  name: 'web_search',
                  arguments: {'q': 'current weather Bellevue WA'},
                ),
              ],
            ),
          ]);
        }
        return Stream.fromIterable([answerChunk('rainy')]);
      },
    ).run(
      history: history,
      listener: SearchAgentListener(onSearchStart: started.add),
    );

    expect(started, ['current weather Bellevue WA']);
    expect(outcome.searchCount, 1);
  });

  test('empty web_search arguments are skipped with a clear reason', () async {
    final skipped = <String>[];
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
                const OllamaToolCall(name: 'web_search', arguments: {}),
              ],
            ),
          ]);
        }
        return Stream.fromIterable([answerChunk('fallback')]);
      },
    ).run(
      history: history,
      listener: SearchAgentListener(
        onSearchSkipped: (q, reason) => skipped.add(reason),
      ),
    );

    expect(outcome.searchCount, 0);
    expect(skipped.single, contains('No query provided'));
    expect(outcome.content, 'fallback');
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

  test('the same statistic for three different years is three questions, not one near-duplicate', () async {
    // Trigram similarity is a string-shape measure, and a one-token
    // instance swap barely changes the shape: these three score 0.905
    // against each other — far above the 0.75 near-duplicate bar, which
    // was calibrated on real paraphrase pairs that topped out at 0.69. So
    // a question keyed by a year (or a version, or a quarter) had two
    // thirds of itself refused before it ever reached a search engine,
    // and the refusals then fed the stall counters that ended the run.
    const queries = [
      'US inflation rate 2023',
      'US inflation rate 2024',
      'US inflation rate 2025',
    ];
    // The user names all three years, which is what licenses splitting
    // them — see ResearchLedger._isDifferentRequestedInstance.
    final asked = [
      OllamaMessage('US inflation rate in 2023, 2024 and 2025?',
          role: OllamaMessageRole.user),
    ];
    final executed = <String>[];
    final skipped = <String>[];
    var turn = 0;
    await agent(
      // Generous on purpose: at the helper's default of 3 this could pass
      // off the global cap instead of proving the block was lifted.
      maxSearches: 15,
      streamTurn: (req) {
        turn++;
        if (turn <= queries.length) {
          return Stream.fromIterable([searchChunk(queries[turn - 1])]);
        }
        return Stream.fromIterable([answerChunk('done')]);
      },
      search: (req) async =>
          [hit('https://example.com/${Uri.encodeComponent(req.query)}')],
    ).run(
      history: asked,
      listener: SearchAgentListener(
        onSearchStart: executed.add,
        onSearchSkipped: (query, reason) => skipped.add(query),
      ),
    );

    expect(executed, queries);
    expect(skipped, isEmpty);
  });

  test('four instances of one question are four sub-goals, so none is left unsearched', () async {
    // Lifting the near-duplicate refusal is not enough on its own: the
    // ledger still GROUPED every year onto a single sub-goal at its 0.40
    // threshold, and two independent bounds then capped the question at
    // three instances — perSubGoalBudget (3 searches against one sub-goal)
    // and stallLimit on roundsSinceNewSubGoal (no NEW sub-goal opened
    // after round 1, so the run reads as stalled and ends). A four-part
    // question came back missing its fourth part either way.
    const queries = [
      'US inflation rate 2021',
      'US inflation rate 2022',
      'US inflation rate 2023',
      'US inflation rate 2024',
    ];
    final asked = [
      OllamaMessage('What was the US inflation rate in 2021, 2022, 2023 '
          'and 2024?', role: OllamaMessageRole.user),
    ];
    final executed = <String>[];
    final skipped = <String>[];
    var snapshot = <SubGoal>[];
    var turn = 0;
    await agent(
      maxSearches: 15,
      streamTurn: (req) {
        turn++;
        if (turn <= queries.length) {
          return Stream.fromIterable([searchChunk(queries[turn - 1])]);
        }
        return Stream.fromIterable([answerChunk('done')]);
      },
      search: (req) async =>
          [hit('https://example.com/${Uri.encodeComponent(req.query)}')],
    ).run(
      history: asked,
      listener: SearchAgentListener(
        onSearchStart: executed.add,
        onSearchSkipped: (query, reason) => skipped.add(query),
        onLedgerUpdate: (objective, goals) => snapshot = goals,
      ),
    );

    expect(executed, queries);
    expect(skipped, isEmpty);
    // The outcome above is downstream of this: each year has to be its own
    // sub-goal, or it shares one budget, opens no new sub-goal, and — since
    // markSearched keeps the FIRST evidence it saw — leaves the ledger
    // advertising 2021's sources as though they covered all four years.
    expect(snapshot.length, 4);
    expect(snapshot.map((g) => g.status),
        everyElement(SubGoalStatus.searched));
    expect(snapshot.map((g) => g.sourceIdStart).toSet().length, 4,
        reason: 'each year must carry its own evidence, not share 2021\'s');
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
    expect(requests[1].transcript.last.content,
        contains('- [x] "Vietnam GDP 2024"'));
    expect(requests[1].transcript.last.content,
        contains(ResearchLedger.stoppingRule));
  });

  test('every turn carries the goal, checklist and stopping rule as a brief', () async {
    // The transcript copy of the ledger only exists from round 2 onward —
    // round 1 has no tool message to carry it. The brief is what puts a
    // finish line in front of the model on the turn that plans the run.
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

    expect(requests.first.transcript, isEmpty);
    expect(requests.first.researchBrief, contains('Goal: What is Vietnam GDP?'));
    expect(requests.first.researchBrief, contains(ResearchLedger.stoppingRule));
    // Round 2's brief has grown a ticked checklist item.
    expect(requests[1].researchBrief, contains('- [x] "Vietnam GDP 2024"'));
  });

  test('only the newest round carries the ledger in the transcript, and it agrees with the brief', () async {
    // Appended to every round and left there, the ledger reached the model
    // as one copy per round: by round 3 the oldest still showed `[ ]`
    // against items later rounds had ticked, with its own copy of the
    // stopping rule — a standing invitation to re-search a closed item.
    final requests = <SearchAgentRequest>[];
    var turn = 0;
    await agent(
      maxSearches: 10,
      streamTurn: (req) {
        requests.add(req);
        turn++;
        if (turn <= 3) {
          return Stream.fromIterable([searchChunk(distinctTopics[turn - 1])]);
        }
        return Stream.fromIterable([answerChunk('done')]);
      },
    ).run(history: history, listener: const SearchAgentListener());

    final toolMessages = requests[3]
        .transcript
        .where((m) => m.role == OllamaMessageRole.tool)
        .toList();
    expect(toolMessages, hasLength(3));
    final carriers =
        toolMessages.where((m) => m.content.contains('### Research ledger'));
    expect(carriers, hasLength(1),
        reason: 'exactly one ledger copy, never one per round');
    expect(carriers.single, same(toolMessages.last));
    // Stripping the old copy leaves that round's own results intact.
    expect(toolMessages.first.content, contains(distinctTopics[0]));
    expect(toolMessages.first.content, contains('body'));
    // And the one copy shows every round's state, not a stale snapshot.
    for (final topic in distinctTopics.take(3)) {
      expect(toolMessages.last.content, contains('- [x] "$topic"'));
    }
    expect(toolMessages.last.content, contains(ResearchLedger.stoppingRule));
  });

  test('a turn with tools withdrawn is briefed that research is closed, not invited to search', () async {
    // Dropping `tools` from the request while the brief still says "search
    // only to close a specific [ ] item" — under a system prompt that still
    // says "You have a web_search tool" — is how a literal-minded model
    // ends up emitting one more tool call and no prose, and needs a whole
    // extra turn to be told in a tool reply what its brief could have said.
    final requests = <SearchAgentRequest>[];
    await agent(
      streamTurn: (req) {
        requests.add(req);
        if (req.toolsEnabled) {
          return Stream.fromIterable([searchChunk(distinctTopics[requests.length - 1])]);
        }
        return Stream.fromIterable([answerChunk('must answer')]);
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(requests.last.toolsEnabled, isFalse);
    // Every turn that could still search was briefed with the open rule.
    for (final open in requests.take(requests.length - 1)) {
      expect(open.researchBrief, contains(ResearchLedger.stoppingRule));
      expect(open.researchBrief, isNot(contains(ResearchLedger.closedRule)));
    }
    expect(requests.last.researchBrief, contains(ResearchLedger.closedRule));
    expect(requests.last.researchBrief,
        isNot(contains(ResearchLedger.stoppingRule)));
    // The checklist itself is still there for the answer to cover.
    expect(requests.last.researchBrief, contains('- [x] "${distinctTopics[0]}"'));
    // The transcript copy tells the same story as the brief it sits under.
    final lastToolMessage = requests.last.transcript
        .lastWhere((m) => m.role == OllamaMessageRole.tool);
    expect(lastToolMessage.content, contains(ResearchLedger.closedRule));
    expect(lastToolMessage.content,
        isNot(contains(ResearchLedger.stoppingRule)));
  });

  test('a derived goal seeds the objective and an unticked checklist', () async {
    final requests = <SearchAgentRequest>[];
    var snapshot = <SubGoal>[];
    final outcome = await SearchAgent(
      streamTurn: (req) {
        requests.add(req);
        return Stream.fromIterable([answerChunk('done')]);
      },
      search: (req) async => [hit('https://example.com')],
      deriveGoal: (userQuestion) async => const ResearchGoal(
        statement: 'Establish Vietnam\'s 2024 GDP figure',
        subQuestions: ['Vietnam nominal GDP 2024', 'Vietnam GDP growth 2024'],
      ),
    ).run(
      history: history,
      listener: SearchAgentListener(
        onLedgerUpdate: (objective, goals) => snapshot = goals,
      ),
    );

    expect(outcome.content, 'done');
    expect(requests.first.researchBrief,
        contains('Goal: Establish Vietnam\'s 2024 GDP figure'));
    expect(requests.first.researchBrief,
        contains('- [ ] "Vietnam nominal GDP 2024"'));
    // Seeded as gaps, not as issued searches: charging them a search would
    // eat the per-sub-goal budget before anything has been looked up.
    expect(snapshot.map((g) => g.searchCount), everyElement(0));
    expect(snapshot.map((g) => g.status), everyElement(SubGoalStatus.open));
  });

  test('the research panel opens before the goal derivation returns', () async {
    // Deriving the goal is a whole model request of its own. Gating this
    // update on it left the bubble showing nothing for that request's
    // entire duration — tens of seconds on a reasoning model — even though
    // the fallback objective (the user's own question) is known up front.
    final derivation = Completer<ResearchGoal?>();
    final objectives = <String>[];
    final run = SearchAgent(
      streamTurn: (req) => Stream.fromIterable([answerChunk('done')]),
      search: (req) async => [hit('https://example.com')],
      deriveGoal: (_) => derivation.future,
    ).run(
      history: history,
      listener: SearchAgentListener(
        onLedgerUpdate: (objective, snapshot) => objectives.add(objective),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(objectives, ['What is Vietnam GDP?'],
        reason: 'the panel is open while the goal call is still in flight');

    derivation.complete(const ResearchGoal(statement: 'Establish Vietnam GDP'));
    await run;

    expect(objectives, ['What is Vietnam GDP?', 'Establish Vietnam GDP'],
        reason: 'the derived goal then replaces it in the same panel');
  });

  test('a goal derivation that fails leaves the run on the raw question', () async {
    final requests = <SearchAgentRequest>[];
    final outcome = await SearchAgent(
      streamTurn: (req) {
        requests.add(req);
        return Stream.fromIterable([answerChunk('done')]);
      },
      search: (req) async => [hit('https://example.com')],
      deriveGoal: (_) async => throw StateError('model unreachable'),
    ).run(history: history, listener: const SearchAgentListener());

    // Losing an entire research run because a framing call fell over would
    // be an absurd trade — the raw question is a workable objective.
    expect(outcome.content, 'done');
    expect(requests.first.researchBrief, contains('Goal: What is Vietnam GDP?'));
  });

  test('a checklist question the model works through does not read as a stall', () async {
    // Every sub-goal exists from round 1 when the checklist is pre-seeded,
    // so "did the list get longer" is false every round. Under that older
    // rule the run was cut off after two rounds with most of its own
    // checklist still unticked.
    const seeded = [
      'kangaroo diet facts',
      'printer ink cartridge types',
      'medieval sword forging',
      'volcanic eruption warning signs',
    ];
    final executed = <String>[];
    var turn = 0;
    final outcome = await SearchAgent(
      maxSearches: 15,
      streamTurn: (req) {
        turn++;
        if (turn <= seeded.length) {
          return Stream.fromIterable([searchChunk(seeded[turn - 1])]);
        }
        return Stream.fromIterable([answerChunk('done')]);
      },
      search: (req) async => [hit('https://example.com/${req.query}')],
      deriveGoal: (_) async =>
          const ResearchGoal(statement: 'cover four topics', subQuestions: seeded),
    ).run(
      history: history,
      listener: SearchAgentListener(onSearchStart: executed.add),
    );

    expect(executed, seeded);
    expect(outcome.reason, SearchTerminationReason.converged);
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

  test('onLedgerUpdate fires before the first turn, then once per search round', () async {
    // The leading update is what lets the UI place its research panel at
    // the top of the run. Fired only after round 1 instead, the panel gets
    // appended below that round's search cards and stays wedged there —
    // ending up showing the run's findings and its "research complete"
    // banner above searches that had not happened yet when it was placed.
    final objectives = <String>[];
    final sizes = <int>[];
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
        onLedgerUpdate: (objective, snapshot) {
          objectives.add(objective);
          sizes.add(snapshot.length);
        },
      ),
    );

    expect(objectives, hasLength(2));
    expect(objectives, everyElement('What is Vietnam GDP?'));
    expect(sizes, [0, 1],
        reason: 'the opening update precedes any search, so it has no entries');
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
    //
    // The 2025/2026 wobble is the model's own invention — `history` asks
    // about Vietnam's GDP and names no year at all — so the ledger still
    // groups these, which is exactly the point: instance-splitting is
    // gated on years the USER asked for. See ResearchLedger.
    // _isDifferentRequestedInstance.
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

    test('a cloud chat keeps the generous defaults, because its num_ctx is never sent', () {
      // In cloud mode _buildOptions deliberately omits num_ctx, so the
      // configured contextSize describes nothing the model actually has.
      // Deriving from it shredded every round but the newest down to a
      // citation line and threw away the evidence the answer needed.
      final cloud =
          SearchAgent.transcriptLimitsFor(2048, contextSizeApplies: false);

      expect(cloud.transcriptBudgetChars,
          SearchAgent.defaultTranscriptBudgetChars);
      expect(cloud.minRawRounds, SearchAgent.defaultMinRawRounds);
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

  group('a clarification before the first search', () {
    const clarification = ResearchClarification(
      question: 'Which Mercury?',
      options: ['The planet', 'The team'],
    );
    const goal = ResearchGoal(
      statement: 'Find the latest Mercury results',
      clarification: clarification,
    );

    test('waits for the user, then folds their picks into the brief and the gate',
        () async {
      final requests = <SearchAgentRequest>[];
      final assessed = <CoverageRequest>[];
      ResearchClarification? asked;
      var turn = 0;

      final outcome = await SearchAgent(
        streamTurn: (req) {
          requests.add(req);
          turn++;
          if (turn == 1) return Stream.fromIterable([searchChunk('Mercury')]);
          return Stream.fromIterable([answerChunk('done')]);
        },
        search: (req) async => [hit('https://example.com')],
        deriveGoal: (_) async => goal,
        askClarification: (c) async {
          asked = c;
          expect(requests, isEmpty,
              reason: 'the question comes before any research turn');
          return ['The team'];
        },
        assessCoverage: (req) async {
          assessed.add(req);
          return const [];
        },
      ).run(history: history, listener: const SearchAgentListener());

      expect(asked, same(clarification));
      expect(outcome.content, 'done');
      // Every turn's brief says what the user meant.
      for (final req in requests) {
        expect(req.researchBrief,
            contains('The user clarified: Which Mercury? The team'));
      }
      // The gate judges against the clarified question, not the ambiguous
      // original — it has one ground truth, and the user just refined it.
      expect(assessed.single.objective, startsWith('What is Vietnam GDP?'));
      expect(assessed.single.objective, contains('The team'));
    });

    test('a skip proceeds on the goal alone', () async {
      final requests = <SearchAgentRequest>[];
      final outcome = await SearchAgent(
        streamTurn: (req) {
          requests.add(req);
          return Stream.fromIterable([answerChunk('done')]);
        },
        search: (req) async => [hit('https://example.com')],
        deriveGoal: (_) async => goal,
        askClarification: (_) async => const [],
      ).run(history: history, listener: const SearchAgentListener());

      expect(outcome.content, 'done');
      expect(requests.single.researchBrief,
          contains('Goal: Find the latest Mercury results'));
      expect(requests.single.researchBrief,
          isNot(contains('The user clarified')));
    });

    test('stopping the run while it waits ends it without a turn', () async {
      var turns = 0;
      final outcome = await SearchAgent(
        streamTurn: (req) {
          turns++;
          return Stream.fromIterable([answerChunk('never')]);
        },
        search: (req) async => [hit('https://example.com')],
        deriveGoal: (_) async => goal,
        askClarification: (_) async => null,
      ).run(history: history, listener: const SearchAgentListener());

      expect(outcome.cancelled, isTrue);
      expect(outcome.reason, SearchTerminationReason.cancelled);
      expect(turns, 0);
    });

    test('is not asked at all when nobody can answer, and survives a throw',
        () async {
      var asks = 0;
      final unasked = await SearchAgent(
        streamTurn: (req) => Stream.fromIterable([answerChunk('done')]),
        search: (req) async => [hit('https://example.com')],
        deriveGoal: (_) async => goal,
      ).run(history: history, listener: const SearchAgentListener());
      expect(unasked.content, 'done');

      final thrown = await SearchAgent(
        streamTurn: (req) => Stream.fromIterable([answerChunk('done')]),
        search: (req) async => [hit('https://example.com')],
        deriveGoal: (_) async => goal,
        askClarification: (_) async {
          asks++;
          throw StateError('card never mounted');
        },
      ).run(history: history, listener: const SearchAgentListener());
      expect(asks, 1);
      expect(thrown.content, 'done',
          reason: 'a failed question costs the run only the clarification');
    });
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

    // The rescue above is for a withdrawn turn that says NOTHING. A withdrawn
    // turn that answers and then asks to search anyway needs the opposite
    // treatment: the request carried no tools, so the call cannot run and the
    // prose is not a preamble to anything — it is the answer. _ingestChunk
    // gates its content discard on _TurnAccum.toolsEnabled for exactly this.
    test('a withdrawn turn that answers AND asks to search keeps its answer',
        () async {
      final requests = <SearchAgentRequest>[];
      var turn = 0;

      final outcome = await agent(
        maxSearches: 1,
        streamTurn: (req) {
          requests.add(req);
          turn++;
          if (turn == 1) {
            return Stream.fromIterable([searchChunk(distinctTopics[0])]);
          }
          return Stream.fromIterable([
            answerChunk('answer from what I have'),
            searchChunk(distinctTopics[1]),
          ]);
        },
      ).run(history: history, listener: const SearchAgentListener());

      expect(requests[1].toolsEnabled, isFalse,
          reason: 'the budget was spent on turn 1, so turn 2 carries no '
              'web_search tool and the call it emits anyway is guaranteed to '
              'be refused');
      expect(outcome.content, 'answer from what I have',
          reason: 'a refused call must not delete the prose that arrived '
              'with it — that prose is a finished answer being thrown away');
      expect(outcome.reason, SearchTerminationReason.hardCapReached);
      expect(turn, 2,
          reason: 'and no forced-answer retry is needed, because turn.content '
              'is no longer empty: the one-shot rescue stays unspent for the '
              'prose-free turn above');
    });

    test(
        'a withdrawn turn that asks to search BEFORE answering keeps its '
        'answer too', () async {
      var turn = 0;

      final outcome = await agent(
        maxSearches: 1,
        streamTurn: (req) {
          turn++;
          if (turn == 1) {
            return Stream.fromIterable([searchChunk(distinctTopics[0])]);
          }
          // The other order, which models emit interchangeably: the refused
          // call first, the answer after it.
          return Stream.fromIterable([
            searchChunk(distinctTopics[1]),
            answerChunk('answer from what I have'),
          ]);
        },
      ).run(history: history, listener: const SearchAgentListener());

      expect(outcome.content, 'answer from what I have',
          reason: 'the rule is order-independent: _ingestChunk\'s '
              '`accum.toolCalls.isEmpty` guard, which drops content arriving '
              'after a call, is gated on toolsEnabled as well');
      expect(turn, 2);
    });

    test('onResetContent is never fired by a refused tool call', () async {
      var resets = 0;
      var turn = 0;

      await agent(
        maxSearches: 1,
        streamTurn: (req) {
          turn++;
          if (turn == 1) {
            return Stream.fromIterable([searchChunk(distinctTopics[0])]);
          }
          return Stream.fromIterable([
            answerChunk('answer from what I have'),
            searchChunk(distinctTopics[1]),
          ]);
        },
      ).run(
        history: history,
        listener: SearchAgentListener(onResetContent: () => resets++),
      );

      expect(resets, 0,
          reason: 'ChatProvider wires onResetContent to '
              'streamingMessage!.content = \'\', so a reset here is the user '
              'watching a complete, cited answer render and then vanish. A '
              'call that can never run is no reason to blank the bubble.');
    });
  });

  group('the completeness gate', () {
    test('reopens research when the answer leaves part of the question open',
        () async {
      final requests = <SearchAgentRequest>[];
      final assessed = <CoverageRequest>[];
      var resets = 0;
      var turn = 0;

      final outcome = await agent(
        maxSearches: 10,
        streamTurn: (req) {
          requests.add(req);
          turn++;
          if (turn == 1) {
            return Stream.fromIterable([searchChunk('2026 NBA Finals winner')]);
          }
          // Answers two of three hops and stops while budget remains — the
          // exact observed failure.
          if (turn == 2) {
            return Stream.fromIterable([answerChunk('Knicks won, Brunson MVP')]);
          }
          if (turn == 3) {
            return Stream.fromIterable([searchChunk('Jalen Brunson college')]);
          }
          return Stream.fromIterable(
              [answerChunk('Knicks won, Brunson MVP, Villanova')]);
        },
        assessCoverage: (req) async {
          assessed.add(req);
          return ['which college the Finals MVP attended'];
        },
      ).run(
        history: history,
        listener: SearchAgentListener(onResetContent: () => resets++),
      );

      // The gate saw the real objective and the real drafted answer.
      expect(assessed, hasLength(1));
      expect(assessed.single.objective, 'What is Vietnam GDP?');
      expect(assessed.single.draftAnswer, 'Knicks won, Brunson MVP');

      // Research actually reopened: the turn after the gate had tools back.
      expect(requests[2].toolsEnabled, isTrue);
      final reopened = requests[2].transcript.last;
      expect(reopened.role, OllamaMessageRole.user);
      expect(reopened.content, contains('which college the Finals MVP attended'));

      // The discarded answer had already streamed to the UI.
      expect(resets, greaterThanOrEqualTo(1));

      expect(outcome.content, 'Knicks won, Brunson MVP, Villanova');
      expect(outcome.searchCount, 2);
    });

    test('publishes the gaps it opened before the corrective turn runs',
        () async {
      // The gaps become [ ] items the model is told to close right now.
      // Published only after the next search round, the panel the user is
      // watching lags the model by a round — and never shows them at all
      // if the model answers the gap notice without searching.
      final snapshots = <List<SubGoal>>[];
      final transcriptsSeen = <List<OllamaMessage>>[];
      var turn = 0;

      await agent(
        maxSearches: 10,
        streamTurn: (req) {
          transcriptsSeen.add(req.transcript);
          turn++;
          if (turn == 1) return Stream.fromIterable([searchChunk('topic')]);
          if (turn == 2) {
            return Stream.fromIterable([answerChunk('partial draft')]);
          }
          // Answers the gap notice straight away, without searching.
          return Stream.fromIterable([answerChunk('partial draft, plus more')]);
        },
        assessCoverage: (req) async => ['the part that was missing'],
      ).run(
        history: history,
        listener: SearchAgentListener(
          onLedgerUpdate: (objective, snapshot) => snapshots.add(snapshot),
        ),
      );

      expect(
        snapshots.last.map((g) => g.query),
        contains('the part that was missing'),
        reason: 'the gap reached the panel even though no search followed',
      );
      // The corrective turn's transcript copy of the ledger shows the gap
      // as open, in agreement with the brief and the gap notice.
      final ledgerCopy = transcriptsSeen[2]
          .where((m) => m.role == OllamaMessageRole.tool)
          .map((m) => m.content)
          .where((c) => c.contains('### Research ledger'));
      expect(ledgerCopy, hasLength(1));
      expect(ledgerCopy.single, contains('- [ ] "the part that was missing"'));
    });

    test('the corrective round can see the draft it was told to keep',
        () async {
      // The gap notice says "Keep everything you already established", and
      // `history` was snapshotted before the run, so unless the rejected
      // draft is put in the transcript that instruction points at text
      // present nowhere in the request — and the corrective turn
      // legitimately answers only the gap.
      final requests = <SearchAgentRequest>[];
      var turn = 0;

      await agent(
        maxSearches: 10,
        streamTurn: (req) {
          requests.add(req);
          turn++;
          if (turn == 1) {
            return Stream.fromIterable([searchChunk('2026 NBA Finals winner')]);
          }
          if (turn == 2) {
            return Stream.fromIterable([answerChunk('Knicks won, Brunson MVP')]);
          }
          if (turn == 3) {
            return Stream.fromIterable([searchChunk('Jalen Brunson college')]);
          }
          return Stream.fromIterable(
              [answerChunk('Knicks won, Brunson MVP, Villanova')]);
        },
        assessCoverage: (req) async => ['which college the Finals MVP attended'],
      ).run(history: history, listener: const SearchAgentListener());

      expect(
        requests[2].transcript.any((m) =>
            m.role == OllamaMessageRole.assistant &&
            m.content == 'Knicks won, Brunson MVP'),
        isTrue,
        reason: 'the draft the model is told to keep must be in its context',
      );
      // The gap notice still has to be the last thing the model reads.
      expect(requests[2].transcript.last.role, OllamaMessageRole.user);
    });

    test('a corrective turn that produces no prose falls back to the rejected draft',
        () async {
      var turn = 0;
      final outcome = await agent(
        maxSearches: 10,
        streamTurn: (req) {
          turn++;
          if (turn == 1) return Stream.fromIterable([searchChunk('topic')]);
          if (turn == 2) {
            return Stream.fromIterable([answerChunk('partial but real')]);
          }
          // Thinks and then says nothing at all — no content, no tool call.
          return Stream.fromIterable([answerChunk('', thinking: 'hmm')]);
        },
        assessCoverage: (req) async => ['a missing part'],
      ).run(history: history, listener: const SearchAgentListener());

      // The same "take what we have" rule the cancelled returns already
      // apply: a draft the gate rejected still beats a blank bubble.
      expect(outcome.content, 'partial but real');
    });

    test('does not block the corrective search it just asked for', () async {
      // The gate opens a sub-goal using the GAP'S OWN WORDING. The model
      // then phrases its corrective query naturally, which lands at 0.795
      // trigram similarity against that wording — over the 0.75 block
      // threshold. So the harness refused the exact search it had just
      // demanded, ended as `converged` with one search, and told the model
      // "That search found nothing new either" about a search that never
      // ran. That is the reported symptom, manufactured by the fix for it.
      final executed = <String>[];
      final skipped = <String>[];
      var turn = 0;

      final outcome = await agent(
        maxSearches: 10,
        streamTurn: (req) {
          turn++;
          if (turn == 1) {
            return Stream.fromIterable([searchChunk('2026 NBA Finals winner')]);
          }
          if (turn == 2) {
            return Stream.fromIterable([answerChunk('Knicks won, Brunson MVP')]);
          }
          if (turn == 3) {
            return Stream.fromIterable(
                [searchChunk('which college did Jalen Brunson attend')]);
          }
          return Stream.fromIterable([answerChunk('complete with Villanova')]);
        },
        assessCoverage: (req) async => ['which college Jalen Brunson attended'],
      ).run(
        history: history,
        listener: SearchAgentListener(
          onSearchStart: executed.add,
          onSearchSkipped: (q, r) => skipped.add(q),
        ),
      );

      expect(skipped, isEmpty,
          reason: 'the gate-opened sub-goal must not block its own follow-up');
      expect(executed, hasLength(2));
      expect(executed.last, 'which college did Jalen Brunson attend');
      expect(outcome.searchCount, 2);
    });

    test('accepts a complete answer after exactly one gate call', () async {
      var calls = 0;
      var turn = 0;
      final outcome = await agent(
        streamTurn: (req) {
          turn++;
          if (turn == 1) return Stream.fromIterable([searchChunk('topic')]);
          return Stream.fromIterable([answerChunk('complete answer')]);
        },
        assessCoverage: (req) async {
          calls++;
          return const [];
        },
      ).run(history: history, listener: const SearchAgentListener());

      expect(outcome.content, 'complete answer');
      expect(calls, 1);
      expect(turn, 2, reason: 'no corrective round should have run');
    });

    test('accepts the answer when the gate itself fails', () async {
      var turn = 0;
      final outcome = await agent(
        streamTurn: (req) {
          turn++;
          if (turn == 1) return Stream.fromIterable([searchChunk('topic')]);
          return Stream.fromIterable([answerChunk('answer worth keeping')]);
        },
        assessCoverage: (req) async => throw StateError('gate exploded'),
      ).run(history: history, listener: const SearchAgentListener());

      // Losing an answer we already have is strictly worse than shipping a
      // possibly-partial one.
      expect(outcome.content, 'answer worth keeping');
    });

    test('does not gate once the search budget is spent', () async {
      var calls = 0;
      var turn = 0;
      await agent(
        maxSearches: 1,
        streamTurn: (req) {
          turn++;
          if (turn == 1) return Stream.fromIterable([searchChunk('topic')]);
          return Stream.fromIterable([answerChunk('done')]);
        },
        assessCoverage: (req) async {
          calls++;
          return ['something missing'];
        },
      ).run(history: history, listener: const SearchAgentListener());

      // Asking what is missing is pointless when no search could run.
      expect(calls, 0);
    });

    test('does not gate an answer that required no research at all', () async {
      var calls = 0;
      final outcome = await agent(
        streamTurn: (req) =>
            Stream.fromIterable([answerChunk('2 + 2 is 4')]),
        assessCoverage: (req) async {
          calls++;
          return ['something missing'];
        },
      ).run(history: history, listener: const SearchAgentListener());

      expect(calls, 0, reason: 'an unresearched reply is not incomplete research');
      expect(outcome.content, '2 + 2 is 4');
    });

    test('does not gate a run the search backend blocked', () async {
      var calls = 0;
      var turn = 0;
      var searchCalls = 0;
      final outcome = await agent(
        maxSearches: 10,
        streamTurn: (req) {
          turn++;
          if (turn <= 2) {
            return Stream.fromIterable([searchChunk(distinctTopics[turn - 1])]);
          }
          return Stream.fromIterable([answerChunk('partial, sources blocked')]);
        },
        // One real search, THEN the block. Without that first success
        // searchCount stays 0 and the gate is blocked by the research
        // precondition instead — which is what this test is not about.
        // Mutation testing caught exactly that: dropping the canSearch
        // guard left this test passing.
        search: (req) async {
          searchCalls++;
          if (searchCalls == 1) return [hit('https://example.com/a')];
          throw const WebSearchUnavailableException('rate limited');
        },
        assessCoverage: (req) async {
          calls++;
          return ['something missing'];
        },
      ).run(history: history, listener: const SearchAgentListener());

      expect(outcome.searchCount, 1, reason: 'the research precondition is met');
      // Reopening research into an active block is exactly what 84f3b71
      // exists to prevent, so only canSearch can be what stops the gate.
      expect(calls, 0);
      expect(outcome.reason, SearchTerminationReason.searchUnavailable);
    });

    test('a cancel during the corrective round still returns the draft',
        () async {
      var cancelled = false;
      var turn = 0;
      final outcome = await agent(
        maxSearches: 10,
        streamTurn: (req) {
          turn++;
          if (turn == 1) return Stream.fromIterable([searchChunk('topic')]);
          if (turn == 2) {
            return Stream.fromIterable([answerChunk('partial but real')]);
          }
          // The user hits stop while the corrective round is under way.
          cancelled = true;
          return Stream.fromIterable([answerChunk('never delivered')]);
        },
        assessCoverage: (req) async => ['a missing part'],
      ).run(
        history: history,
        listener: const SearchAgentListener(),
        isCancelled: () => cancelled,
      );

      expect(outcome.cancelled, isTrue);
      // The gate rejected this draft, but a rejected draft beats a blank
      // message — the same lesson as dd4ed25. Discarding it because we had
      // hoped to improve it loses everything the run established.
      expect(outcome.content, 'partial but real',
          reason: 'cancelling mid-correction must not blank the answer');
    });

    test('gives up after maxCoverageChecks corrective rounds', () async {
      var calls = 0;
      var turn = 0;
      final outcome = await agent(
        maxSearches: 10,
        streamTurn: (req) {
          turn++;
          // Alternates search / answer, and the answer is never good enough.
          if (turn.isOdd) {
            return Stream.fromIterable(
                [searchChunk(distinctTopics[turn ~/ 2])]);
          }
          return Stream.fromIterable([answerChunk('still incomplete $turn')]);
        },
        assessCoverage: (req) async {
          calls++;
          return ['never satisfied'];
        },
      ).run(history: history, listener: const SearchAgentListener());

      // An unbounded gate is an infinite loop with extra steps.
      expect(calls, SearchAgent.defaultMaxCoverageChecks);
      expect(outcome.content, isNotEmpty);
    });
  });

  group('a throttled search backend', () {
    test('stops the run instead of counting as evidence of absence', () async {
      var turn = 0;
      var searchCalls = 0;
      final outcome = await agent(
        maxSearches: 10,
        streamTurn: (req) {
          turn++;
          if (turn <= 3) {
            return Stream.fromIterable([searchChunk(distinctTopics[turn - 1])]);
          }
          return Stream.fromIterable([answerChunk('partial answer')]);
        },
        search: (req) async {
          searchCalls++;
          if (searchCalls == 1) return [hit('https://example.com/a')];
          throw const WebSearchUnavailableException('rate limited');
        },
      ).run(history: history, listener: const SearchAgentListener());

      expect(outcome.reason, SearchTerminationReason.searchUnavailable);
      // The throttled attempt reached no search engine, so it is not
      // research and must not be billed as such.
      expect(outcome.searchCount, 1);
      expect(outcome.content, 'partial answer');
      // Round 1 searched, round 2 was throttled, and the run ends — it does
      // not spend the remaining 8 searches of budget hammering the block.
      expect(searchCalls, 2);
    });

    test('tells the model it was blocked, not that nothing was found',
        () async {
      final requests = <SearchAgentRequest>[];
      var turn = 0;
      await agent(
        streamTurn: (req) {
          requests.add(req);
          turn++;
          if (turn == 1) {
            return Stream.fromIterable([searchChunk('creatine 2026 opinions')]);
          }
          return Stream.fromIterable([answerChunk('done')]);
        },
        search: (req) async =>
            throw const WebSearchUnavailableException('rate limited'),
      ).run(history: history, listener: const SearchAgentListener());

      final notice = requests.last.transcript
          .where((m) => m.role == OllamaMessageRole.tool)
          .last;
      expect(notice.content, contains('NOT searched'));
      expect(notice.content, contains('Do not rephrase'));
      // The exact failure mode this fixes: the old text told the model "No
      // results found ... Try a different phrasing", which reads as evidence
      // the fact does not exist and invites more requests into the block.
      expect(notice.content, isNot(contains('No results found')));
      expect(notice.content, isNot(contains('Try a different phrasing')));
    });

    test('reports the block through onSearchSkipped', () async {
      final skips = <String>[];
      var turn = 0;
      await agent(
        streamTurn: (req) {
          turn++;
          if (turn == 1) return Stream.fromIterable([searchChunk('topic')]);
          return Stream.fromIterable([answerChunk('done')]);
        },
        search: (req) async =>
            throw const WebSearchUnavailableException('rate limited'),
      ).run(
        history: history,
        listener: SearchAgentListener(
          onSearchSkipped: (query, reason) => skips.add(reason),
        ),
      );

      expect(skips, hasLength(1));
      expect(skips.single, contains('rate-limiting'));
    });

    test('abandons the rest of the round rather than retrying each query',
        () async {
      final attempted = <String>[];
      var turn = 0;
      await agent(
        streamTurn: (req) {
          turn++;
          if (turn == 1) {
            return Stream.fromIterable([
              OllamaMessage(
                '',
                role: OllamaMessageRole.assistant,
                toolCalls: [
                  OllamaToolCall(
                      name: 'web_search', arguments: {'query': 'first topic'}),
                  OllamaToolCall(
                      name: 'web_search',
                      arguments: {'query': 'unrelated second topic'}),
                ],
              ),
            ]);
          }
          return Stream.fromIterable([answerChunk('done')]);
        },
        search: (req) async {
          attempted.add(req.query);
          throw const WebSearchUnavailableException('rate limited');
        },
      ).run(history: history, listener: const SearchAgentListener());

      // Both were planned; only the first is attempted. Every extra request
      // into an active block extends it.
      expect(attempted, ['first topic']);
    });

    test('a genuinely empty result set is still treated as a real search',
        () async {
      var turn = 0;
      final outcome = await agent(
        maxSearches: 10,
        streamTurn: (req) {
          turn++;
          if (turn <= 2) {
            return Stream.fromIterable([searchChunk(distinctTopics[turn - 1])]);
          }
          return Stream.fromIterable([answerChunk('done')]);
        },
        search: (req) async => <WebSearchResult>[],
      ).run(history: history, listener: const SearchAgentListener());

      // A request that reached the engine and came back empty is evidence of
      // absence, bills against the budget, and must NOT be reported as a
      // backend outage.
      expect(outcome.searchCount, 2);
      expect(outcome.reason, isNot(SearchTerminationReason.searchUnavailable));
    });
  });
}
