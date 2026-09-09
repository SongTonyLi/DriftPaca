/// Guard: OpenRouterToolCallAssembler keeps parallel tool calls apart even
/// when the provider sends no `index`.
///
/// The assembler used to have exactly one notion of call identity — the
/// OpenAI streaming `index` — and one fallback for its absence: append to
/// `max(_calls.keys)`. That fallback is right for ONE call streamed as
/// nameless argument fragments (the shape the class was written for) and
/// wrong for any entry announcing a NEW call, so N index-less calls all
/// landed on slot 0 and `_AssemblingCall.addArguments` glued their JSON
/// into `{"query":"a"}{"query":"b"}`. That decoded as nothing, so
/// `OllamaToolCall.parseArguments` handed the raw text back as the search
/// query: one junk DuckDuckGo request, billed against the run's budget,
/// filed in the research ledger as a sub-goal that had been researched,
/// with no skip event and no trace of the two queries that were lost.
///
/// Three changes close it, and this file walks all three from the pure
/// assembler, through `OllamaService.chatStream`, into a real
/// `SearchAgent` run:
///
///  1. `OpenRouterToolCallAssembler._slotFor` (openrouter_codec.dart:394)
///     routes each entry by `index`, then by `id` — every
///     OpenAI-compatible tool call carries one and it is unique per call —
///     and only then by "the call currently being streamed", which is now
///     limited to a fragment that cannot be announcing a new call. Two
///     entries of one `tool_calls` array are two calls and never merge.
///  2. `OpenRouterCodec.toolCallPayload` (openrouter_codec.dart:231) tells
///     the assembler WHICH branch supplied the list. A non-delta `message`
///     payload is a set of FINISHED calls, not fragments — it carries no
///     `index` at all — so it replaces the assembler's state instead of
///     being appended to it (openrouter_codec.dart:352).
///  3. Arguments that open like JSON and do not decode yield NO query
///     (ollama_tool.dart:53), so a call the transport could not reassemble
///     is skipped visibly through `onSearchSkipped` rather than searched
///     literally.
///
/// `OllamaService._consumeOpenRouterSseLine` (ollama_service.dart:924) is
/// deliberately untouched: on a genuine delta stream the finish frame
/// carries at most the last argument fragment, so `parseCompletion` alone
/// would yield a truncated call. The assembler stays the single source of
/// truth — it is now correct, and the codec's two readings of the same
/// frame agree.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Services/ollama_service.dart';
import 'package:llamaseek/Services/openrouter_codec.dart';
import 'package:llamaseek/Services/search_agent.dart';
import 'package:llamaseek/Services/web_search_service.dart';

/// One SSE frame shaped like an OpenAI-compatible NON-delta `message`
/// payload carrying two parallel `web_search` calls. Note what is absent:
/// `index`. The `message` schema has no such field — only streamed
/// `delta` tool_calls do — and `toolCallPayload` reads `message` first.
Map<String, dynamic> messageShapedFrame() => {
      'model': 'openai/gpt-4o-mini',
      'choices': [
        {
          'message': {
            'role': 'assistant',
            'content': '',
            'tool_calls': [
              {
                'id': 'call_a',
                'type': 'function',
                'function': {
                  'name': 'web_search',
                  'arguments': '{"query":"population of Paris"}',
                },
              },
              {
                'id': 'call_b',
                'type': 'function',
                'function': {
                  'name': 'web_search',
                  'arguments': '{"query":"population of Lyon"}',
                },
              },
            ],
          },
          'finish_reason': 'tool_calls',
        },
      ],
    };

/// What the two calls' arguments used to be glued into. Every assertion
/// below that mentions it says it must appear NOWHERE.
const concatenated =
    '{"query":"population of Paris"}{"query":"population of Lyon"}';

List<String?> queriesOf(List<OllamaToolCall> calls) =>
    [for (final call in calls) call.arguments['query'] as String?];

