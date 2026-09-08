import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:llamaseek/Models/agent_memory.dart';
import 'package:llamaseek/Models/conversation_memory.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/database_service.dart';
import 'package:llamaseek/Services/memory_service.dart';
import 'package:llamaseek/Services/ollama_service.dart';
import 'package:llamaseek/Services/web_search_service.dart';

class _Db extends DatabaseService {
  final ready = Completer<void>();
  final OllamaChat chat =
      OllamaChat(id: 'test', model: 'deepseek/deepseek-v4-pro');

  @override
  Future<void> open(String databaseFile) async {}
  @override
  Future<List<OllamaChat>> getAllChats() async {
    ready.complete();
    return [chat];
  }

  @override
  Future<List<OllamaMessage>> getMessages(String chatId) async => [];
  @override
  Future<void> addMessage(OllamaMessage message,
      {required OllamaChat chat}) async {}
  @override
  Future<OllamaChat?> getChatWithLastUpdate(String chatId) async => chat;
}

class _Memory extends MemoryService {
  _Memory(DatabaseService db) : super(db: db);

  @override
  Future<void> processForgetQueue() async {}
  @override
  Future<ConversationMemory?> getConversationMemory(String chatId) async =>
      null;
  @override
  Future<AgentMemory?> getAgentMemory() async => null;
  @override
  Future<String> selectRelevantContext(List<OllamaMessage> recentMessages,
          {String? conversationSummary}) async =>
      '';
  @override
  void triggerMemoryUpdate(
      {required String chatId,
      required List<OllamaMessage> messages,
      bool skipAgentMemory = false}) {}
}

class _Search extends WebSearchService {
  @override
  Future<List<WebSearchResult>> searchAndExtract(
    String query, {
    int maxResults = 8,
    void Function(List<WebSearchResult> urls)? onUrlsKnown,
    void Function(String url, bool success)? onUrlFetched,
    bool Function()? isCancelled,
    Set<String> excludeUrls = const {},
  }) async =>
      [
        WebSearchResult(
          title: 'A source',
          snippet: 'The batch was decided in mid-September.',
          url: 'https://example.com/offboarding',
          pageContent: 'The batch was decided in mid-September.',
          chunks: const ['The batch was decided in mid-September.'],
        ),
      ];
}

String _sse(Map<String, dynamic> json) => 'data: ${jsonEncode(json)}\n\n';

const _done = 'data: [DONE]\n\n';

String _events(List<String> events) => events.join();

Map<String, dynamic> _delta(Map<String, dynamic> delta, {String? finish}) => {
      'id': 'gen-1',
      'model': 'deepseek/deepseek-v4-pro',
      'choices': [
        {'index': 0, 'delta': delta, 'finish_reason': finish}
      ],
    };

/// Plays the role of OpenRouter for one research run: a goal derivation, a
/// turn that calls web_search, a turn that answers, and the completeness
/// gate — each over a socket that is never closed, the way a keep-alive
/// connection behaves after its last byte.
class _OpenRouter extends http.BaseClient {
  final List<String> kinds = [];
  final controllers = <StreamController<List<int>>>[];

  /// What the answer turn streams; overridable per test.
  String Function() answerBody;

  _OpenRouter({required this.answerBody});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = jsonDecode((request as http.Request).body) as Map;
    final messages = (body['messages'] as List).cast<Map>();
    final system = messages.first['role'] == 'system'
        ? messages.first['content'].toString()
        : '';
    final hasTools = body['tools'] != null;
    final hasToolReply = messages.any((m) => m['role'] == 'tool');

