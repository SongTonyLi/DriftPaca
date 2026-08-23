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
}
