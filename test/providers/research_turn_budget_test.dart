/// The provider-level half of audit finding #1: a research turn whose model
/// request goes silent must not leave the app generating forever, and the
/// stop button must be able to end one.
///
/// Sibling of `coverage_gate_budget_test.dart`, which pins the same
/// guarantee for the completeness gate. The research turn is the third and
/// largest of the three model calls a run is made of, and it was the one
/// with no budget at all: `ChatProvider.researchTurnIdleBudget` is what
/// wires `SearchAgent.turnIdleBudget` in, and these tests are what prove the
/// wiring reaches production's construction site rather than only the
/// agent's own tests.
///
/// The second test is the one to run first when doubting the fix: before it,
/// pressing stop on a silent turn returned nothing at all, because
/// `cancelCurrentStreaming()` only removes the chat id from
/// `_activeChatStreams` while the run itself keeps going — so `sendPrompt`
/// never completed, and the next message the user sent re-armed the map and
/// handed the zombie run a live `cancelled()` of `false` again.
library;

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

/// A run whose goal derivation answers normally and whose first research
/// turn opens a stream that never delivers anything and never closes — the
/// exact shape a provider queued behind `: OPENROUTER PROCESSING`
/// keep-alives presents to the loop, since the codec drops those frames
/// before they can become chunks.
class _Ollama extends OllamaService {
  /// Completed the first time the research turn is actually subscribed, so
  /// the cancellation test can press stop at a moment that is genuinely
  /// inside the turn rather than racing it.
  final turnStarted = Completer<void>();
  final _turns = <StreamController<OllamaMessage>>[];

  var turnCancelled = false;

  @override
  void dispose() {
    for (final controller in _turns) {
      controller.close().ignore();
    }
    super.dispose();
  }

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
  }) {
    if (tools == null) {
      return Stream.fromIterable([
        OllamaMessage('GOAL: When was the batch decided?',
            role: OllamaMessageRole.assistant),
      ]);
    }
    // The research turn. Deliberately never yields and never closes.
    final controller = StreamController<OllamaMessage>(
      onListen: () {
        if (!turnStarted.isCompleted) turnStarted.complete();
      },
      onCancel: () => turnCancelled = true,
    );
    _turns.add(controller);
    return controller.stream;
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
    temp = await Directory.systemTemp.createTemp('research_turn_budget');
    Hive.init(temp.path);
    await Hive.openBox('settings');
    await Hive.box('settings').put('serverMode', 'openrouter');
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  setUp(() {
    defaultBudget = ChatProvider.researchTurnIdleBudget;
    ChatProvider.searchServiceFactory = _Search.new;
  });
  tearDown(() {
    ChatProvider.researchTurnIdleBudget = defaultBudget;
    ChatProvider.searchServiceFactory = WebSearchService.new;
  });

  test('a stalled research turn does not leave the app generating forever',
      () async {
    // Nothing has reached the screen when this happens — the research panel
    // is open and empty, waiting on a first token that never comes — so an
    // unbounded turn is an indefinite spinner over a blank bubble.
    ChatProvider.researchTurnIdleBudget = const Duration(milliseconds: 20);
    final db = _Db();
    final memory = _Memory(db);
    final ollama = _Ollama();
    final provider = await _startedRun(db, memory, ollama);
    addTearDown(provider.dispose);
    addTearDown(memory.dispose);
    addTearDown(ollama.dispose);

    await provider
        .sendPrompt(provider.displayUserMessage('When was it decided?'),
            searchAttemptsRemaining: 1)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('the run never returned from the research '
              'turn — SearchAgent.turnIdleBudget did not reach production'),
        );

    expect(ollama.turnStarted.isCompleted, isTrue,
        reason: 'the turn has to have actually started, or this proves '
            'nothing about bounding it');
    expect(provider.isCurrentChatStreaming, isFalse,
        reason: 'the stop-generating state is the user-visible symptom: an '
            'app that never leaves it is the 16-minute hang');
    expect(provider.currentChatError, isNotNull,
        reason: 'a stall is nobody\'s request, so it must say so — silently '
            'ending the run would swap an endless spinner for an unexplained '
            'nothing');
    expect(
      provider.messages.where((m) =>
          m.role == OllamaMessageRole.assistant &&
          m.content.isEmpty &&
          (m.thinking ?? '').isEmpty),
      isEmpty,
      reason: 'the bubble the research panel opened before the first token '
          'has nothing in it and must not be left behind next to the error',
    );
  });

  test('stopping the run abandons a research turn that has gone silent',
      () async {
    // The half a deadline cannot fix. With the budget left long, the only
    // thing that can end this run inside five seconds is the cancellation
    // poll — a per-chunk check has no chunk to run on.
    ChatProvider.researchTurnIdleBudget = const Duration(seconds: 30);
    final db = _Db();
    final memory = _Memory(db);
    final ollama = _Ollama();
    final provider = await _startedRun(db, memory, ollama);
    addTearDown(provider.dispose);
    addTearDown(memory.dispose);
    addTearDown(ollama.dispose);

    final run = provider.sendPrompt(
        provider.displayUserMessage('When was it decided?'),
        searchAttemptsRemaining: 1);
    await ollama.turnStarted.future.timeout(const Duration(seconds: 5),
        onTimeout: () => fail('the research turn never started'));
    provider.cancelCurrentStreaming();

    await run.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('stopping did not reach the research turn — the '
          'run keeps going with the chat id already removed from '
          '_activeChatStreams, which is the zombie-run case'),
    );
    // The subscription's cancel is deliberately not awaited by the loop (see
    // SearchAgent._streamOneTurn), so let its teardown land before asking
    // whether it happened.
    await _flush();
    expect(provider.isCurrentChatStreaming, isFalse);
    expect(ollama.turnCancelled, isTrue,
        reason: 'and the abandoned request is cancelled rather than left to '
            'keep the model busy');
  });
}