void main() {
  group('the assembler keeps index-less calls apart', () {
    test('two index-less calls in one frame build as TWO calls', () {
      final assembler = OpenRouterToolCallAssembler()
        ..addFromCompletionJson(messageShapedFrame());
      final built = assembler.build();

      expect(built, hasLength(2),
          reason: 'the model asked for two parallel searches; neither entry '
              'of a `message.tool_calls` array carries an `index`, so they '
              'are told apart by their ids (call_a, call_b) instead of '
              'stacking onto one slot');
      expect(queriesOf(built), ['population of Paris', 'population of Lyon'],
          reason: 'each call keeps its own argument JSON — argument strings '
              'are never concatenated across calls');
      expect(queriesOf(built), isNot(contains(concatenated)));
    });

    test('the same frame parses correctly through parseCompletion', () {
      // The two readings the codec has of one frame must agree. They did
      // not: _parseToolCalls walks the array element by element and never
      // needs `index`, so it always recovered both calls from the very
      // frame the assembler collapsed.
      final parsed = OpenRouterCodec.parseCompletion(messageShapedFrame());

      expect(parsed.toolCalls, hasLength(2),
          reason: '_parseToolCalls walks the array element by element and '
              'never needs `index`');
      expect(queriesOf(parsed.toolCalls!),
          ['population of Paris', 'population of Lyon'],
          reason: 'the correct reading of this frame — two clean queries');

      final built = (OpenRouterToolCallAssembler()
            ..addFromCompletionJson(messageShapedFrame()))
          .build();
      expect(queriesOf(built), queriesOf(parsed.toolCalls!),
          reason: 'and the assembler, which is what the transport actually '
              'delivers, now reads the identical bytes the identical way');
    });

    test('index-less DELTA-shaped calls stay separate', () {
      // Not limited to the `message` shape: any provider (or proxy) that
      // streams delta tool_calls without the optional `index` field used
      // to hit the identical fallback. `id` separates them.
      final assembler = OpenRouterToolCallAssembler()
        ..addDeltas([
          {
            'id': 'call_a',
            'function': {'name': 'web_search', 'arguments': '{"query":"one"}'},
          },
          {
            'id': 'call_b',
            'function': {'name': 'web_search', 'arguments': '{"query":"two"}'},
          },
        ]);

      final built = assembler.build();
      expect(built, hasLength(2),
          reason: 'two distinct ids in one delta array are two distinct '
              'calls, index or no index');
      expect(queriesOf(built), ['one', 'two'],
          reason: 'no concatenation, no junk query');
    });

    test('WITH index the exact same two calls survive — the control', () {
      // The mainstream OpenRouter shape. It went through the first clause
      // of _slotFor before the fix and still does: this test is here to
      // prove the fix did not move the path that was always correct.
      final assembler = OpenRouterToolCallAssembler()
        ..addDeltas([
          {
            'index': 0,
            'function': {
              'name': 'web_search',
              'arguments': '{"query":"population of Paris"}',
            },
          },
          {
            'index': 1,
            'function': {
              'name': 'web_search',
              'arguments': '{"query":"population of Lyon"}',
            },
          },
        ]);

      final built = assembler.build();
      expect(built, hasLength(2));
      expect(queriesOf(built), ['population of Paris', 'population of Lyon']);
    });

    test('an index-less nameless fragment continues the call being streamed',
        () {
      // The one case where neither identity is available: an argument
      // fragment with no index, no id and no name. There is no way to know
      // which call it belongs to, and continuing the call currently being
      // streamed is the documented contract — it is the shape the class
      // was written for — not a defect. It must not, however, be read as
      // the announcement of a new call.
      final assembler = OpenRouterToolCallAssembler()
        ..addDeltas([
          {
            'index': 0,
            'function': {'name': 'web_search', 'arguments': '{"query":"a"}'},
          },
          {
            'index': 1,
            'function': {'name': 'web_search', 'arguments': '{"query":"b'},
          },
        ])
        // A continuation of call 1 that lost its index in transit.
        ..addDeltas([
          {
            'function': {'arguments': 'c"}'},
          },
        ]);

      final built = assembler.build();
      expect(built, hasLength(2),
          reason: 'a nameless fragment continues a call, it never opens one');
      expect(queriesOf(built), ['a', 'bc'],
          reason: 'the fragment completed the call that was still open, and '
              'the finished call before it was left alone');
    });

    test('a stray fragment corrupts no call but the one it lands on', () {
      // The same shape, but the fragment is not valid JSON for the call it
      // continues. The damage is contained to that call, and that call
      // reports NO query rather than a plausible-looking junk one, so the
      // loop skips it visibly instead of searching it.
      final assembler = OpenRouterToolCallAssembler()
        ..addDeltas([
          {
            'index': 0,
            'function': {'name': 'web_search', 'arguments': '{"query":"a"}'},
          },
          {
            'index': 1,
            'function': {'name': 'web_search', 'arguments': '{"query":"b"}'},
          },
        ])
        ..addDeltas([
          {
            'function': {'arguments': 'XX'},
          },
        ]);

      final built = assembler.build();
      expect(built[0].arguments['query'], 'a',
          reason: 'the call that was already finished is untouched');
      expect(OllamaToolCall.searchQuery(built[1].arguments), isEmpty,
          reason: '`{"query":"b"}XX` does not decode, and JSON-shaped text '
              'that does not decode is corrupt arguments — not a query to '
              'send to a search engine');
    });

    test('a single call streamed with no index at all still builds as ONE',
        () {
      // The regression this class exists for (commit d3f12c6): name and id
      // in the first chunk, arguments dribbling in as nameless fragments.
      // Splitting these apart would empty every web_search query.
      const full = '{"query":"population of Paris"}';
      final assembler = OpenRouterToolCallAssembler()
        ..addDeltas([
          {
            'id': 'call_a',
            'function': {'name': 'web_search', 'arguments': ''},
          },
        ])
        ..addDeltas([
          {
            'function': {'arguments': full.substring(0, 12)},
          },
        ])
        ..addDeltas([
          {
            'function': {'arguments': full.substring(12)},
          },
        ]);

      final built = assembler.build();
      expect(built, hasLength(1),
          reason: 'three fragments of one call are one call — the fix routes '
              'by identity, it does not split on every entry');
      expect(built.single.arguments['query'], 'population of Paris');
    });

    test('a repeated complete message frame does not double its arguments',
        () {
      // A proxy that streams a whole message — or a growing snapshot of
      // one — re-sends calls it has already sent. Finished calls replace
      // the assembler's state; appending them would concatenate each
      // call's arguments with a copy of itself.
      final assembler = OpenRouterToolCallAssembler()
        ..addFromCompletionJson(messageShapedFrame())
        ..addFromCompletionJson(messageShapedFrame());

      final built = assembler.build();
      expect(built, hasLength(2),
          reason: 'the second frame describes the same two calls, not two '
              'more');
      expect(queriesOf(built), ['population of Paris', 'population of Lyon'],
          reason: 'and neither query is doubled');
      expect(queriesOf(built), isNot(contains(concatenated)));
    });
  });

  group('parallel calls survive the real OllamaService stream', () {
    test('chatStream yields both tool calls, exactly as the codec reads them',
        () async {
      final line = 'data: ${jsonEncode(messageShapedFrame())}';
      final client = MockClient((request) async => http.Response(
            '$line\n\ndata: [DONE]\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          ));

      final service = OllamaService(client: client)
        ..isOpenRouterMode = true
        ..apiKey = 'or-key';

      final delivered = <OllamaToolCall>[];
      await for (final message in service.chatStream(
        [
          OllamaMessage('Populations of Paris and Lyon?',
              role: OllamaMessageRole.user)
        ],
        chat: OllamaChat(model: 'openai/gpt-4o-mini'),
        tools: const [OllamaToolDefinition.webSearch],
      )) {
        if (message.toolCalls != null) delivered.addAll(message.toolCalls!);
      }

      expect(delivered, hasLength(2),
          reason: '_consumeOpenRouterSseLine hands the consumer '
              'assembler.build(), so what the assembler assembles is what '
              'the research loop actually receives');
      expect(queriesOf(delivered),
          ['population of Paris', 'population of Lyon'],
          reason: 'both searches the model asked for arrive intact');
      expect(queriesOf(delivered), isNot(contains(concatenated)));

      // The codec's other reading of the exact line the stream carried.
      // The transport and the codec must agree; they did not, and the
      // corrupt reading was the one that won.
      final parsed = OpenRouterCodec.parseSseLine(line)!.toolCalls!;
      expect([for (final c in delivered) '${c.name}:${c.arguments['query']}'],
          [for (final c in parsed) '${c.name}:${c.arguments['query']}'],
          reason: 'same bytes, same calls, whichever path reads them');
    });
  });

  group('both parallel searches are executed as real research', () {
    test('SearchAgent runs each query the model asked for', () async {
      // The tool calls are not hand-written here: they are whatever the
      // assembler actually produces from the frame above, so this round is
      // exactly what the transport would hand the loop.
      final calls = (OpenRouterToolCallAssembler()
            ..addFromCompletionJson(messageShapedFrame()))
          .build();

      final executed = <String>[];
      final skipped = <String>[];
      final ledgers = <List<SubGoal>>[];
      var turn = 0;

      final agent = SearchAgent(
        streamTurn: (request) async* {
          if (turn++ == 0) {
            yield OllamaMessage('',
                role: OllamaMessageRole.assistant, toolCalls: calls);
          } else {
            yield OllamaMessage('Here is the answer.',
                role: OllamaMessageRole.assistant);
          }
        },
        search: (request) async {
          executed.add(request.query);
          return [
            WebSearchResult(
              title: 'Some page',
              snippet: 'unrelated text',
              url: 'https://example.invalid/whatever',
              chunks: const ['unrelated text'],
            ),
          ];
        },
      );

      await agent.run(
        history: [
          OllamaMessage('What are the populations of Paris and Lyon?',
              role: OllamaMessageRole.user),
        ],
        listener: SearchAgentListener(
          onSearchSkipped: (query, reason) => skipped.add('$query :: $reason'),
          onLedgerUpdate: (_, snapshot) => ledgers.add(snapshot),
        ),
      );

      expect(executed, ['population of Paris', 'population of Lyon'],
          reason: 'both lookups reach the search backend, in the order the '
              'model asked for them — the default roundBatchCap is 2, so a '
              'pair of parallel calls runs in one round');
      expect(executed, isNot(contains(concatenated)),
          reason: 'the glued-together JSON text is never sent to a search '
              'engine, because it is never built');

      expect(skipped, isEmpty,
          reason: 'nothing was refused: two legitimate searches ran as two '
              'legitimate searches');

      final subGoalTexts = [
        for (final snapshot in ledgers)
          for (final goal in snapshot) goal.query,
      ];
      expect(subGoalTexts, contains('population of Paris'),
          reason: 'the ledger the model reads back records a real query, so '
              'the checklist and the stall detector are reasoning about '
              'research that actually happened');
      expect(subGoalTexts, isNot(contains(concatenated)),
          reason: 'and no junk string is filed as a sub-goal that has "been '
              'researched"');
      // Deliberately NOT asserting a separate 'population of Lyon' sub-goal:
      // trigramJaccard('population of Paris', 'population of Lyon') is 0.571,
      // above ResearchLedger._groupingThreshold (0.40), so the two queries
      // group onto one sub-goal. Both searches run and both sets of evidence
      // are recorded against it; whether that grouping is too eager is audit
      // finding 6's subject, not this one.
    });
  });
}
