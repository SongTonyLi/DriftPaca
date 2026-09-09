import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';

OllamaMessage parseMessage(Map<String, dynamic> message) {
  return OllamaMessage.fromJson({
    'created_at': DateTime.now().toIso8601String(),
    'message': message,
  });
}

void main() {
  test('parses tool_calls with object arguments', () {
    final msg = parseMessage({
      'role': 'assistant',
      'content': '',
      'tool_calls': [
        {
          'function': {
            'name': 'web_search',
            'arguments': {'query': 'Vietnam GDP'},
          },
        },
      ],
    });
    expect(msg.toolCalls, isNotNull);
    expect(msg.toolCalls!.single.name, 'web_search');
    expect(msg.toolCalls!.single.arguments['query'], 'Vietnam GDP');
  });

  test('null content becomes empty string', () {
    final msg = parseMessage({
      'role': 'assistant',
      'content': null,
      'tool_calls': [
        {
          'function': {
            'name': 'web_search',
            'arguments': {'query': 'q'},
          },
        },
      ],
    });
    expect(msg.content, '');
    expect(msg.toolCalls, isNotEmpty);
  });

  test('parses tool_calls with JSON-string arguments', () {
    final msg = parseMessage({
      'role': 'assistant',
      'content': '',
      'tool_calls': [
        {
          'function': {
            'name': 'web_search',
            'arguments': '{"query":"string args"}',
          },
        },
      ],
    });
    expect(msg.toolCalls!.single.arguments['query'], 'string args');
  });

  test('parses multiple tool_calls', () {
    final msg = parseMessage({
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
    });
    expect(msg.toolCalls!.map((c) => c.arguments['query']).toList(), ['one', 'two']);
  });

  test('role tool fromString and toChatJson emit tool_name', () async {
    expect(OllamaMessageRole.fromString('tool'), OllamaMessageRole.tool);
    final msg = OllamaMessage(
      'result text',
      role: OllamaMessageRole.tool,
      toolName: 'web_search',
    );
    final json = await msg.toChatJson();
    expect(json['role'], 'tool');
    expect(json['tool_name'], 'web_search');
    expect(json['content'], 'result text');
    expect(json.containsKey('tool_calls'), isFalse);
  });

  test('toChatJson emits tool_calls for assistant', () async {
    final msg = OllamaMessage(
      '',
      role: OllamaMessageRole.assistant,
      toolCalls: [
        const OllamaToolCall(
          name: 'web_search',
          arguments: {'query': 'gdp'},
        ),
      ],
    );
    final json = await msg.toChatJson();
    expect(json['tool_calls'], isNotEmpty);
    expect(json['tool_calls'][0]['function']['name'], 'web_search');
    expect(json['tool_calls'][0]['function']['arguments']['query'], 'gdp');
  });

  test('OllamaToolDefinition.webSearch schema', () {
    const tool = OllamaToolDefinition.webSearch;
    expect(tool.name, 'web_search');
    expect(tool.description, contains('ledger'));
    expect(tool.parameters['required'], ['query']);
    expect(
      (tool.parameters['properties'] as Map)['query']['type'],
      'string',
    );
    final json = tool.toJson();
    expect(json['type'], 'function');
    expect(json['function']['name'], 'web_search');
    expect(json['function']['parameters']['required'], ['query']);
  });

  test('lifts q onto query and accepts a bare argument string', () {
    expect(
      OllamaToolCall.parseArguments({'q': 'Bellevue WA weather'})['query'],
      'Bellevue WA weather',
    );
    expect(
      OllamaToolCall.parseArguments('current weather Bellevue WA')['query'],
      'current weather Bellevue WA',
    );
    expect(
      OllamaToolCall.searchQuery({'search_query': 'gdp vietnam'}),
      'gdp vietnam',
    );
  });

  test('JSON-shaped arguments that do not decode produce no query', () {
    // Two parallel calls glued together by a stream assembler that could
    // not tell them apart, and a call truncated mid-stream. Both used to
    // come back as {query: <the raw text>}, which sent the literal JSON to
    // a search engine, spent one of the run's search slots on it and filed
    // it in the research ledger as a sub-goal that had been researched
    // (audit finding #11). No query means SearchAgent skips the call
    // visibly instead.
    expect(
      OllamaToolCall.parseArguments('{"query":"a"}{"query":"b"}'),
      isEmpty,
      reason: 'concatenated argument objects are wreckage, not a query',
    );
    expect(
      OllamaToolCall.parseArguments('{"query":"popul'),
      isEmpty,
      reason: 'truncated argument JSON is wreckage too — searching it '
          'would report a half-written query as researched',
    );
    expect(
      OllamaToolCall.parseArguments('[{"query":"a"}]'),
      isEmpty,
      reason: 'the same holds for an array-shaped payload that carries no '
          'arguments map',
    );
    expect(
      OllamaToolCall.parseArguments('current weather Bellevue WA')['query'],
      'current weather Bellevue WA',
      reason: 'a model that sends a bare query string instead of JSON is '
          'still understood — only JSON-shaped text is held to decoding',
    );
  });
}
