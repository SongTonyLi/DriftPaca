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
}
