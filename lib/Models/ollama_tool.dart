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
  /// (`q`, `search_query`, a bare string) onto `query`. JSON-shaped text
  /// that does not decode yields NO arguments rather than a query — see the
  /// catch block below.
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
        // A string that OPENS like JSON but does not decode is corrupt
        // arguments — truncated mid-stream, or two parallel calls glued
        // together by an assembler that could not tell them apart — not a
        // bare query the model typed. Handing the literal text back as a
        // query spends one of the run's search slots on nonsense and files
        // that nonsense in the research ledger as a sub-goal that has now
        // "been researched" (audit finding #11). Returning no arguments
        // routes the call to SearchAgent._planSearches' emptyQuery branch
        // instead, which answers the model with "No query provided;
        // nothing was searched." and reports it through onSearchSkipped,
        // so the loop, the transcript and the UI all see the failure.
        final trimmed = raw.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) return {};
        return {'query': trimmed};
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
