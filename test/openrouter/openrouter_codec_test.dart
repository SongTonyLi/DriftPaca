import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Services/openrouter_codec.dart';

void main() {
  group('OpenRouterCodec.toOpenAiMessages', () {
    test('keeps plain text messages and drops empty image lists', () {
      final out = OpenRouterCodec.toOpenAiMessages([
        {'role': 'system', 'content': 'Be brief'},
        {'role': 'user', 'content': 'Hi', 'images': <String>[]},
      ]);

      expect(out, [
        {'role': 'system', 'content': 'Be brief'},
        {'role': 'user', 'content': 'Hi'},
      ]);
    });

    test('converts Ollama base64 images to OpenAI image_url parts', () {
      final out = OpenRouterCodec.toOpenAiMessages([
        {
          'role': 'user',
          'content': 'What is this?',
          'images': ['abc123'],
        },
      ]);

      expect(out.single['role'], 'user');
      final content = out.single['content'] as List;
      expect(content, [
        {'type': 'text', 'text': 'What is this?'},
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/jpeg;base64,abc123'},
        },
      ]);
    });

    test('maps Ollama tool_calls into OpenAI function tool_calls', () {
      final out = OpenRouterCodec.toOpenAiMessages([
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'function': {
                'name': 'web_search',
                'arguments': {'query': 'flutter streams'},
              },
            },
          ],
        },
        {
          'role': 'tool',
          'content': 'results',
          'tool_name': 'web_search',
        },
      ]);

      final assistant = out[0];
      expect(assistant['tool_calls'], isA<List>());
      final call = (assistant['tool_calls'] as List).single as Map;
      expect(call['type'], 'function');
      expect(call['function']['name'], 'web_search');
      expect(call['function']['arguments'], '{"query":"flutter streams"}');

      expect(out[1]['role'], 'tool');
      expect(out[1]['content'], 'results');
    });

    test('every tool message answers the id of the call it follows', () {
      // Ollama tool calls carry no id, so both sides are minted here — and
      // an OpenAI-compatible provider rejects the whole request when a tool
      // message's tool_call_id answers no call in the preceding assistant
      // message. Minted independently they never matched.
      final out = OpenRouterCodec.toOpenAiMessages([
        {'role': 'user', 'content': 'compare two things'},
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'function': {
                'name': 'web_search',
                'arguments': {'query': 'one'},
              },
            },
            {
              'function': {
                'name': 'web_search',
                'arguments': {'query': 'two'},
              },
            },
          ],
        },
        {'role': 'tool', 'content': 'r1', 'tool_name': 'web_search'},
        {'role': 'tool', 'content': 'r2', 'tool_name': 'web_search'},
        // A second round, whose ids must not collide with the first's.
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'function': {
                'name': 'web_search',
                'arguments': {'query': 'three'},
              },
            },
          ],
        },
        {'role': 'tool', 'content': 'r3', 'tool_name': 'web_search'},
      ]);

      List<String> callIds(Map<String, dynamic> assistant) => [
            for (final c in assistant['tool_calls'] as List)
              (c as Map)['id'] as String,
          ];

      final round1 = callIds(out[1]);
      expect(round1, hasLength(2));
      expect(out[2]['tool_call_id'], round1[0]);
      expect(out[3]['tool_call_id'], round1[1]);

      final round2 = callIds(out[4]);
      expect(out[5]['tool_call_id'], round2.single);
      expect({...round1, ...round2}, hasLength(3),
          reason: 'ids stay unique across the whole conversation');
    });

    test('keeps a provider-supplied tool call id verbatim', () {
      final out = OpenRouterCodec.toOpenAiMessages([
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': 'call_abc',
              'function': {
                'name': 'web_search',
                'arguments': {'query': 'x'},
              },
            },
          ],
        },
        {'role': 'tool', 'content': 'r', 'tool_name': 'web_search'},
      ]);

      expect((out[0]['tool_calls'] as List).single['id'], 'call_abc');
      expect(out[1]['tool_call_id'], 'call_abc');
    });
  });

  group('OpenRouterCodec.parseSseLine', () {
    test('parses a content delta into an incremental OllamaMessage', () {
      final message = OpenRouterCodec.parseSseLine(
        'data: {"id":"gen-1","model":"openai/gpt-4o","choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}',
      );
      expect(message, isNotNull);
      expect(message!.content, 'Hello');
      expect(message.role, OllamaMessageRole.assistant);
      expect(message.model, 'openai/gpt-4o');
      expect(message.done, isFalse);
    });

    test('maps reasoning deltas onto thinking', () {
      final message = OpenRouterCodec.parseSseLine(
        'data: {"choices":[{"delta":{"reasoning":"step 1"}}]}',
      );
      expect(message!.thinking, 'step 1');
      expect(message.content, isEmpty);
    });

    test('returns null for [DONE] and keep-alives', () {
      expect(OpenRouterCodec.parseSseLine('data: [DONE]'), isNull);
      expect(OpenRouterCodec.parseSseLine(': ping'), isNull);
      expect(OpenRouterCodec.parseSseLine(''), isNull);
    });

    test('recognizes the terminator, and only the terminator', () {
      // A reader that stops here stops at the end of the response instead
      // of at the end of the socket — see isStreamTerminator.
      expect(OpenRouterCodec.isStreamTerminator('data: [DONE]'), isTrue);
      expect(OpenRouterCodec.isStreamTerminator('data:[DONE]'), isTrue);
      expect(OpenRouterCodec.isStreamTerminator('data: [DONE]\r'), isTrue);
      expect(OpenRouterCodec.isStreamTerminator(': ping'), isFalse);
      expect(OpenRouterCodec.isStreamTerminator(''), isFalse);
      expect(
        OpenRouterCodec.isStreamTerminator(
            'data: {"choices":[{"delta":{"content":"[DONE]"}}]}'),
        isFalse,
        reason: 'a model may well write the word in its own answer',
      );
    });

    test('emits tool calls when finish_reason is tool_calls', () {
      final message = OpenRouterCodec.parseSseLine(
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"web_search","arguments":"{\\"query\\":\\"x\\"}"}}]},"finish_reason":"tool_calls"}]}',
      );
      expect(message!.toolCalls, isNotNull);
      expect(message.toolCalls!.single.name, 'web_search');
      expect(message.toolCalls!.single.arguments['query'], 'x');
      expect(message.done, isTrue);
    });
  });

  group('OpenRouterCodec.parseCompletion', () {
    test('reads a non-stream chat completion', () {
      final message = OpenRouterCodec.parseCompletion({
        'model': 'anthropic/claude-sonnet-4',
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': 'Hi there',
              'reasoning': 'thought',
            },
            'finish_reason': 'stop',
          },
        ],
      });
      expect(message.content, 'Hi there');
      expect(message.thinking, 'thought');
      expect(message.model, 'anthropic/claude-sonnet-4');
      expect(message.done, isTrue);
    });
  });

  group('OpenRouterCodec.chatBody', () {
    test('includes OpenAI-compatible fields and omits Ollama options', () {
      final body = OpenRouterCodec.chatBody(
        model: 'openai/gpt-4o',
        messages: [
          {'role': 'user', 'content': 'Hi'},
        ],
        stream: true,
        temperature: 0.4,
        tools: [
          {
            'type': 'function',
            'function': {
              'name': 'web_search',
              'description': 'Search',
              'parameters': {
                'type': 'object',
                'properties': {
                  'query': {'type': 'string'},
                },
              },
            },
          },
        ],
      );

      expect(body['model'], 'openai/gpt-4o');
      expect(body['stream'], isTrue);
      expect(body['temperature'], 0.4);
      expect(body.containsKey('options'), isFalse);
      expect(body['tools'], isNotEmpty);
    });
  });

  group('OpenRouterToolCallAssembler', () {
    test('assembles streamed tool-call argument fragments by index', () {
      const full = '{"query":"current weather Bellevue WA"}';
      final assembler = OpenRouterToolCallAssembler();
      assembler.addDeltas([
        {
          'index': 0,
          'id': 'call_1',
          'function': {'name': 'web_search', 'arguments': ''},
        },
      ]);
      assembler.addDeltas([
        {
          'index': 0,
          'function': {'arguments': full.substring(0, 10)},
        },
      ]);
      assembler.addDeltas([
        {
          'index': 0,
          'function': {'arguments': full.substring(10)},
        },
      ]);

      final calls = assembler.build();
      expect(calls, hasLength(1));
      expect(calls.single.name, 'web_search');
      expect(calls.single.arguments['query'], 'current weather Bellevue WA');
    });

    test('keeps two parallel tool calls on separate indexes', () {
      final assembler = OpenRouterToolCallAssembler();
      assembler.addDeltas([
        {
          'index': 0,
          'function': {'name': 'web_search', 'arguments': '{"query":"one"}'},
        },
        {
          'index': 1,
          'function': {'name': 'web_search', 'arguments': '{"query":"two"}'},
        },
      ]);

      expect(
        assembler.build().map((c) => c.arguments['query']),
        ['one', 'two'],
      );
    });

    test('reads Gemini-style args.q as the search query', () {
      final assembler = OpenRouterToolCallAssembler();
      assembler.addDeltas([
        {
          'index': 0,
          'function': {
            'name': 'web_search',
            'args': {'q': 'Bellevue WA weather'},
          },
        },
      ]);

      expect(assembler.build().single.arguments['query'], 'Bellevue WA weather');
    });

    test('treats a bare argument string as the query', () {
      final assembler = OpenRouterToolCallAssembler();
      assembler.addDeltas([
        {
          'index': 0,
          'function': {
            'name': 'web_search',
            'arguments': 'current weather Bellevue WA',
          },
        },
      ]);

      expect(
        assembler.build().single.arguments['query'],
        'current weather Bellevue WA',
      );
    });

    // The tests below pin the identity rules the assembler falls back on
    // when a provider omits `index`. It used to have only one — append to
    // the highest slot seen so far — which merged every parallel call onto
    // slot 0 and concatenated their argument JSON into one junk query
    // (audit finding #11).

    test('index-less calls are separated by id', () {
      final assembler = OpenRouterToolCallAssembler();
      assembler.addDeltas([
        {
          'id': 'call_a',
          'function': {'name': 'web_search', 'arguments': '{"query":"one"}'},
        },
        {
          'id': 'call_b',
          'function': {'name': 'web_search', 'arguments': '{"query":"two"}'},
        },
      ]);

      expect(
        assembler.build().map((c) => c.arguments['query']),
        ['one', 'two'],
        reason: 'an unseen id announces a NEW call, so two parallel calls '
            'stay two calls even with no `index` to key them by',
      );
    });

    test('fragments of one index-less call are joined by id', () {
      const full = '{"query":"current weather Bellevue WA"}';
      final assembler = OpenRouterToolCallAssembler();
      assembler.addDeltas([
        {
          'id': 'call_1',
          'function': {'name': 'web_search', 'arguments': ''},
        },
      ]);
      assembler.addDeltas([
        {
          'id': 'call_1',
          'function': {'arguments': full.substring(0, 10)},
        },
      ]);
      assembler.addDeltas([
        {
          'id': 'call_1',
          'function': {'arguments': full.substring(10)},
        },
      ]);

      final calls = assembler.build();
      expect(calls, hasLength(1),
          reason: 'a repeated id is the SAME call, so its fragments rejoin '
              'rather than opening a call per chunk');
      expect(calls.single.arguments['query'], 'current weather Bellevue WA');
    });

    test('a nameless argument fragment continues the call being streamed',
        () {
      // Neither `index` nor `id` anywhere: the only defensible target for
      // a nameless fragment is the call currently being streamed, which is
      // the shape this class was written for.
      final assembler = OpenRouterToolCallAssembler();
      assembler.addDeltas([
        {
          'name': 'web_search',
          'arguments': '{"query":"a',
        },
      ]);
      assembler.addDeltas([
        {'arguments': 'bc"}'},
      ]);

      final calls = assembler.build();
      expect(calls, hasLength(1));
      expect(calls.single.arguments['query'], 'abc');
    });

    test('a named entry starts a new call once the previous one is finished',
        () {
      // Same absence of identity, but this entry names a function and the
      // open call already decodes — it is an announcement, not a
      // continuation, and merging the two would glue their arguments.
      final assembler = OpenRouterToolCallAssembler();
      assembler.addDeltas([
        {
          'name': 'web_search',
          'arguments': '{"query":"a"}',
        },
      ]);
      assembler.addDeltas([
        {
          'name': 'web_search',
          'arguments': '{"query":"b"}',
        },
      ]);

      expect(
        assembler.build().map((c) => c.arguments['query']),
        ['a', 'b'],
      );
    });

    test('a complete message payload replaces accumulated fragments', () {
      // A `message.tool_calls` array is finished calls, not fragments — the
      // shape a proxy that streams a whole message (or a growing snapshot
      // of one) sends. Appending it to what the deltas already hold would
      // concatenate each call's arguments with a copy of itself.
      final assembler = OpenRouterToolCallAssembler();
      assembler.addDeltas([
        {
          'index': 0,
          'id': 'call_1',
          'function': {'name': 'web_search', 'arguments': '{"query":"Belle'},
        },
      ]);
      assembler.addFromCompletionJson({
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'tool_calls': [
                {
                  'id': 'call_1',
                  'function': {
                    'name': 'web_search',
                    'arguments': '{"query":"Bellevue WA weather"}',
                  },
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
      });

      final calls = assembler.build();
      expect(calls, hasLength(1));
      expect(calls.single.arguments['query'], 'Bellevue WA weather',
          reason: 'the finished call is authoritative; the half-streamed '
              'fragment it supersedes is discarded, not prepended');
    });

    test('a message payload with an empty tool_calls array leaves fragments '
        'alone', () {
      // An empty array says nothing about calls the deltas are still
      // building, so it must not clear them.
      final assembler = OpenRouterToolCallAssembler();
      assembler.addDeltas([
        {
          'index': 0,
          'function': {
            'name': 'web_search',
            'arguments': '{"query":"Bellevue WA weather"}',
          },
        },
      ]);
      assembler.addFromCompletionJson({
        'choices': [
          {
            'message': {'role': 'assistant', 'tool_calls': <dynamic>[]},
            'finish_reason': 'stop',
          },
        ],
      });

      expect(
        assembler.build().map((c) => c.arguments['query']),
        ['Bellevue WA weather'],
      );
    });
  });
}
