import 'dart:convert';

import 'package:llamaseek/Models/model_capabilities.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Models/ollama_tool.dart';

/// Pure OpenRouter ↔ Ollama translations. Kept free of I/O so the mapping
/// can be unit-tested without a network.
class OpenRouterCodec {
  static const String referer = 'https://github.com/SongTonyLi/DriftPaca';
  static const String title = 'DriftPaca';

  /// Parses `GET /api/v1/models` and keeps text-output chat models only.
  static List<OllamaModel> parseModels(Map<String, dynamic> json) {
    final raw = json['data'];
    if (raw is! List) return const [];

    final models = <OllamaModel>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final architecture = map['architecture'] is Map
          ? Map<String, dynamic>.from(map['architecture'] as Map)
          : const <String, dynamic>{};
      final outputs = _stringList(architecture['output_modalities']);
      if (outputs.isNotEmpty && !outputs.contains('text')) continue;

      final id = (map['id'] ?? '').toString();
      if (id.isEmpty) continue;

      final created = map['created'];
      final modifiedAt = created is num
          ? DateTime.fromMillisecondsSinceEpoch((created * 1000).round())
          : DateTime.now();

      models.add(OllamaModel(
        name: id,
        model: id,
        modifiedAt: modifiedAt,
        size: 0,
        digest: id,
        parameterSize: parameterSizeFromId(id),
        family: familyFromId(id),
        format: 'openrouter',
        description: (map['description'] ?? '').toString(),
        contextLength: _asInt(map['context_length']),
        capabilities: capabilitiesFrom(map, architecture),
      ));
    }
    return models;
  }

  static String familyFromId(String id) {
    final slash = id.indexOf('/');
    return slash > 0 ? id.substring(0, slash) : id;
  }

  static String parameterSizeFromId(String id) {
    final match = RegExp(r'(\d+(?:\.\d+)?)[ \-]?([bBtT])\b').firstMatch(id);
    if (match == null) return '';
    return '${match.group(1)}${match.group(2)!.toUpperCase()}';
  }

  static ModelCapabilities capabilitiesFrom(
    Map<String, dynamic> model,
    Map<String, dynamic> architecture,
  ) {
    final inputs = _stringList(architecture['input_modalities']);
    final supported = _stringList(model['supported_parameters']);
    final hay = '${model['id'] ?? ''} ${model['name'] ?? ''}'.toLowerCase();
    final thinking = supported.contains('reasoning') ||
        hay.contains('thinking') ||
        hay.contains('reasoning') ||
        RegExp(r'(?:^|[^a-z])o[1-9](?:[^a-z]|$)').hasMatch(hay) ||
        hay.contains('r1');
    return ModelCapabilities(
      completion: true,
      vision: inputs.contains('image'),
      tools: supported.isEmpty || supported.contains('tools'),
      thinking: thinking,
    );
  }

  /// Converts prepared Ollama chat maps into OpenAI-compatible messages.
  static List<Map<String, dynamic>> toOpenAiMessages(
    List<Map<String, dynamic>> messages,
  ) {
    final out = <Map<String, dynamic>>[];
    for (final raw in messages) {
      final msg = Map<String, dynamic>.from(raw);
      final images = msg.remove('images');
      final toolName = msg.remove('tool_name');
      final ollamaTools = msg['tool_calls'];

      if (ollamaTools is List && ollamaTools.isNotEmpty) {
        msg['tool_calls'] = [
          for (var i = 0; i < ollamaTools.length; i++)
            _toOpenAiToolCall(ollamaTools[i], i),
        ];
      }

      if (toolName != null && msg['role'] == 'tool') {
        msg['name'] = toolName;
        msg['tool_call_id'] = 'tool_${out.length}';
      }

      if (images is List && images.isNotEmpty) {
        msg['content'] = [
          if ((msg['content'] ?? '').toString().isNotEmpty)
            {'type': 'text', 'text': msg['content']},
          for (final image in images)
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/jpeg;base64,$image',
              },
            },
        ];
      }

      msg.remove('thinking');
      out.add(msg);
    }
    return out;
  }

  static Map<String, dynamic> _toOpenAiToolCall(dynamic raw, int index) {
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final function = map['function'] is Map
        ? Map<String, dynamic>.from(map['function'] as Map)
        : map;
    final arguments = function['arguments'];
    final encoded = arguments is String
        ? arguments
        : jsonEncode(arguments ?? {});
    return {
      'id': map['id'] ?? 'call_$index',
      'type': 'function',
      'function': {
        'name': function['name'] ?? '',
        'arguments': encoded,
      },
    };
  }

  static Map<String, dynamic> chatBody({
    required String model,
    required List<Map<String, dynamic>> messages,
    required bool stream,
    double? temperature,
    List<Map<String, dynamic>>? tools,
  }) {
    return {
      'model': model,
      'messages': messages,
      'stream': stream,
      if (temperature != null) 'temperature': temperature,
      if (tools != null && tools.isNotEmpty) 'tools': tools,
    };
  }

  /// Parses one SSE line (`data: {...}`). Returns null for keep-alives / DONE.
  static OllamaMessage? parseSseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith(':')) return null;
    if (!trimmed.startsWith('data:')) return null;
    final payload = trimmed.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') return null;
    try {
      final json = jsonDecode(payload);
      if (json is Map<String, dynamic>) return parseCompletion(json);
      if (json is Map) {
        return parseCompletion(Map<String, dynamic>.from(json));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static OllamaMessage parseCompletion(Map<String, dynamic> json) {
    final choices = json['choices'];
    final choice = choices is List && choices.isNotEmpty && choices.first is Map
        ? Map<String, dynamic>.from(choices.first as Map)
        : const <String, dynamic>{};
    final delta = choice['delta'] is Map
        ? Map<String, dynamic>.from(choice['delta'] as Map)
        : null;
    final message = choice['message'] is Map
        ? Map<String, dynamic>.from(choice['message'] as Map)
        : delta ?? const <String, dynamic>{};

    final finish = choice['finish_reason']?.toString();
    final rawTools = message['tool_calls'] ?? delta?['tool_calls'];
    final thinking = (message['reasoning'] ??
            message['reasoning_content'] ??
            delta?['reasoning'] ??
            delta?['reasoning_content'])
        ?.toString();

    return OllamaMessage(
      (message['content'] ?? '').toString(),
      role: OllamaMessageRole.assistant,
      thinking: thinking == null || thinking.isEmpty ? null : thinking,
      toolCalls: _parseToolCalls(rawTools),
      model: json['model']?.toString(),
      done: finish != null && finish.isNotEmpty,
    );
  }

  static List<OllamaToolCall>? _parseToolCalls(dynamic raw) {
    if (raw is! List || raw.isEmpty) return null;
    final calls = <OllamaToolCall>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final call = OllamaToolCall.fromJson(Map<String, dynamic>.from(item));
      if (call.name.isEmpty) continue;
      calls.add(call);
    }
    return calls.isEmpty ? null : calls;
  }

  static List<String> _stringList(dynamic raw) {
    if (raw is! List) return const [];
    return [for (final item in raw) item.toString()];
  }

  static int? _asInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    return int.tryParse(raw?.toString() ?? '');
  }
}
