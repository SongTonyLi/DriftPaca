import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Services/search_agent.dart';
import 'package:llamaseek/Services/web_search_service.dart';

final history = [
  OllamaMessage('What is Vietnam GDP?', role: OllamaMessageRole.user),
];

OllamaMessage answerChunk(String content, {String? thinking}) => OllamaMessage(
      content,
      role: OllamaMessageRole.assistant,
      thinking: thinking,
    );

OllamaMessage searchChunk(String query, {String? thinking}) => OllamaMessage(
      '',
      role: OllamaMessageRole.assistant,
      thinking: thinking,
      toolCalls: [
        OllamaToolCall(name: 'web_search', arguments: {'query': query}),
      ],
    );

WebSearchResult hit(String url, {String title = 'T'}) => WebSearchResult(
      title: title,
      snippet: 'S',
      url: url,
      pageContent: 'body',
    );

SearchAgent agent({
  required Stream<OllamaMessage> Function(SearchAgentRequest) streamTurn,
  Future<List<WebSearchResult>> Function(SearchAgentSearchRequest)? search,
  int maxSearches = 3,
}) {
  return SearchAgent(
    maxSearches: maxSearches,
    streamTurn: streamTurn,
    search: search ??
        (req) async => [hit('https://example.com/${req.query}')],
  );
}

