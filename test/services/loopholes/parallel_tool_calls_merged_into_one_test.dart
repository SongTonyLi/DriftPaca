/// Probe: OpenRouterToolCallAssembler collapses every `index`-less
/// tool_call delta onto slot 0, string-concatenating N complete JSON
/// argument objects into one call.
///
/// `OpenRouterToolCallAssembler.addDeltas` (openrouter_codec.dart:307-309)
/// keys each incoming fragment by `map['index']`, falling back to
/// `_calls.isEmpty ? 0 : max(_calls.keys)` when the provider sends no
/// index. That fallback is right for ONE call streamed as nameless
/// argument fragments — the case the class was written for — but for N
/// index-less calls it maps all of them onto the SAME slot.
/// `_AssemblingCall.addArguments` then does `argumentsJson += args`, so
/// two finished JSON objects become `{"query":"a"}{"query":"b"}`,
/// `OllamaToolCall.parseArguments` fails to jsonDecode that, and its
/// catch block (ollama_tool.dart:38-40) hands back
/// `{'query': <the raw concatenation>}`.
///
/// This is reachable, not hypothetical: `OpenRouterCodec.toolCallDeltas`
/// (line 228-231) deliberately prefers `choice['message']['tool_calls']`
/// over `choice['delta']['tool_calls']`, and the OpenAI-compatible
/// non-delta `message` schema carries no `index` field at all. And
/// `OllamaService._consumeOpenRouterSseLine` (ollama_service.dart:922-934)
/// computes `parseCompletion(json)` — which parses each array element
/// separately and gets BOTH calls right — and then throws that away in
/// favour of `assembler.build()`. The corrupt parse wins over the
/// correct one that the same function already computed.
///
/// The tests below walk the defect from the pure assembler, through
/// `OllamaService.chatStream`, into a real `SearchAgent` run: two
/// legitimate parallel searches become one junk DuckDuckGo query, billed
/// against the run's budget, with no skip event and no trace of the two
/// queries that were lost.
library;

import 'dart:convert';
import 'dart:math' as math;

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
/// `delta` tool_calls do — and `toolCallDeltas` reads `message` first.
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

const concatenated =
    '{"query":"population of Paris"}{"query":"population of Lyon"}';

