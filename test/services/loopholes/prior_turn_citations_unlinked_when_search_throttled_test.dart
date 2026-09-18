/// Regression: a follow-up answer that cites sources from an EARLIER turn
/// gets those citations linked (and so rendered as favicons), even when the
/// current turn's own searches produced nothing.
///
/// The defect, as seen in the field: turn 1 ("北元灭国史") searched, and its
/// answer shipped with `[³](url)`-style links. Turn 2 ("鞑靼与瓦剌的历史")
/// hit the search engine's rate limit, so `SearchAgent` told the model to
/// answer "from the sources already gathered" — which it did, citing
/// `[3][10][12]...` exactly as those ids appeared in turn 1's answer. But
/// `ChatProvider._streamWithNativeTools` resolved citations only against
/// the id→URL map of the CURRENT run, which was empty, so every citation
/// stayed as raw `[3][10]` text with no favicon.
///
/// The fix seeds that map with `ChatProvider.citationUrlsFromHistory`, the
/// ids read back from the links already rendered into earlier answers in
/// the chat, and layers the run's own sources on top.
///
/// This runs the whole production path — `sendPrompt` →
/// `_streamOllamaMessage` → `_streamWithNativeTools` → SearchAgent → a
/// throttled search → the forced answer → `replaceCitationsWithLinks` —
/// against an offline model, search service and database.
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

// Where turn 1's answer pointed its citations.
const _threeUrl = 'https://zh.example/beiyuan/three';
const _tenUrl = 'https://zh.example/beiyuan/ten';

/// Turn 1's answer exactly as the app persisted it: citations already
/// rewritten into superscript markdown links.
const _priorAnswer = '北元汗廷崩溃后，明朝将蒙古本部诸部统称为"鞑靼"[³]($_threeUrl)。'
    '1402年鬼力赤即位[¹⁰]($_tenUrl)。';

/// What the model writes on turn 2, having been told the search was
/// throttled and to answer from the sources already gathered.
const _followUpAnswer = '"鞑靼"本是唐宋时期的泛称[3]，1402年改称鞑靼[10]。';

// ---------------------------------------------------------------------------
// Offline doubles: no network, no model, no real database.
// ---------------------------------------------------------------------------

class _Db extends DatabaseService {
  final ready = Completer<void>();
  final OllamaChat chat = OllamaChat(id: 'probe', model: 'qwen/tools');

  @override
  Future<void> open(String databaseFile) async {}
  @override
  Future<List<OllamaChat>> getAllChats() async {
    if (!ready.isCompleted) ready.complete();
    return [chat];
  }

  /// The chat as the user finds it: turn 1 already answered, with links.
  @override
  Future<List<OllamaMessage>> getMessages(String chatId) async => [
        OllamaMessage('北元灭国史', role: OllamaMessageRole.user),
        OllamaMessage(_priorAnswer,
            role: OllamaMessageRole.assistant, model: 'qwen/tools'),
      ];
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

/// A search engine that is rate-limiting this client: every query fails
/// before reaching the web, which is the condition under test.
class _ThrottledSearch extends WebSearchService {
  int attempts = 0;

  @override
  Future<List<WebSearchResult>> searchAndExtract(
    String query, {
    int maxResults = 8,
    void Function(List<WebSearchResult> urls)? onUrlsKnown,
    void Function(String url, bool success)? onUrlFetched,
    bool Function()? isCancelled,
    Set<String> excludeUrls = const {},
  }) async {
    attempts++;
    throw const WebSearchUnavailableException('HTTP 429');
  }
}

/// A tool-capable model, which routes the run through SearchAgent
/// (`_streamWithNativeTools`) — the path the screenshot came from.
///
/// Answers each of the harness's requests by what it is:
///   * the coverage gate (its own system prompt) — "NONE", nothing missing;
///   * a research turn that may search (tools attached) — one search;
///   * a research turn after research closed (transcript present, no
///     tools) — the answer, citing turn 1's ids;
///   * anything else is the goal-derivation call — a plain goal, no
///     clarification, so the run never pauses on the user.
class _Ollama extends OllamaService {
  List<OllamaMessage>? historySeen;
  List<OllamaMessage>? transcriptSeen;

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
    if (chat.systemPrompt == coverageGateInstruction()) {
      yield OllamaMessage('NONE', role: OllamaMessageRole.assistant);
      return;
    }
    if (tools != null && tools.isNotEmpty) {
      historySeen = messages;
      yield OllamaMessage('', role: OllamaMessageRole.assistant, toolCalls: [
        OllamaToolCall(name: 'web_search', arguments: {'query': '瓦剌 起源'}),
      ]);
      return;
    }
    if (extraMessages.isNotEmpty) {
      transcriptSeen = extraMessages;
      yield OllamaMessage('"鞑靼"本是唐宋时期的泛称[3]，',
          role: OllamaMessageRole.assistant);
      yield OllamaMessage('1402年改称鞑靼[10]。',
          role: OllamaMessageRole.assistant);
      return;
    }
    yield OllamaMessage('GOAL: 鞑靼与瓦剌的历史', role: OllamaMessageRole.assistant);
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late _ThrottledSearch search;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('probe_prior_citations_');
    Hive.init(temp.path);
    await Hive.openBox('settings');
  });
  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });
  setUp(() {
    search = _ThrottledSearch();
    ChatProvider.searchServiceFactory = () => search;
  });
  tearDown(() {
    ChatProvider.searchServiceFactory = WebSearchService.new;
  });

  test(
      'end to end: with this turn\'s search throttled, citations of last '
      'turn\'s sources ship as links to those sources', () async {
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
        .sendPrompt(provider.displayUserMessage('鞑靼与瓦剌的历史'),
            searchAttemptsRemaining: 1)
        .timeout(const Duration(seconds: 10),
            onTimeout: () => fail('the run never returned'));

    // The preconditions that make this the screenshot's situation.
    expect(search.attempts, 1,
        reason: 'the run did try to search, and the engine refused it');
    expect(ollama.transcriptSeen, isNotNull,
        reason: 'the model was asked to answer after the throttled search');
    expect(ollama.transcriptSeen!.map((m) => m.content).join(),
        contains('NOT searched'),
        reason: 'the transcript told the model no search ran this turn and '
            'to answer from the sources already gathered');
    expect(ollama.historySeen!.map((m) => m.content).join(),
        contains(']($_threeUrl)'),
        reason: 'the model saw turn 1\'s answer with its links intact — '
            'that is how it knows to write [3] and [10] at all');

    final shipped = provider.messages.last.content;
    expect(shipped, contains('[³]($_threeUrl)'),
        reason: 'citation [3] resolves to the source turn 1 numbered 3');
    expect(shipped, contains('[¹⁰]($_tenUrl)'),
        reason: 'citation [10] resolves to the source turn 1 numbered 10');
    expect(shipped, isNot(contains('[3]')));
    expect(shipped, isNot(contains('[10]')));
    expect(
        shipped,
        ChatProvider.replaceCitationsWithLinks(
            _followUpAnswer, {3: _threeUrl, 10: _tenUrl}),
        reason: 'the whole answer is the model\'s text with exactly those '
            'two citations rewritten and nothing else touched');
  });
}