    final String kind;
    final String sse;
    if (system.contains('research brief for a web-search agent')) {
      kind = 'goal';
      sse = _events([
        _sse(_delta({'content': 'GOAL: When was the batch decided?'})),
        _sse(_delta({}, finish: 'stop')),
        _done,
      ]);
    } else if (system.contains('draft answer')) {
      kind = 'gate';
      sse = _events([
        _sse(_delta({'content': 'NONE'})),
        _sse(_delta({}, finish: 'stop')),
        _done,
      ]);
    } else if (hasTools && !hasToolReply) {
      kind = 'tool-turn';
      sse = _events([
        _sse(_delta({
          'tool_calls': [
            {
              'index': 0,
              'id': 'call_1',
              'type': 'function',
              'function': {'name': 'web_search', 'arguments': ''}
            }
          ]
        })),
        _sse(_delta({
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': '{"query":"offboarding batch"}'}
            }
          ]
        })),
        _sse(_delta({}, finish: 'tool_calls')),
        _done,
      ]);
    } else {
      kind = 'answer';
      sse = answerBody();
    }
    kinds.add(kind);

    final controller = StreamController<List<int>>();
    controllers.add(controller);
    controller.add(utf8.encode(sse));
    // Never closed on purpose.
    return http.StreamedResponse(controller.stream, 200,
        headers: {'content-type': 'text/event-stream'});
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('research_run_completion');
    Hive.init(temp.path);
    await Hive.openBox('settings');
    await Hive.box('settings').put('serverMode', 'openrouter');
    await Hive.box('settings').put('openrouterApiKey', 'or-key');
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  setUp(() => ChatProvider.searchServiceFactory = _Search.new);
  tearDown(() => ChatProvider.searchServiceFactory = WebSearchService.new);

  late Duration defaultIdle;
  setUp(() => defaultIdle = OllamaService.streamIdleLimit);
  tearDown(() => OllamaService.streamIdleLimit = defaultIdle);

  Future<void> runToCompletion(ChatProvider provider, _OpenRouter client) =>
      provider
          .sendPrompt(provider.displayUserMessage('When was it decided?'),
              searchAttemptsRemaining: 1)
          .timeout(const Duration(seconds: 5),
              onTimeout: () => fail(
                  'the run never returned; requests seen: ${client.kinds}'));

  Future<ChatProvider> start(_OpenRouter client) async {
    final db = _Db();
    final memory = _Memory(db);
    final ollama = OllamaService(client: client)
      ..isOpenRouterMode = true
      ..apiKey = 'or-key';
    final provider = ChatProvider(
        ollamaService: ollama, databaseService: db, memoryService: memory);
    addTearDown(provider.dispose);
    addTearDown(memory.dispose);
    addTearDown(() async {
      for (final c in client.controllers) {
        await c.close();
      }
    });
    await db.ready.future;
    await _flush();
    provider.destinationChatSelected(1);
    await _flush();
    return provider;
  }

  test('a research run over keep-alive sockets ends when the answer does',
      () async {
    final client = _OpenRouter(
      answerBody: () => _events([
        _sse(_delta({'reasoning': 'Looking at the source. '})),
        _sse(_delta({'content': 'Mid-September'})),
        _sse(_delta({'content': ', per the source [1].'})),
        _sse(_delta({}, finish: 'stop')),
        // OpenRouter's trailing usage chunk repeats finish_reason.
        _sse({
          ..._delta({}, finish: 'stop'),
          'usage': {'prompt_tokens': 10, 'completion_tokens': 5},
        }),
        _done,
      ]),
    );
    final provider = await start(client);

    await runToCompletion(provider, client);

    expect(client.kinds, ['goal', 'tool-turn', 'answer', 'gate']);
    expect(provider.isCurrentChatStreaming, isFalse);
    expect(provider.messages.last.content, contains('Mid-September'));
  });

  test('an answer that reports finish_reason but no [DONE] still ends the run',
      () async {
    // Hosts behind OpenRouter differ on which end-of-response marker they
    // send. A model that says it is finished IS finished — waiting for a
    // sentinel that never comes, on a socket nobody closes, is the stuck
    // state again.
    final client = _OpenRouter(
      answerBody: () => _events([
        _sse(_delta({'content': 'Mid-September, per the source [1].'})),
        _sse(_delta({}, finish: 'stop')),
      ]),
    );
    final provider = await start(client);

    await runToCompletion(provider, client);

    expect(client.kinds, ['goal', 'tool-turn', 'answer', 'gate']);
    expect(provider.isCurrentChatStreaming, isFalse);
    expect(provider.messages.last.content, contains('Mid-September'));
  });

  test('an answer whose upstream goes silent after the last token still '
      'ends the run', () async {
    // No finish_reason, no [DONE], and a connection the edge keeps open:
    // the one case no marker can cover. The idle limit is what ends it,
    // and the answer already in hand is kept.
    OllamaService.streamIdleLimit = const Duration(milliseconds: 100);
    final client = _OpenRouter(
      answerBody: () => _events([
        _sse(_delta({'content': 'Mid-September'})),
        _sse(_delta({'content': ', per the source [1].'})),
      ]),
    );
    final provider = await start(client);

    await runToCompletion(provider, client);

    expect(client.kinds, ['goal', 'tool-turn', 'answer', 'gate']);
    expect(provider.isCurrentChatStreaming, isFalse);
    expect(provider.messages.last.content, contains('per the source'));
  });
}
