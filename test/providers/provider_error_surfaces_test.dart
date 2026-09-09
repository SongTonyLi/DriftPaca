/// What the user sees when OpenRouter fails mid-stream on an HTTP 200.
///
/// This is audit finding #12 pinned at the layer it was actually experienced:
/// the transport swallowed the provider's error frame, `SearchAgent` reported
/// the resulting empty turn as [SearchTerminationReason.converged], and
/// `ChatProvider` persisted the blank assistant bubble with no error banner.
/// A rate limit looked exactly like a finished research run that had nothing
/// to say.
///
/// The guarantee now: the failure reaches [ChatProvider.currentChatError] like
/// any other provider failure, the bubble the research panel was opened into
/// is taken back down because it never received a single token, and nothing is
/// written to the database.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llamaseek/Models/agent_memory.dart';
import 'package:llamaseek/Models/conversation_memory.dart';
import 'package:llamaseek/Models/model_capabilities.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/database_service.dart';
import 'package:llamaseek/Services/memory_service.dart';
import 'package:llamaseek/Services/ollama_service.dart';
import 'package:llamaseek/Services/web_search_service.dart';

/// HTTP 200, one `data:` frame carrying only an `error` object, then `[DONE]`
/// — how OpenRouter reports a provider failure that happens after streaming
/// has begun, and therefore past every status-code guard in the transport.
const _errorFrameBody = 'data: {"error":{"code":429,"message":"Provider '
    'returned error: rate limited","metadata":{"provider_name":"Together"}}}\n'
    '\n'
    'data: [DONE]\n\n';

class _Db extends DatabaseService {
  final ready = Completer<void>();
  final OllamaChat chat = OllamaChat(id: 'test', model: 'openai/test');
  final persisted = <OllamaMessage>[];

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
      {required OllamaChat chat}) async {
    persisted.add(message);
  }

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

/// The real OpenRouter transport over a client that answers every request —
/// the goal derivation and the first research turn alike — with the error
/// frame. Nothing about the failure is faked above the socket.
class _Ollama extends OllamaService {
  _Ollama()
      : super(
          client: MockClient((_) async => http.Response(
                _errorFrameBody,
                200,
                headers: {'content-type': 'text/event-stream'},
              )),
        );

  @override
  Future<ModelCapabilities?> getCapabilities(String model) async =>
      const ModelCapabilities(tools: true);
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('provider_error_surfaces');
    Hive.init(temp.path);
    await Hive.openBox('settings');
    await Hive.box('settings').put('serverMode', 'openrouter');
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  setUp(() {
    ChatProvider.searchServiceFactory = WebSearchService.new;
  });

  test('a mid-stream provider error reaches the user as an error, not as a '
      'blank answer', () async {
    final db = _Db();
    final memory = _Memory(db);
    final ollama = _Ollama();
    final provider = ChatProvider(
        ollamaService: ollama, databaseService: db, memoryService: memory);
    addTearDown(provider.dispose);
    addTearDown(memory.dispose);
    await db.ready.future;
    await _flush();
    provider.destinationChatSelected(1);
    await _flush();

    await provider
        .sendPrompt(provider.displayUserMessage('What changed this week?'),
            searchAttemptsRemaining: 1)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('the failed run never returned'),
        );

    expect(provider.currentChatError, isNotNull,
        reason: 'the run failed, so the chat must carry an error — this is '
            'the banner that used to be absent because nothing ever threw');
    expect(provider.currentChatError!.message, contains('Too many requests'),
        reason: 'a 429 reported inside a 200 stream is worded exactly like a '
            '429 reported as an HTTP status');
    expect(provider.currentChatError!.message, contains('rate limited'),
        reason: 'the provider text survives all the way to the user instead '
            'of being dropped by parseCompletion');

    expect(provider.messages.map((m) => m.role), [OllamaMessageRole.user],
        reason: 'the bubble SearchAgent opened for the research panel never '
            'received a token, so it is taken back down rather than left on '
            'screen as an empty assistant turn beside the error');
    expect(
      db.persisted.where((m) => m.role == OllamaMessageRole.assistant),
      isEmpty,
      reason: 'nothing is written for a run that produced nothing; the blank '
          'message used to be persisted and would come back on reload',
    );
    expect(provider.isCurrentChatStreaming, isFalse,
        reason: 'the run is over — it failed');
  });
}
