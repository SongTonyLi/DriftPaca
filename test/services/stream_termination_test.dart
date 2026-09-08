import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Services/ollama_service.dart';

/// Answers every request with a body fed by hand over a socket that is
/// NEVER closed — a keep-alive connection (OpenRouter's own, or any proxy in
/// between) left open after the last token. That is the shape of the "stuck
/// generating" bug: the answer is complete on screen and the app is still
/// waiting on the stream to end.
class _NeverClosingClient extends http.BaseClient {
  final Stream<List<int>> body;

  _NeverClosingClient(this.body);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        body,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
}

void main() {
  test('an OpenRouter response ends at [DONE], not when the socket closes',
      () async {
    final body = StreamController<List<int>>();
    addTearDown(body.close);
    final service = OllamaService(client: _NeverClosingClient(body.stream))
      ..isOpenRouterMode = true
      ..apiKey = 'or-key';

    final content = StringBuffer();
    final run = service
        .chatStream(
          [OllamaMessage('Hi', role: OllamaMessageRole.user)],
          chat: OllamaChat(model: 'openai/gpt-4o-mini'),
        )
        .forEach((message) => content.write(message.content));

    body.add(utf8.encode('data: {"choices":[{"delta":{"content":"Hel"}}]}\n\n'
        'data: {"choices":[{"delta":{"content":"lo"},'
        '"finish_reason":"stop"}]}\n\n'
        'data: [DONE]\n\n'));

    await run.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('the stream never ended after its [DONE] sentinel'),
    );
    expect(content.toString(), 'Hello');
  });

  test('an Ollama response ends at done:true, not when the socket closes',
      () async {
    final body = StreamController<List<int>>();
    addTearDown(body.close);
    final service = OllamaService(client: _NeverClosingClient(body.stream));

    final content = StringBuffer();
    final run = service
        .chatStream(
          [OllamaMessage('Hi', role: OllamaMessageRole.user)],
          chat: OllamaChat(model: 'llama3.2:latest'),
        )
        .forEach((message) => content.write(message.content));

    String chunk(String text, {required bool done}) => '${jsonEncode({
          'model': 'llama3.2:latest',
          'created_at': '2026-09-06T12:00:00.000Z',
          'message': {'role': 'assistant', 'content': text},
          'done': done,
          if (done) 'done_reason': 'stop',
        })}\n';

    body.add(utf8.encode(
        '${chunk('Hel', done: false)}${chunk('lo', done: false)}'
        '${chunk('', done: true)}'));

    await run.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('the stream never ended after its final object'),
    );
    expect(content.toString(), 'Hello');
  });

  test('the idle limit counts from the first byte, not from the request',
      () async {
    // A slow first token is not a stall: a local model loading or chewing
    // through a large prompt sends nothing for a while, and the limit must
    // not cut that short. Silence AFTER the response has started is what
    // it exists for.
    final defaultIdle = OllamaService.streamIdleLimit;
    OllamaService.streamIdleLimit = const Duration(milliseconds: 150);
    addTearDown(() => OllamaService.streamIdleLimit = defaultIdle);
    final body = StreamController<List<int>>();
    addTearDown(body.close);
    final service = OllamaService(client: _NeverClosingClient(body.stream))
      ..isOpenRouterMode = true
      ..apiKey = 'or-key';

    final content = StringBuffer();
    final run = service
        .chatStream(
          [OllamaMessage('Hi', role: OllamaMessageRole.user)],
          chat: OllamaChat(model: 'openai/gpt-4o-mini'),
        )
        .forEach((message) => content.write(message.content));

    // Well past the idle limit before the first byte.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    body.add(utf8.encode('data: {"choices":[{"delta":{"content":"Late"}}]}\n\n'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    body.add(utf8.encode('data: {"choices":[{"delta":{"content":" start"}}]}\n\n'));
    // Then nothing: no finish_reason, no [DONE], socket held open.

    await run.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('the stream never ended after going silent'),
    );
    expect(content.toString(), 'Late start');
  });

  test('a partial trailing SSE line is still assembled across chunks',
      () async {
    // The terminator check runs on every line, so it must not disturb the
    // buffering that makes a payload split across two network reads parse.
    final body = StreamController<List<int>>();
    addTearDown(body.close);
    final service = OllamaService(client: _NeverClosingClient(body.stream))
      ..isOpenRouterMode = true
      ..apiKey = 'or-key';

    final content = StringBuffer();
    final run = service
        .chatStream(
          [OllamaMessage('Hi', role: OllamaMessageRole.user)],
          chat: OllamaChat(model: 'openai/gpt-4o-mini'),
        )
        .forEach((message) => content.write(message.content));

    body.add(utf8.encode('data: {"choices":[{"delta":{"content":"Split'));
    body.add(utf8.encode(' token"}}]}\n\ndata: [DONE]\n\n'));

    await run.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('the stream never ended after its [DONE] sentinel'),
    );
    expect(content.toString(), 'Split token');
  });
}
