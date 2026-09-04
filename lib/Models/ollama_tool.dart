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
      arguments: parseArguments(function['arguments'] ?? function['args']),
    );
  }

  /// Parses OpenAI / Gemini tool arguments and lifts common query aliases
  /// (`q`, `search_query`, a bare string) onto `query`.
  static Map<String, dynamic> parseArguments(dynamic raw) {
    if (raw is Map<String, dynamic>) return normalizeSearchArgs(raw);
    if (raw is Map) return normalizeSearchArgs(Map<String, dynamic>.from(raw));
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return normalizeSearchArgs(decoded);
        if (decoded is Map) {
          return normalizeSearchArgs(Map<String, dynamic>.from(decoded));
        }
        if (decoded is String && decoded.trim().isNotEmpty) {
          return {'query': decoded.trim()};
        }
      } catch (_) {
        return {'query': raw.trim()};
      }
    }
    return {};
  }

  static Map<String, dynamic> normalizeSearchArgs(Map<String, dynamic> args) {
    if (_nonEmpty(args['query'])) return args;
    const aliases = ['q', 'search_query', 'searchQuery', 'text', 'input'];
    for (final key in aliases) {
      if (_nonEmpty(args[key])) {
        return {...args, 'query': args[key].toString().trim()};
      }
    }
    if (args.length == 1 && _nonEmpty(args.values.single)) {
      return {...args, 'query': args.values.single.toString().trim()};
    }
    return args;
  }

  static String searchQuery(Map<String, dynamic> arguments) =>
      (normalizeSearchArgs(arguments)['query']?.toString() ?? '').trim();

  static bool _nonEmpty(dynamic value) =>
      value != null && value.toString().trim().isNotEmpty;

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
