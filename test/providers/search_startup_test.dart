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

  _Db({bool incognito = false}) : chat = OllamaChat(id: 'test', model: 'openai/test', isIncognito: incognito);

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
      yield OllamaMessage(await goal.future, role: OllamaMessageRole.assistant);
    } else {
      turnStarted = true;
      receivedContext = relevantContext;
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

  test('goal and memory prepare concurrently before the first research turn', () async {
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
    final goalStartedBeforeMemory = ollama.goalStarted;
    memory.conversation.complete(ConversationMemory(summary: 'Summary'));
    await _flush();
    final selectionStartedBeforeGoal = memory.selectionStarted;
    memory.selection.complete('Relevant memory');
    ollama.goal.complete('GOAL: Find what is new');
    await run;

    expect(goalStartedBeforeMemory, isTrue, reason: 'The isolated goal request does not depend on memory reads.');
    expect(selectionStartedBeforeGoal, isTrue, reason: 'Memory selection must overlap the goal model request.');
    expect(memory.selectedSummary, 'Summary');
    expect(ollama.turnStarted, isTrue);
    expect(ollama.receivedContext, 'Relevant memory');
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
