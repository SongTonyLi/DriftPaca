import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:llamaseek/Models/agent_memory.dart';
import 'package:llamaseek/Models/conversation_memory.dart';
import 'package:llamaseek/Models/model_capabilities.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/database_service.dart';
import 'package:llamaseek/Services/memory_service.dart';
import 'package:llamaseek/Services/ollama_service.dart';
import 'package:llamaseek/Services/web_search_service.dart';

class _Db extends DatabaseService {
  final ready = Completer<void>();
  final OllamaChat chat = OllamaChat(id: 'test', model: 'openai/test');

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
  Future<void> addMessage(OllamaMessage message, {required OllamaChat chat}) async {}
  @override
  Future<OllamaChat?> getChatWithLastUpdate(String chatId) async => chat;
}

class _Memory extends MemoryService {
  _Memory(DatabaseService db) : super(db: db);

  @override
  Future<void> processForgetQueue() async {}
  @override
  Future<ConversationMemory?> getConversationMemory(String chatId) async => null;
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
          snippet: 'The offboarding batch was decided in mid-September.',
          url: 'https://example.com/offboarding',
          pageContent: 'The offboarding batch was decided in mid-September.',
          chunks: const ['The offboarding batch was decided in mid-September.'],
        ),
      ];
}

/// A run that searches once, answers, and then hands the finished answer to a
/// completeness gate whose request never comes back.
class _Ollama extends OllamaService {
  /// Completed by the test only when it wants the gate to answer; left
  /// hanging otherwise.
  final gate = Completer<String>();
  final gateStarted = Completer<void>();
  var searchTurns = 0;

  @override
  Future<ModelCapabilities?> getCapabilities(String model) async =>
      const ModelCapabilities(tools: true);

  @override
  Stream<OllamaMessage> chatStream(
    List<OllamaMessage> messages, {
    required OllamaChat chat,
    ConversationMemory? conversationMemory,
    AgentMemory? profile,
    String relevantContext = '',
    List<OllamaToolDefinition>? tools,
    List<OllamaMessage> extraMessages = const [],
  }) async* {
    final prompt = chat.systemPrompt ?? '';
    if (tools == null && prompt.contains('draft answer')) {
      if (!gateStarted.isCompleted) gateStarted.complete();
      yield OllamaMessage(await gate.future, role: OllamaMessageRole.assistant);
      return;
    }
    if (tools == null) {
      yield OllamaMessage('GOAL: When was the batch decided?',
          role: OllamaMessageRole.assistant);
      return;
    }
    searchTurns++;
    if (searchTurns == 1) {
      yield OllamaMessage(
        '',
        role: OllamaMessageRole.assistant,
        toolCalls: const [
          OllamaToolCall(name: 'web_search', arguments: {'query': 'offboarding batch'}),
        ],
      );
      return;
    }
    yield OllamaMessage('Mid-September, per the source.',
        role: OllamaMessageRole.assistant);
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Future<ChatProvider> _startedRun(
  _Db db,
  _Memory memory,
  _Ollama ollama,
) async {
  final provider = ChatProvider(
      ollamaService: ollama, databaseService: db, memoryService: memory);
  await db.ready.future;
  await _flush();
  provider.destinationChatSelected(1);
  await _flush();
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late Duration defaultBudget;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('coverage_gate_budget');
    Hive.init(temp.path);
    await Hive.openBox('settings');
    await Hive.box('settings').put('serverMode', 'openrouter');
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  setUp(() {
    defaultBudget = ChatProvider.coverageGateBudget;
    ChatProvider.searchServiceFactory = _Search.new;
  });
  tearDown(() {
    ChatProvider.coverageGateBudget = defaultBudget;
    ChatProvider.searchServiceFactory = WebSearchService.new;
  });

  test('a stalled completeness gate does not keep the run generating after '
      'the answer is done', () async {
    // The gate runs after the answer has finished streaming and shows the
    // user nothing while it thinks, so a request that never comes back
    // leaves a finished answer on screen with the app still generating and
    // the chat still called "New Chat" — the title only gets written once
    // the run returns.
    ChatProvider.coverageGateBudget = const Duration(milliseconds: 20);
    final db = _Db();
    final memory = _Memory(db);
    final ollama = _Ollama();
    final provider = await _startedRun(db, memory, ollama);
    addTearDown(provider.dispose);
    addTearDown(memory.dispose);

    // ollama.gate is deliberately never completed.
    await provider
        .sendPrompt(provider.displayUserMessage('When was it decided?'),
            searchAttemptsRemaining: 1)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('the run never returned from the gate'),
        );

    expect(ollama.gateStarted.isCompleted, isTrue);
    expect(provider.isCurrentChatStreaming, isFalse);
    expect(provider.messages.last.content, 'Mid-September, per the source.',
        reason: 'giving up on the gate keeps the answer already in hand');
  });

  test('stopping the run abandons a gate request that is still out', () async {
    // Nothing arrives on a stalled request, so a cancellation check that only
    // runs per chunk can never fire on it: the run would sit out the rest of
    // its budget on work the user has already walked away from.
    ChatProvider.coverageGateBudget = const Duration(seconds: 30);
    final db = _Db();
    final memory = _Memory(db);
    final ollama = _Ollama();
    final provider = await _startedRun(db, memory, ollama);
    addTearDown(provider.dispose);
    addTearDown(memory.dispose);

    final run = provider.sendPrompt(
        provider.displayUserMessage('When was it decided?'),
        searchAttemptsRemaining: 1);
    await ollama.gateStarted.future
        .timeout(const Duration(seconds: 5), onTimeout: () => fail('the gate never ran'));
    provider.cancelCurrentStreaming();

    await run.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('stopping did not reach the gate request'),
    );
    expect(provider.isCurrentChatStreaming, isFalse);
  });
}
