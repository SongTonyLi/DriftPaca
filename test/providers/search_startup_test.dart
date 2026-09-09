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

class _Db extends DatabaseService {
  final ready = Completer<void>();
  final OllamaChat chat;

  /// The turns already in the chat when the prompt under test is sent.
  final List<OllamaMessage> priorMessages;

  _Db({bool incognito = false, this.priorMessages = const []})
      : chat = OllamaChat(id: 'test', model: 'openai/test', isIncognito: incognito);

  @override
  Future<void> open(String databaseFile) async {}
  @override
  Future<List<OllamaChat>> getAllChats() async {
    ready.complete();
    return [chat];
  }

  @override
  Future<List<OllamaMessage>> getMessages(String chatId) async => List.of(priorMessages);
  @override
  Future<void> addMessage(OllamaMessage message, {required OllamaChat chat}) async {}
  @override
  Future<OllamaChat?> getChatWithLastUpdate(String chatId) async => chat;
}

class _Memory extends MemoryService {
  final conversation = Completer<ConversationMemory?>();
  final selection = Completer<String>();
  bool selectionStarted = false;
  int profileReads = 0;
  String? selectedSummary;

  _Memory(DatabaseService db) : super(db: db);

  @override
  Future<void> processForgetQueue() async {}
  @override
  Future<ConversationMemory?> getConversationMemory(String chatId) => conversation.future;
  @override
  Future<AgentMemory?> getAgentMemory() async {
    profileReads++;
    return AgentMemory(name: 'Sam');
  }

  @override
  Future<String> selectRelevantContext(List<OllamaMessage> recentMessages, {String? conversationSummary}) {
    selectionStarted = true;
    selectedSummary = conversationSummary;
    return selection.future;
  }

  @override
  void triggerMemoryUpdate(
      {required String chatId, required List<OllamaMessage> messages, bool skipAgentMemory = false}) {}
}

class _Ollama extends OllamaService {
  final goal = Completer<String>();
  bool goalStarted = false;
  bool turnStarted = false;
  String? receivedContext;
  String? receivedSystemPrompt;

  /// What the goal request was given: its messages, and the memory the
  /// chatStream call itself carried (none — the goal call renders memory
  /// into its user turn instead).
  List<OllamaMessage>? goalMessages;
  String? goalRelevantContext;
  ConversationMemory? goalConversationMemory;

  @override
  Future<ModelCapabilities?> getCapabilities(String model) async => const ModelCapabilities(tools: true);

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
    if (tools == null) {
      goalStarted = true;
      goalMessages = messages;
      goalRelevantContext = relevantContext;
      goalConversationMemory = conversationMemory;
      yield OllamaMessage(await goal.future, role: OllamaMessageRole.assistant);
    } else {
      turnStarted = true;
      receivedContext = relevantContext;
      receivedSystemPrompt = chat.systemPrompt;
      yield OllamaMessage('Answer', role: OllamaMessageRole.assistant);
    }
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('search_startup');
    Hive.init(temp.path);
    await Hive.openBox('settings');
    await Hive.box('settings').put('serverMode', 'openrouter');
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('the goal call reads the memory the first turn will use, and waits for '
      'the retrieval pass rather than duplicating it', () async {
    // The goal call used to start blind, in parallel with memory. It now
    // waits (briefly — see goalContextBudget) for the same two memory
    // stages the first turn awaits, so a clarification is only asked when
    // nothing already known settles it. Retrieval runs once, for both.
    final db = _Db();
    final memory = _Memory(db);
    final ollama = _Ollama();
    final provider = ChatProvider(ollamaService: ollama, databaseService: db, memoryService: memory);
    addTearDown(provider.dispose);
    addTearDown(memory.dispose);
    await db.ready.future;
    await _flush();
    provider.destinationChatSelected(1);
    await _flush();
    final prompt = provider.displayUserMessage('What is new?');
    final run = provider.sendPrompt(prompt, searchAttemptsRemaining: 1);
    await _flush();
    expect(ollama.goalStarted, isFalse,
        reason: 'the goal call waits for the stored memory to be read');
    memory.conversation.complete(ConversationMemory(summary: 'Summary'));
    await _flush();
    expect(memory.selectionStarted, isTrue);
    expect(ollama.goalStarted, isFalse,
        reason: 'and for the retrieval pass, while it is quick');
    memory.selection.complete('Relevant memory');
    await _flush();
    expect(ollama.goalStarted, isTrue);
    ollama.goal.complete('GOAL: Find what is new');
    await run;

    expect(memory.selectedSummary, 'Summary');
    expect(memory.profileReads, 1, reason: 'the profile is read once for both');
    expect(ollama.turnStarted, isTrue);
    expect(ollama.receivedContext, 'Relevant memory');
    // The goal call carries memory in its own user turn, not through the
    // answering turn's injection.
    expect(ollama.goalRelevantContext, isEmpty);
    expect(ollama.goalConversationMemory, isNull);
    final goalTurn = ollama.goalMessages!.single.content;
    expect(goalTurn, contains('Relevant memory'));
    expect(goalTurn, contains('Sam'));
    expect(goalTurn, endsWith('What is new?'));
  });

