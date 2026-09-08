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
    // Ids of the most recent assistant message's tool calls that no tool
    // message has answered yet, in call order. OpenAI-compatible providers
    // (OpenAI, Anthropic and Gemini through OpenRouter) reject a request
    // whose tool messages do not answer those exact ids — and Ollama tool
    // calls carry no id at all, so both sides are minted here. Minting
    // them independently (the call from its index, the reply from its
    // position in the conversation) meant no reply ever matched its call,
    // which is a 400 on every research turn after the first.
    final pendingCallIds = <String>[];
    for (final raw in messages) {
      final msg = Map<String, dynamic>.from(raw);
      final images = msg.remove('images');
      final toolName = msg.remove('tool_name');
      final ollamaTools = msg['tool_calls'];

      if (ollamaTools is List && ollamaTools.isNotEmpty) {
        pendingCallIds.clear();
        final calls = <Map<String, dynamic>>[];
        for (var i = 0; i < ollamaTools.length; i++) {
          final call =
              _toOpenAiToolCall(ollamaTools[i], 'call_${out.length}_$i');
          pendingCallIds.add(call['id'] as String);
          calls.add(call);
        }
        msg['tool_calls'] = calls;
      }

      if (toolName != null && msg['role'] == 'tool') {
        msg['name'] = toolName;
        msg['tool_call_id'] = pendingCallIds.isNotEmpty
            ? pendingCallIds.removeAt(0)
            : 'tool_${out.length}';
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

  static Map<String, dynamic> _toOpenAiToolCall(dynamic raw, String fallbackId) {
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final function = map['function'] is Map
        ? Map<String, dynamic>.from(map['function'] as Map)
        : map;
    final arguments = function['arguments'];
    final encoded = arguments is String
        ? arguments
        : jsonEncode(arguments ?? {});
    return {
      'id': map['id'] ?? fallbackId,
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
    final json = decodeSseJson(line);
    return json == null ? null : parseCompletion(json);
  }

  /// Whether [line] is the SSE stream terminator (`data: [DONE]`).
  ///
  /// The OpenAI-compatible protocol OpenRouter speaks marks end-of-response
  /// with this sentinel and sends nothing after it, so a reader that
  /// recognizes it can stop at the answer instead of waiting for the socket
  /// to close. That wait is not free: a keep-alive connection (OpenRouter's
  /// own, or any proxy in between) can stay open long after the last token,
  /// and every consumer up the stack — the research turn, the run, the
  /// "generating" UI and its stop button — is blocked on the stream ending.
  /// The user sees a finished answer that the app still calls in progress.
  static bool isStreamTerminator(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('data:')) return false;
    return trimmed.substring(5).trim() == '[DONE]';
  }

  /// Decodes one `data: {...}` SSE payload. Null for keep-alives / DONE.
  static Map<String, dynamic>? decodeSseJson(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith(':')) return null;
    if (!trimmed.startsWith('data:')) return null;
    final payload = trimmed.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') return null;
    try {
      final json = jsonDecode(payload);
      if (json is Map<String, dynamic>) return json;
      if (json is Map) return Map<String, dynamic>.from(json);
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Raw `tool_calls` deltas from a completion / SSE chunk, including nameless
  /// argument fragments that `_parseToolCalls` would drop.
  static List<dynamic>? toolCallDeltas(Map<String, dynamic> json) {
    final choices = json['choices'];
    final choice = choices is List && choices.isNotEmpty && choices.first is Map
        ? Map<String, dynamic>.from(choices.first as Map)
        : const <String, dynamic>{};
    final delta = choice['delta'] is Map
        ? Map<String, dynamic>.from(choice['delta'] as Map)
        : null;
    final payload = choice['message'] is Map
        ? Map<String, dynamic>.from(choice['message'] as Map)
        : delta;
    final raw = payload?['tool_calls'] ?? delta?['tool_calls'];
    return raw is List ? raw : null;
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

/// Merges OpenAI-compatible streamed `tool_calls` deltas by `index`.
///
/// OpenRouter (and Gemini through it) sends the function name in the first
/// chunk and the JSON arguments as later nameless fragments. Treating each
/// chunk as a finished call produced empty `web_search` queries.
class OpenRouterToolCallAssembler {
  final Map<int, _AssemblingCall> _calls = {};

  void addFromCompletionJson(Map<String, dynamic> json) {
    final deltas = OpenRouterCodec.toolCallDeltas(json);
    if (deltas != null) addDeltas(deltas);
  }

  void addDeltas(dynamic raw) {
    if (raw is! List) return;
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final index = map['index'] is num
          ? (map['index'] as num).toInt()
          : (_calls.isEmpty ? 0 : _calls.keys.reduce((a, b) => a > b ? a : b));
      final existing = _calls.putIfAbsent(index, _AssemblingCall.new);
      if (map['id'] != null) existing.id = map['id'].toString();
      final function = map['function'] is Map
          ? Map<String, dynamic>.from(map['function'] as Map)
          : map;
      final name = (function['name'] ?? map['name'])?.toString();
      if (name != null && name.isNotEmpty) existing.name = name;
      existing.addArguments(
        function['arguments'] ??
            function['args'] ??
            map['arguments'] ??
            map['args'],
      );
    }
  }

  List<OllamaToolCall> build() {
    final keys = _calls.keys.toList()..sort();
    return [
      for (final key in keys)
        if (_calls[key]!.name.isNotEmpty)
          OllamaToolCall(
            name: _calls[key]!.name,
            arguments: _calls[key]!.parsedArguments(),
          ),
    ];
  }

  void clear() => _calls.clear();
}

class _AssemblingCall {
  String name = '';
  String id = '';
  String argumentsJson = '';
  Map<String, dynamic>? argumentsMap;

  void addArguments(dynamic args) {
    if (args == null) return;
    if (args is String) {
      argumentsJson += args;
      return;
    }
    if (args is Map) {
      argumentsMap = Map<String, dynamic>.from(args);
    }
  }

  Map<String, dynamic> parsedArguments() {
    if (argumentsJson.isNotEmpty) {
      return OllamaToolCall.parseArguments(argumentsJson);
    }
    if (argumentsMap != null) {
      return OllamaToolCall.normalizeSearchArgs(argumentsMap!);
    }
    return {};
  }
}
