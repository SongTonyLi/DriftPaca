import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Services/ollama_service.dart';

void main() {
  test('OpenRouter mode lists models from /api/v1/models with a bearer key',
      () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'data': [
            {
              'id': 'openai/gpt-4o-mini',
              'name': 'OpenAI: GPT-4o Mini',
              'description': 'Small fast model',
              'context_length': 128000,
              'architecture': {
                'input_modalities': ['text'],
                'output_modalities': ['text'],
              },
            },
          ],
        }),
        200,
      );
    });

    final service = OllamaService(client: client)
      ..isOpenRouterMode = true
      ..apiKey = 'or-key';

    final models = await service.listModels();

    expect(captured.url.toString(), 'https://openrouter.ai/api/v1/models');
    expect(captured.headers['Authorization'], 'Bearer or-key');
    expect(captured.headers['HTTP-Referer'], contains('DriftPaca'));
    expect(models.single.name, 'openai/gpt-4o-mini');
    expect(models.single.family, 'openai');
  });

  test('OpenRouter chatStream posts SSE completions and yields tokens', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        'data: {"choices":[{"delta":{"content":"Hel"}}]}\n\n'
        'data: {"choices":[{"delta":{"content":"lo"},"finish_reason":"stop"}]}\n\n'
        'data: [DONE]\n\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });

    final service = OllamaService(client: client)
      ..isOpenRouterMode = true
      ..apiKey = 'or-key';

    final chunks = <String>[];
    await for (final message in service.chatStream(
      [OllamaMessage('Hi', role: OllamaMessageRole.user)],
      chat: OllamaChat(model: 'openai/gpt-4o-mini'),
    )) {
      chunks.add(message.content);
    }

    expect(captured.url.toString(),
        'https://openrouter.ai/api/v1/chat/completions');
    expect(captured.headers['Authorization'], 'Bearer or-key');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['model'], 'openai/gpt-4o-mini');
    expect(body['stream'], isTrue);
    expect(chunks.join(), 'Hello');
  });

  test('OpenRouter generate uses chat completions with a user prompt', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'model': 'openai/gpt-4o-mini',
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'A title'},
              'finish_reason': 'stop',
            },
          ],
        }),
        200,
      );
    });

    final service = OllamaService(client: client)
      ..isOpenRouterMode = true
      ..apiKey = 'or-key';

    final message = await service.generate(
      'Name this chat',
      chat: OllamaChat(
        model: 'openai/gpt-4o-mini',
        systemPrompt: 'Return a short title',
      ),
    );

    expect(captured.url.toString(),
        'https://openrouter.ai/api/v1/chat/completions');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['stream'], isFalse);
    expect(body['messages'], isA<List>());
    expect(message.content, 'A title');
  });
}
