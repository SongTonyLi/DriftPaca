import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Services/web_search_service.dart';

class SearchAgentRequest {
  final List<OllamaMessage> history;
  final List<OllamaMessage> transcript;
  final bool includeMemory;
  final bool toolsEnabled;

  const SearchAgentRequest({
    required this.history,
    required this.transcript,
    required this.includeMemory,
    required this.toolsEnabled,
  });
}

class SearchAgentSearchRequest {
  final String query;
  final void Function(List<WebSearchResult> urls)? onUrlsKnown;
  final void Function(String url, bool success)? onUrlFetched;
  final bool Function()? isCancelled;

  const SearchAgentSearchRequest({
    required this.query,
    this.onUrlsKnown,
    this.onUrlFetched,
    this.isCancelled,
  });
}

class SearchAgentListener {
  final void Function(String delta)? onThinking;
  final void Function(String thinking)? onSearchThinking;
  final void Function(String query)? onSearchStart;
  final void Function(List<WebSearchResult> results)? onSearchComplete;
  final void Function()? onAnswerStart;
  final void Function(String delta)? onContent;
  final void Function()? onResetContent;

  const SearchAgentListener({
    this.onThinking,
    this.onSearchThinking,
    this.onSearchStart,
    this.onSearchComplete,
    this.onAnswerStart,
    this.onContent,
    this.onResetContent,
  });
}

class SearchAgentOutcome {
  final String content;
  final String thinking;
  final Map<int, String> sourceUrls;
  final int searchCount;
  final bool cancelled;

  const SearchAgentOutcome({
    required this.content,
    required this.thinking,
    required this.sourceUrls,
    required this.searchCount,
    required this.cancelled,
  });
}

class SearchAgent {
  static const defaultMaxSearches = 3;

  final Stream<OllamaMessage> Function(SearchAgentRequest) streamTurn;
  final Future<List<WebSearchResult>> Function(SearchAgentSearchRequest) search;
  final int maxSearches;

  SearchAgent({
    required this.streamTurn,
    required this.search,
    this.maxSearches = defaultMaxSearches,
  });

  Future<SearchAgentOutcome> run({
    required List<OllamaMessage> history,
    required SearchAgentListener listener,
    bool Function()? isCancelled,
  }) async {
    final transcript = <OllamaMessage>[];
    final sourceUrls = <int, String>{};
    var searchCount = 0;
    var idOffset = 0;
    var allThinking = '';
    var lastContent = '';

    while (true) {
      if (isCancelled?.call() == true) {
        return _outcome(lastContent, allThinking, sourceUrls, searchCount, true);
      }

      final turn = await _streamOneTurn(
        history: history,
        transcript: transcript,
        listener: listener,
        isCancelled: isCancelled,
        toolsEnabled: searchCount < maxSearches,
      );
      allThinking += turn.thinking;
      lastContent = turn.content;

      if (turn.cancelled) {
        return _outcome(lastContent, allThinking, sourceUrls, searchCount, true);
      }

      final hasTools = turn.toolCalls.isNotEmpty && searchCount < maxSearches;
      if (!hasTools) {
        if (!turn.answerStarted) {
          listener.onAnswerStart?.call();
          if (turn.content.isNotEmpty) {
            listener.onContent?.call(turn.content);
          }
        }
        return _outcome(
            turn.content, allThinking, sourceUrls, searchCount, false);
      }

      listener.onSearchThinking?.call(turn.thinking);
      if (turn.streamedContent || turn.content.isNotEmpty) {
        listener.onResetContent?.call();
        lastContent = '';
      }

      final executed = await _executeToolCalls(
        turn.toolCalls,
        remaining: maxSearches - searchCount,
        idOffset: idOffset,
        listener: listener,
        isCancelled: isCancelled,
      );
      if (isCancelled?.call() == true || executed.cancelled) {
        return _outcome(lastContent, allThinking, sourceUrls, searchCount, true);
      }
      if (executed.toolMessages.isEmpty) {
        if (!turn.answerStarted) listener.onAnswerStart?.call();
        return _outcome('', allThinking, sourceUrls, searchCount, false);
      }

      transcript.add(OllamaMessage(
        '',
        role: OllamaMessageRole.assistant,
        thinking: turn.thinking.isEmpty ? null : turn.thinking,
        toolCalls: turn.toolCalls,
      ));
      transcript.addAll(executed.toolMessages);
      sourceUrls.addAll(executed.sourceUrls);
      idOffset = executed.nextOffset;
      searchCount += executed.uniqueSearchCount;
    }
  }

  Future<_TurnAccum> _streamOneTurn({
    required List<OllamaMessage> history,
    required List<OllamaMessage> transcript,
    required SearchAgentListener listener,
    required bool Function()? isCancelled,
    required bool toolsEnabled,
  }) async {
    final accum = _TurnAccum();
    final request = SearchAgentRequest(
      history: history,
      transcript: List<OllamaMessage>.from(transcript),
      includeMemory: transcript.isEmpty,
      toolsEnabled: toolsEnabled,
    );

    await for (final chunk in streamTurn(request)) {
      if (isCancelled?.call() == true) {
        accum.cancelled = true;
        return accum;
      }
      _ingestChunk(chunk, accum, listener);
    }
    if (isCancelled?.call() == true) accum.cancelled = true;
    return accum;
  }

