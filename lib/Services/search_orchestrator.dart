import 'dart:async';
import 'dart:io';

import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Services/ollama_service.dart';
import 'package:llamaseek/Services/web_search_service.dart';

/// Result of parsing an evaluation response.
class ParseResult {
  final bool canAnswer;
  final String? nextQuery;
  final String reasoning;

  ParseResult({
    required this.canAnswer,
    this.nextQuery,
    required this.reasoning,
  });
}

/// Orchestrates an agentic search loop: plan -> search -> evaluate -> repeat.
/// Emits [SearchEvent]s for UI updates via [events] stream.
/// Max 3 iterations. All LLM calls are non-streaming with 15s timeout.
class SearchOrchestrator {
  final OllamaService _ollamaService;
  final OllamaChat _chat;
  final WebSearchService _searchService;

  static const _maxIterations = 3;
  static const _llmTimeout = Duration(seconds: 15);
  static const _maxContextChars = 16000;

  bool _cancelled = false;

  final _eventController = StreamController<SearchEvent>.broadcast();

  /// Stream of search events for UI updates.
  Stream<SearchEvent> get events => _eventController.stream;

  SearchOrchestrator({
    required OllamaService ollamaService,
    required OllamaChat chat,
    WebSearchService? searchService,
  })  : _ollamaService = ollamaService,
        _chat = chat,
        _searchService = searchService ?? WebSearchService();

  /// Cancel the orchestrator. Checked between each step.
  void cancel() {
    _cancelled = true;
  }

  /// Runs the agentic search loop.
  /// Returns the accumulated search context string for prompt injection,
  /// or null if no useful results were found.
  Future<String?> run(String userMessage) async {
    final accumulatedResults = <WebSearchResult>[];
    final queriesUsed = <String>[];

    try {
      for (var iteration = 0;
          iteration < _maxIterations && !_cancelled;
          iteration++) {
        String query;
        String reasoning;

        if (iteration == 0) {
          // --- PLANNING ---
          final planResult = await _planSearch(userMessage);
          reasoning = planResult.reasoning;
          query = planResult.query;
        } else {
          // --- EVALUATION (from previous iteration) ---
          final evalResponse = await _evaluate(
            userMessage,
            accumulatedResults,
            queriesUsed,
          );

          if (evalResponse.canAnswer) {
            if (evalResponse.reasoning.isNotEmpty) {
              _emit(ThinkingEvent(evalResponse.reasoning));
            }
            break;
          }

          reasoning = evalResponse.reasoning;
          query = evalResponse.nextQuery ?? userMessage;

          // Don't repeat a query
          if (queriesUsed.contains(query)) break;
        }

        if (_cancelled) break;
        queriesUsed.add(query);

        if (reasoning.isNotEmpty) {
          _emit(ThinkingEvent(reasoning));
        }
        _emit(SearchStartEvent(query));

        // --- SEARCH ---
        final results = await _search(query);

        if (_cancelled) break;

        accumulatedResults.addAll(results);
        _capContext(accumulatedResults);

        // If last iteration, don't evaluate — just answer
        if (iteration == _maxIterations - 1) break;
      }
    } catch (e) {
      _emit(SearchErrorEvent('Search error: ${e.toString().split('\n').first}'));
    }

    _emit(AnswerStartEvent());

    if (accumulatedResults.isEmpty) return null;

    return WebSearchService.formatResultsAsContext(accumulatedResults);
  }

  // ============================================================
  // Planning
  // ============================================================

  Future<({String query, String reasoning})> _planSearch(
      String userMessage) async {
    try {
      final prompt =
          '''Think step by step about what information you need to answer the user's question.
Reason briefly about what to search for.
On the LAST line, write ONLY the search query (max 10 words, no quotes, no explanation).

User question: $userMessage''';

      final chat = OllamaChat(
        model: _chat.model,
        systemPrompt:
            'You are a search query planner. Your job is to determine the best web search query.',
      );

      final response = await _ollamaService
          .generate(prompt, chat: chat)
          .timeout(_llmTimeout);

      final lines = response.content.trim().split('\n');
      final lastLine = lines.last.trim();
      final reasoning =
          lines.length > 1 ? lines.sublist(0, lines.length - 1).join('\n') : '';
      final query = sanitizeQuery(lastLine);

      return (
        query: query.isNotEmpty ? query : userMessage,
        reasoning: reasoning,
      );
    } catch (e) {
      return (query: userMessage, reasoning: '');
    }
  }