  test('a slow retrieval pass costs the goal call its notes, not its start', () async {
    final defaultBudget = ChatProvider.goalContextBudget;
    ChatProvider.goalContextBudget = const Duration(milliseconds: 20);
    addTearDown(() {
      ChatProvider.goalContextBudget = defaultBudget;
    });
    final db = _Db();
    final memory = _Memory(db);
    final ollama = _Ollama();
    final provider = ChatProvider(ollamaService: ollama, databaseService: db, memoryService: memory);
    addTearDown(provider.dispose);
    addTearDown(memory.dispose);
    await db.ready.future;
    await _flush();
    provider.destinationChatSelected(1);
    await _flush();
    final run = provider.sendPrompt(provider.displayUserMessage('What is new?'), searchAttemptsRemaining: 1);
    await _flush();
    memory.conversation.complete(ConversationMemory(summary: 'Summary'));
    // memory.selection is left hanging past the budget.
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(ollama.goalStarted, isTrue,
        reason: 'the goal call goes ahead with what has arrived');
    expect(ollama.goalMessages!.single.content, contains('Sam'),
        reason: 'the stored stage did arrive');
    expect(ollama.goalMessages!.single.content, isNot(contains('Relevant memory')));
    expect(ollama.turnStarted, isFalse,
        reason: 'the first turn still waits for the full retrieval');

    memory.selection.complete('Relevant memory');
    ollama.goal.complete('GOAL: Find what is new');
    await run;
    expect(ollama.receivedContext, 'Relevant memory');
  });

  test('the goal call sees the earlier turns, and the message it is briefing last',
      () async {
    // The bug this guards: a follow-up like "and its moons?" reached the
    // derivation with no referent, and "which Mercury?" was asked of a
    // user who had just spent a turn on the planet.
    final db = _Db(priorMessages: [
      OllamaMessage('Tell me about Mercury, the planet', role: OllamaMessageRole.user),
      OllamaMessage('Mercury is the innermost planet…', role: OllamaMessageRole.assistant),
    ]);
    final memory = _Memory(db);
    final ollama = _Ollama();
    final provider = ChatProvider(ollamaService: ollama, databaseService: db, memoryService: memory);
    addTearDown(provider.dispose);
    addTearDown(memory.dispose);
    await db.ready.future;
    await _flush();
    provider.destinationChatSelected(1);
    await _flush();
    final run = provider.sendPrompt(provider.displayUserMessage('and its moons?'), searchAttemptsRemaining: 1);
    await _flush();
    memory.conversation.complete(null);
    memory.selection.complete('');
    await _flush();

    final goalTurn = ollama.goalMessages!.single.content;
    expect(goalTurn, contains('Earlier turns of this conversation:'));
    expect(goalTurn, contains('User: Tell me about Mercury, the planet'));
    expect(goalTurn, contains('Assistant: Mercury is the innermost planet…'));
    expect(goalTurn, endsWith('and its moons?'));
    expect(goalTurn.indexOf('the planet'), lessThan(goalTurn.indexOf('and its moons?')));

    ollama.goal.complete('GOAL: Find the moons of the planet Mercury');
    await run;
    expect(ollama.receivedSystemPrompt, contains('Goal: Find the moons of the planet Mercury'));
  });

