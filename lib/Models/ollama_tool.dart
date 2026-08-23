import 'dart:convert';

/// A single tool invocation from an Ollama assistant message.
class OllamaToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  const OllamaToolCall({
    required this.name,
    required this.arguments,
  });

  factory OllamaToolCall.fromJson(Map<String, dynamic> json) {
    final function = json['function'] is Map
        ? Map<String, dynamic>.from(json['function'] as Map)
        : json;
    return OllamaToolCall(
      name: function['name']?.toString() ?? '',
      arguments: _parseArguments(function['arguments']),
    );
  }

  static Map<String, dynamic> _parseArguments(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return {};
  }

  Map<String, dynamic> toJson() => {
        'function': {
          'name': name,
          'arguments': arguments,
        },
      };
}

/// An Ollama function-tool definition sent on the chat request.
class OllamaToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  const OllamaToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });

  Map<String, dynamic> toJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };

  static const OllamaToolDefinition webSearch = OllamaToolDefinition(
    name: 'web_search',
    description:
        'Search the web for current facts, numbers, news, or anything that '
        'may have changed. Use a concise query. Call this again only to close '
        'a specific gap the previous results left open, with a query that '
        'targets that gap — not a rephrasing of one already asked. Tool '
        'results may include a research ledger showing what has already been '
        'searched and what remains open — check it before searching again.',
    parameters: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': 'The search query to look up.',
        },
      },
      'required': ['query'],
    },
  );
}