void main() {
  group('the assembler merges index-less calls onto one slot', () {
    test('two index-less calls in one frame build as ONE junk call', () {
      final assembler = OpenRouterToolCallAssembler()
        ..addFromCompletionJson(messageShapedFrame());
      final built = assembler.build();

      expect(built, hasLength(1),
          reason: 'the model asked for two parallel searches and the '
              'assembler produced ${built.length} — the second call was '
              'merged into the first because neither carried an `index`, so '
              'the fallback key `_calls.keys.reduce(max)` resolved to slot 0 '
              'for both');
      expect(built.single.arguments['query'], concatenated,
          reason: 'both argument objects were string-concatenated by '
              '_AssemblingCall.addArguments; jsonDecode of the result throws '
              'and OllamaToolCall.parseArguments returns {query: <raw>}, so '
              'the literal JSON text is now the search query');
    });

    test('the same frame parses correctly through parseCompletion', () {
      // The point: this is not a malformed frame the harness is entitled
      // to mangle. The codec's OTHER path on the IDENTICAL bytes gets
      // both calls right, which is what makes the assembler's result a
      // regression rather than a limitation of the input.
      final parsed = OpenRouterCodec.parseCompletion(messageShapedFrame());

      expect(parsed.toolCalls, hasLength(2),
          reason: '_parseToolCalls walks the array element by element and '
              'never needs `index`, so it recovers both calls from the very '
              'frame the assembler collapsed');
      expect(
        parsed.toolCalls!.map((c) => c.arguments['query']).toList(),
        ['population of Paris', 'population of Lyon'],
        reason: 'the correct reading of this frame — two clean queries',
      );
    });

    test('index-less DELTA-shaped calls collapse the same way', () {
      // Not limited to the `message` shape: any provider (or proxy) that
      // streams delta tool_calls without the optional `index` field hits
      // the identical fallback.
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
      expect(built, hasLength(1),
          reason: 'delta-shaped calls without `index` collapse too');
      expect(built.single.arguments['query'], '{"query":"one"}{"query":"two"}',
          reason: 'same concatenation, same junk query');
    });

    test('WITH index the exact same two calls survive — this is the delta',
        () {
      // Control. Adding the one field the frames above omit fixes
      // everything, which pins the cause on the index fallback and not on
      // anything else in the pipeline.
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
      expect(built, hasLength(2),
          reason: 'the ONLY difference from the failing cases is the presence '
              'of `index`');
      expect(built.map((c) => c.arguments['query']).toList(),
          ['population of Paris', 'population of Lyon']);
    });

    test('the fallback is max(keys), so it also lands on the WRONG open slot',
        () {
      // A frame that mixes an indexed call with a later index-less
      // argument fragment: the fragment is appended to the HIGHEST index
      // seen so far rather than to the call it belongs to.
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
        // A continuation for call 0 that lost its index in transit.
        ..addDeltas([
          {
            'function': {'arguments': 'XX'},
          },
        ]);

      final built = assembler.build();
      final maxKey = [0, 1].reduce(math.max);
      expect(built[maxKey].arguments['query'], contains('XX'),
          reason: 'the index-less fragment was appended to the highest slot '
              '($maxKey), corrupting a call it may not belong to');
      expect(built[0].arguments['query'], 'a',
          reason: 'while the call it plausibly continued was left untouched');
    });
  });

  group('the collapse survives the real OllamaService stream', () {
    test('chatStream yields one junk tool call where the codec sees two',
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

      // What the same function already computed from the same bytes, and
      // then discarded.
      final correct = OpenRouterCodec.parseSseLine(line)!.toolCalls!;
      expect(correct, hasLength(2),
          reason: 'parseSseLine on the exact line the stream carried '
              'recovers both searches');

      expect(delivered, hasLength(1),
          reason: '_consumeOpenRouterSseLine overrides message.toolCalls with '
              'assembler.build(), so the consumer receives '
              '${delivered.length} call(s) instead of 2 — the corrupt parse '
              'wins over the correct one');
      expect(delivered.single.arguments['query'], concatenated,
          reason: 'and the surviving call\'s query is the raw JSON '
              'concatenation, not either query the model asked for');
    });
  });

  group('the junk query is executed as real research', () {
    test('SearchAgent fires the concatenated JSON at the search backend',
        () async {
      // The tool call is not hand-written here: it is whatever the
      // assembler actually produces from the frame above, so this round
      // is exactly what the transport would hand the loop.
      final corrupted = (OpenRouterToolCallAssembler()
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
                role: OllamaMessageRole.assistant, toolCalls: corrupted);
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

      expect(executed, [concatenated],
          reason: 'the loop billed one search against maxSearches and sent '
              'the literal string $concatenated to the search backend; '
              'neither "population of Paris" nor "population of Lyon" was '
              'ever searched');
      expect(executed, isNot(contains('population of Paris')));
      expect(executed, isNot(contains('population of Lyon')),
          reason: 'neither query was ever issued in its own right — only the '
              'single glued-together string was');

      expect(skipped, isEmpty,
          reason: 'and nothing was reported as skipped — two legitimate '
              'searches vanished with no onSearchSkipped callback, so the UI '
              'and the transcript both show a normal, productive round');

      final subGoalTexts = [
        for (final snapshot in ledgers)
          for (final goal in snapshot) goal.query,
      ];
      expect(subGoalTexts, contains(concatenated),
          reason: 'the junk string was upserted as a research sub-goal, so '
              'the ledger the model reads back — and the checklist the '
              'stopping rule is evaluated against — now claims this is what '
              'was researched');
      expect(subGoalTexts, isNot(contains('population of Lyon')),
          reason: 'and "population of Lyon" exists nowhere in the ledger as a '
              'sub-goal of its own, so nothing downstream — not the '
              'checklist, not the stall detector, not the coverage gate — '
              'can notice it was dropped');
      expect(subGoalTexts, hasLength(1),
          reason: 'two requested lookups produced exactly one ledger entry');
    });
  });
}