  test('the research panel has a bubble to render into while the goal call '
      'is still out', () async {
    // Search segments are handed to the index-0 message, so without an
    // assistant bubble the panel SearchAgent opens ahead of the derivation
    // has nowhere to go — and the skeleton loader hides as soon as a
    // segment exists, leaving the run showing nothing at all.
    final db = _Db();
    final memory = _Memory(db);
    final ollama = _Ollama();
    final provider = ChatProvider(ollamaService: ollama, databaseService: db, memoryService: memory);
    addTearDown(provider.dispose);
    addTearDown(memory.dispose);
    await db.ready.future;
    await _flush();
    provider.destinationChatSelected(1);
    await _flush();
    final run = provider.sendPrompt(provider.displayUserMessage('What is new?'), searchAttemptsRemaining: 1);
    await _flush();
    memory.conversation.complete(ConversationMemory(summary: 'Summary'));
    memory.selection.complete('Relevant memory');
    await _flush();

    expect(ollama.goalStarted, isTrue);
    expect(ollama.turnStarted, isFalse, reason: 'the derivation has not returned yet');
    expect(provider.messages.map((m) => m.role),
        [OllamaMessageRole.user, OllamaMessageRole.assistant]);

    ollama.goal.complete('GOAL: Find what is new');
    await run;
  });

  test('a stalled goal derivation does not hold up the first research turn',
      () async {
    // The framing call is the first thing a run does and nothing else can
    // start until it answers. Unbounded, a model that never replies (or
    // spends a minute reasoning about how to phrase the goal) is the whole
    // wait before the first search — so past the budget the run drops it
    // and keeps the user's question as the objective, which is what every
    // other derivation failure already falls back to.
    final defaultBudget = ChatProvider.goalDerivationBudget;
    ChatProvider.goalDerivationBudget = const Duration(milliseconds: 20);
    addTearDown(() {
      ChatProvider.goalDerivationBudget = defaultBudget;
    });
    final db = _Db();
    final memory = _Memory(db);
    final ollama = _Ollama();
    final provider = ChatProvider(ollamaService: ollama, databaseService: db, memoryService: memory);
    addTearDown(provider.dispose);
    addTearDown(memory.dispose);
    await db.ready.future;
    await _flush();
    provider.destinationChatSelected(1);
    await _flush();
    final run = provider.sendPrompt(provider.displayUserMessage('What is new?'), searchAttemptsRemaining: 1);
    await _flush();
    memory.conversation.complete(ConversationMemory(summary: 'Summary'));
    memory.selection.complete('Relevant memory');
    // ollama.goal is deliberately never completed: the derivation request
    // hangs for the rest of the test.
    await run;

    expect(ollama.goalStarted, isTrue);
    expect(ollama.turnStarted, isTrue,
        reason: 'research starts anyway once the budget is spent');
    expect(ollama.receivedSystemPrompt, contains('Goal: What is new?'),
        reason: 'the run falls back to the question the user actually asked');
  });

  for (final incognito in [false, true]) {
    test(
        incognito
            ? 'incognito research never retrieves global memory'
            : 'cancellation during memory preparation prevents the research request', () async {
      final db = _Db(incognito: incognito);
      final memory = _Memory(db);
      final ollama = _Ollama();
      final provider = ChatProvider(ollamaService: ollama, databaseService: db, memoryService: memory);
      addTearDown(provider.dispose);
      addTearDown(memory.dispose);
      await db.ready.future;
      await _flush();
      provider.destinationChatSelected(1);
      await _flush();
      final run = provider.sendPrompt(provider.displayUserMessage('What is new?'), searchAttemptsRemaining: 1);
      await _flush();
      ollama.goal.complete('GOAL: Find what is new');
      await _flush();
      expect(ollama.turnStarted, isFalse);
      if (!incognito) provider.cancelCurrentStreaming();
      memory.conversation.complete(ConversationMemory(summary: 'Summary'));
      await run;
      expect(memory.selectionStarted, isFalse);
      expect(ollama.turnStarted, incognito);
      if (incognito) {
        expect(memory.profileReads, 0);
        expect(ollama.receivedContext, isEmpty);
      }
    });
  }
}