  // ============================================================
  // Search Execution
  // ============================================================

  Future<List<WebSearchResult>> _search(String query) async {
    try {
      final results = await _searchService.searchAndExtract(query);

      if (results.isEmpty) {
        _emit(SearchErrorEvent('No results found'));
        return [];
      }

      _emit(SearchProgressEvent(results
          .map((r) => SearchURLStatus(
                url: r.url,
                domain: Uri.tryParse(r.url)?.host ?? r.url,
                state: r.pageContent != null
                    ? SearchURLState.success
                    : SearchURLState.failed,
              ))
          .toList()));

      _emit(SearchCompleteEvent(results.length));
      return results;
    } on SocketException {
      _emit(SearchErrorEvent('No internet connection'));
      return [];
    } on TimeoutException {
      _emit(SearchErrorEvent('Search timed out'));
      return [];
    } catch (e) {
      _emit(SearchErrorEvent('Search unavailable'));
      return [];
    }
  }

  // ============================================================
  // Evaluation
  // ============================================================

  Future<ParseResult> _evaluate(
    String userMessage,
    List<WebSearchResult> results,
    List<String> queriesUsed,
  ) async {
    try {
      final context = WebSearchService.formatResultsAsContext(results);
      final queriesList = queriesUsed.map((q) => '- "$q"').join('\n');

      final prompt =
          '''You searched for "${queriesUsed.last}" and found these results:

$context

Think about whether you can fully answer the user's question with the information above.
If you need more information, explain what's missing and write SEARCH: <query> on the last line.
If you have enough, write DONE on the last line.

Do not repeat these previous queries:
$queriesList

User question: $userMessage''';

      final chat = OllamaChat(
        model: _chat.model,
        systemPrompt:
            'You are a search evaluator. Decide if more searches are needed to answer the question.',
      );

      final response = await _ollamaService
          .generate(prompt, chat: chat)
          .timeout(_llmTimeout);

      return parseEvaluation(response.content);
    } catch (e) {
      return ParseResult(canAnswer: true, reasoning: '');
    }
  }

  // ============================================================
  // Parsing
  // ============================================================

  /// Leniently parses the evaluation response.
  /// Last line determines action: done-like words -> stop, anything else -> next query.
  static ParseResult parseEvaluation(String response) {
    final trimmed = response.trim();
    if (trimmed.isEmpty) {
      return ParseResult(canAnswer: true, reasoning: '');
    }

    final lines = trimmed.split('\n');
    final lastLine = lines.last.trim().toLowerCase();
    final reasoning =
        lines.length > 1 ? lines.sublist(0, lines.length - 1).join('\n') : '';

    // Check for "done" signals
    const doneSignals = [
      'ready',
      'done',
      'enough',
      'sufficient',
      'can answer',
      'have enough',
      'no further',
    ];
    if (doneSignals.any((s) => lastLine.contains(s))) {
      return ParseResult(canAnswer: true, reasoning: reasoning);
    }

    // Strip explicit search prefix if present
    var query = lines.last.trim(); // preserve original case for query
    for (final prefix in ['search:', 'search for:', 'query:']) {
      final lower = query.toLowerCase();
      if (lower.startsWith(prefix)) {
        query = query.substring(prefix.length).trim();
        break;
      }
    }

    query = sanitizeQuery(query);

    if (query.isEmpty || query.length > 200) {
      return ParseResult(canAnswer: true, reasoning: trimmed);
    }

    return ParseResult(
      canAnswer: false,
      nextQuery: query,
      reasoning: reasoning,
    );
  }

  // ============================================================
  // Helpers
  // ============================================================

  /// Sanitizes a query string by removing quotes, backticks, asterisks.
  static String sanitizeQuery(String query) {
    return query
        .replaceAll(RegExp(r'^["\x27]|["\x27]$'), '')
        .replaceAll(RegExp(r'^`+|`+$'), '')
        .replaceAll(RegExp(r'^\*+|\*+$'), '')
        .trim();
  }

  void _capContext(List<WebSearchResult> results) {
    var totalChars = 0;
    for (final r in results) {
      final content = r.pageContent ?? r.snippet;
      totalChars += content.length;
    }

    while (totalChars > _maxContextChars && results.length > 1) {
      final removed = results.removeAt(0);
      totalChars -= (removed.pageContent ?? removed.snippet).length;
    }
  }

  void _emit(SearchEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  void dispose() {
    _eventController.close();
  }
}