  void _ingestChunk(
    OllamaMessage chunk,
    _TurnAccum accum,
    SearchAgentListener listener,
  ) {
    if (chunk.toolCalls != null && chunk.toolCalls!.isNotEmpty) {
      accum.toolCalls.addAll(chunk.toolCalls!);
      if (accum.streamedContent) {
        listener.onResetContent?.call();
        accum.content = '';
        accum.streamedContent = false;
        accum.answerStarted = false;
      }
    }

    final thinking = chunk.thinking;
    if (thinking != null && thinking.isNotEmpty) {
      accum.thinking += thinking;
      listener.onThinking?.call(thinking);
    }

    if (chunk.content.isNotEmpty && accum.toolCalls.isEmpty) {
      if (!accum.answerStarted) {
        listener.onAnswerStart?.call();
        accum.answerStarted = true;
      }
      accum.content += chunk.content;
      listener.onContent?.call(chunk.content);
      accum.streamedContent = true;
    }
  }

  Future<_SearchExec> _executeToolCalls(
    List<OllamaToolCall> toolCalls, {
    required int remaining,
    required int idOffset,
    required SearchAgentListener listener,
    required bool Function()? isCancelled,
  }) async {
    final planned = _planSearches(toolCalls, remaining);
    if (planned.isEmpty) return _SearchExec(nextOffset: idOffset);

    final unique = [for (final p in planned) if (p.kind == _PlanKind.unique) p];
    final formattedByKey = <String, String>{};
    final urls = <int, String>{};
    var offset = idOffset;
    for (final p in unique) {
      if (isCancelled?.call() == true) {
        return _SearchExec(nextOffset: idOffset, cancelled: true);
      }
      listener.onSearchStart?.call(p.query);
      final results = await search(SearchAgentSearchRequest(
        query: p.query,
        isCancelled: isCancelled,
      ));
      if (isCancelled?.call() == true) {
        return _SearchExec(nextOffset: idOffset, cancelled: true);
      }
      listener.onSearchComplete?.call(results);
      formattedByKey[p.key] = results.isEmpty
          ? 'No results found for "${p.query}".'
          : WebSearchService.formatResultsAsContext(results, idOffset: offset);
      urls.addAll(
          WebSearchService.sourceUrlsFromResults(results, idOffset: offset));
      offset += results.length;
    }

    final toolMessages = <OllamaMessage>[];
    for (final p in planned) {
      if (p.kind == _PlanKind.unknown) {
        toolMessages.add(OllamaMessage(
          'Unknown tool',
          role: OllamaMessageRole.tool,
          toolName: p.name,
        ));
        continue;
      }
      toolMessages.add(OllamaMessage(
        formattedByKey[p.key] ?? '',
        role: OllamaMessageRole.tool,
        toolName: 'web_search',
      ));
    }

    return _SearchExec(
      toolMessages: toolMessages,
      sourceUrls: urls,
      nextOffset: offset,
      uniqueSearchCount: unique.length,
    );
  }

  List<_Planned> _planSearches(List<OllamaToolCall> toolCalls, int remaining) {
    final planned = <_Planned>[];
    final seen = <String>{};
    var uniqueCount = 0;
    for (final call in toolCalls) {
      if (call.name != 'web_search') {
        planned.add(_Planned.unknown(call.name));
        continue;
      }
      final query = (call.arguments['query']?.toString() ?? '').trim();
      if (query.isEmpty) continue;
      final key = _normalizeQuery(query);
      if (seen.contains(key)) {
        planned.add(_Planned.dupe(query, key));
        continue;
      }
      if (uniqueCount >= remaining) continue;
      seen.add(key);
      uniqueCount++;
      planned.add(_Planned.unique(query, key));
    }
    return planned;
  }

  static String _normalizeQuery(String query) =>
      query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  SearchAgentOutcome _outcome(
    String content,
    String thinking,
    Map<int, String> sourceUrls,
    int searchCount,
    bool cancelled,
  ) {
    return SearchAgentOutcome(
      content: content,
      thinking: thinking,
      sourceUrls: Map<int, String>.from(sourceUrls),
      searchCount: searchCount,
      cancelled: cancelled,
    );
  }
}

class _TurnAccum {
  String thinking = '';
  String content = '';
  final toolCalls = <OllamaToolCall>[];
  bool streamedContent = false;
  bool answerStarted = false;
  bool cancelled = false;
}

enum _PlanKind { unique, dupe, unknown }

class _Planned {
  final _PlanKind kind;
  final String query;
  final String key;
  final String name;

  const _Planned({
    required this.kind,
    this.query = '',
    this.key = '',
    this.name = 'web_search',
  });

  factory _Planned.unique(String query, String key) =>
      _Planned(kind: _PlanKind.unique, query: query, key: key);

  factory _Planned.dupe(String query, String key) =>
      _Planned(kind: _PlanKind.dupe, query: query, key: key);

  factory _Planned.unknown(String name) =>
      _Planned(kind: _PlanKind.unknown, name: name);
}

class _SearchExec {
  final List<OllamaMessage> toolMessages;
  final Map<int, String> sourceUrls;
  final int nextOffset;
  final int uniqueSearchCount;
  final bool cancelled;

  _SearchExec({
    this.toolMessages = const [],
    this.sourceUrls = const {},
    required this.nextOffset,
    this.uniqueSearchCount = 0,
    this.cancelled = false,
  });
}