void main() {
  test('no tool_calls answers directly with tools and memory on first turn', () async {
    final requests = <SearchAgentRequest>[];
    final outcome = await agent(
      streamTurn: (req) {
        requests.add(req);
        return Stream.fromIterable([answerChunk('plain answer')]);
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(outcome.content, 'plain answer');
    expect(outcome.searchCount, 0);
    expect(outcome.cancelled, isFalse);
    expect(requests, hasLength(1));
    expect(requests.single.toolsEnabled, isTrue);
    expect(requests.single.includeMemory, isTrue);
  });

  test('one search then answer; transcript is assistant+tool; memory off', () async {
    final requests = <SearchAgentRequest>[];
    var turn = 0;
    final outcome = await agent(
      streamTurn: (req) {
        requests.add(req);
        turn++;
        if (turn == 1) {
          return Stream.fromIterable(
              [searchChunk('Vietnam GDP', thinking: 'need search')]);
        }
        return Stream.fromIterable([answerChunk('GDP is X [1]')]);
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(outcome.searchCount, 1);
    expect(outcome.content, 'GDP is X [1]');
    expect(requests, hasLength(2));
    expect(requests[0].includeMemory, isTrue);
    expect(requests[0].toolsEnabled, isTrue);
    expect(requests[1].includeMemory, isFalse);
    expect(requests[1].transcript, hasLength(2));
    expect(requests[1].transcript[0].role, OllamaMessageRole.assistant);
    expect(requests[1].transcript[0].toolCalls, isNotEmpty);
    expect(requests[1].transcript[0].thinking, 'need search');
    expect(requests[1].transcript[1].role, OllamaMessageRole.tool);
    expect(requests[1].transcript[1].toolName, 'web_search');
  });

  test('two sequential searches accumulate source ids 1 then 2', () async {
    final requests = <SearchAgentRequest>[];
    var turn = 0;
    final outcome = await agent(
      streamTurn: (req) {
        requests.add(req);
        turn++;
        if (turn == 1) return Stream.fromIterable([searchChunk('Vietnam')]);
        if (turn == 2) return Stream.fromIterable([searchChunk('Thailand')]);
        return Stream.fromIterable([answerChunk('done')]);
      },
      search: (req) async => [
        hit(req.query == 'Vietnam'
            ? 'https://example.com/vn'
            : 'https://example.com/th'),
      ],
    ).run(history: history, listener: const SearchAgentListener());

    expect(outcome.searchCount, 2);
    expect(outcome.sourceUrls[1], 'https://example.com/vn');
    expect(outcome.sourceUrls[2], 'https://example.com/th');
    expect(requests[1].transcript.last.content, contains('id="1"'));
    expect(requests[2].transcript.last.content, contains('id="2"'));
  });

  test('two tool_calls in one turn run start-then-search in order', () async {
    final events = <String>[];
    var turn = 0;
    final outcome = await agent(
      streamTurn: (req) {
        turn++;
        if (turn == 1) {
          return Stream.fromIterable([
            OllamaMessage(
              '',
              role: OllamaMessageRole.assistant,
              toolCalls: [
                const OllamaToolCall(
                    name: 'web_search', arguments: {'query': 'Vietnam GDP'}),
                const OllamaToolCall(
                    name: 'web_search', arguments: {'query': 'Thailand GDP'}),
              ],
            ),
          ]);
        }
        return Stream.fromIterable([answerChunk('both')]);
      },
      search: (req) async {
        events.add('search:${req.query}');
        await Future<void>.delayed(const Duration(milliseconds: 15));
        return [hit('https://example.com/${req.query}', title: req.query)];
      },
    ).run(
      history: history,
      listener: SearchAgentListener(
        onSearchStart: (q) => events.add('start:$q'),
        onSearchComplete: (r) => events.add('complete:${r.single.title}'),
      ),
    );

    expect(events, [
      'start:Vietnam GDP',
      'search:Vietnam GDP',
      'complete:Vietnam GDP',
      'start:Thailand GDP',
      'search:Thailand GDP',
      'complete:Thailand GDP',
    ]);
    expect(outcome.searchCount, 2);
    expect(outcome.sourceUrls.keys.toList()..sort(), [1, 2]);
  });

  test('dedupes identical queries case-insensitively', () async {
    final queries = <String>[];
    var turn = 0;
    final outcome = await agent(
      streamTurn: (req) {
        turn++;
        if (turn == 1) {
          return Stream.fromIterable([
            OllamaMessage(
              '',
              role: OllamaMessageRole.assistant,
              toolCalls: [
                const OllamaToolCall(
                    name: 'web_search', arguments: {'query': 'Vietnam GDP'}),
                const OllamaToolCall(
                    name: 'web_search', arguments: {'query': 'vietnam gdp'}),
              ],
            ),
          ]);
        }
        return Stream.fromIterable([answerChunk('one search')]);
      },
      search: (req) async {
        queries.add(req.query);
        return [hit('https://example.com/vn')];
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(queries, ['Vietnam GDP']);
    expect(outcome.searchCount, 1);
  });

  test('after max 3 searches the last turn disables tools', () async {
    final requests = <SearchAgentRequest>[];
    final outcome = await agent(
      streamTurn: (req) {
        requests.add(req);
        if (req.toolsEnabled) {
          return Stream.fromIterable([searchChunk('q${requests.length}')]);
        }
        return Stream.fromIterable([answerChunk('must answer')]);
      },
    ).run(history: history, listener: const SearchAgentListener());

    expect(outcome.searchCount, 3);
    expect(requests, hasLength(4));
    expect(requests.take(3).every((r) => r.toolsEnabled), isTrue);
    expect(requests.last.toolsEnabled, isFalse);
    expect(outcome.content, 'must answer');
  });

  test('cancel during search skips the next model turn', () async {
    var cancelled = false;
    var turns = 0;
    final outcome = await agent(
      streamTurn: (req) {
        turns++;
        return Stream.fromIterable([searchChunk('Vietnam GDP')]);
      },
      search: (req) async {
        cancelled = true;
        return [hit('https://example.com/vn')];
      },
    ).run(
      history: history,
      listener: const SearchAgentListener(),
      isCancelled: () => cancelled,
    );

    expect(outcome.cancelled, isTrue);
    expect(turns, 1);
  });

  test('preamble content then tool_calls resets streamed content', () async {
    var resets = 0;
    var turn = 0;
    final contents = <String>[];
    final outcome = await agent(
      streamTurn: (req) {
        turn++;
        if (turn == 1) {
          return Stream.fromIterable([
            answerChunk('Let me look that up.'),
            searchChunk('Vietnam GDP'),
          ]);
        }
        return Stream.fromIterable([answerChunk('Final [1]')]);
      },
    ).run(
      history: history,
      listener: SearchAgentListener(
        onResetContent: () => resets++,
        onContent: contents.add,
      ),
    );

    expect(resets, greaterThanOrEqualTo(1));
    expect(outcome.content, 'Final [1]');
    expect(contents.last, 'Final [1]');
  });
}
