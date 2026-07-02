import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:llamaseek/Constants/memory_constants.dart';
import 'package:llamaseek/Models/agent_memory.dart';
import 'package:llamaseek/Models/conversation_memory.dart';
import 'package:llamaseek/Models/ephemeral_context.dart';
import 'package:llamaseek/Models/memory_topic.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Services/database_service.dart';

class MemoryService extends ChangeNotifier {
  final DatabaseService _db;
  static const String _cloudBaseUrl = 'https://ollama.com';

  bool _isUpdating = false;
  bool get isUpdating => _isUpdating;

  bool _isAgentMemoryUpdating = false;
  bool get isAgentMemoryUpdating => _isAgentMemoryUpdating;

  String? _updatingChatId;
  String? get updatingChatId => _updatingChatId;

  String? _lastError;
  String? get lastError => _lastError;

  /// In-memory caches to avoid DB reads on every message send.
  final Map<String, ConversationMemory> _conversationMemoryCache = {};
  static const int _maxConversationCacheSize = 20;
  AgentMemory? _profileCache;
  List<MemoryTopic>? _topicsCache;
  List<EphemeralContext>? _ephemeralCache;

  /// Persistent HTTP client for cloud memory-model calls — reuses the
  /// TLS connection across requests. When injected (shared with
  /// OllamaService), both services reuse a single TLS connection to
  /// ollama.com instead of each paying a separate handshake.
  final http.Client _client;
  final bool _ownsClient;

  MemoryService({required DatabaseService db, http.Client? client})
      : _db = db,
        _client = client ?? http.Client(),
        _ownsClient = client == null {
    // Migrate old default model names to current default
    final box = Hive.box('settings');
    final stored = box.get('memoryModel');
    if (stored == 'gpt-oss-20b' || stored == 'gpt-oss:20b-cloud') {
      box.delete('memoryModel');
    }
  }

  // ============================================================
  // Configuration
  // ============================================================

  /// Model for async memory generation/summarisation (off the critical path).
  String get _generationModel {
    final box = Hive.box('settings');
    return box.get('memoryModel', defaultValue: MemoryConstants.defaultModel);
  }

  /// Model for the pre-message topic-retrieval call (on the critical path).
  String get _retrievalModel {
    final box = Hive.box('settings');
    return box.get('memoryRetrievalModel',
        defaultValue: MemoryConstants.defaultRetrievalModel);
  }

  String? get _apiKey {
    final box = Hive.box('settings');
    return box.get('cloudApiKey');
  }

  bool get isEnabled => _apiKey != null && _apiKey!.isNotEmpty;

  // ============================================================
  // Read (for prompt injection)
  // ============================================================

  Future<ConversationMemory?> getConversationMemory(String chatId) async {
    if (_conversationMemoryCache.containsKey(chatId)) {
      // Move to end (most recently used)
      final value = _conversationMemoryCache.remove(chatId)!;
      _conversationMemoryCache[chatId] = value;
      return value;
    }

    final memory = await _db.getConversationMemory(chatId);
    if (memory != null) {
      _conversationMemoryCache[chatId] = memory;
      // Evict oldest if over capacity
      while (_conversationMemoryCache.length > _maxConversationCacheSize) {
        _conversationMemoryCache.remove(_conversationMemoryCache.keys.first);
      }
    }
    return memory;
  }

  Future<AgentMemory?> getAgentMemory() async {
    if (_profileCache != null) return _profileCache;

    _profileCache = await _db.getAgentMemory();
    return _profileCache;
  }

  Future<List<MemoryTopic>> getTopics() async {
    if (_topicsCache != null) return _topicsCache!;
    _topicsCache = await _db.getAllTopics();
    return _topicsCache!;
  }

  Future<List<EphemeralContext>> getEphemeralContexts() async {
    if (_ephemeralCache != null) return _ephemeralCache!;
    _ephemeralCache = await _db.getAllEphemeralContexts();
    return _ephemeralCache!;
  }

  // ============================================================
  // Pre-message: Select Relevant Context
  // ============================================================

  /// Lightweight LLM call before each message to select which topic/ephemeral
  /// keys are relevant to the current conversation. Returns a formatted string
  /// of relevant entries for injection, or '' if none are relevant.
  Future<String> selectRelevantContext(
    List<OllamaMessage> recentMessages, {
    String? conversationSummary,
  }) async {
    try {
      if (!isEnabled) return '';

      final topics = await getTopics();
      final ephemeral = await getEphemeralContexts();

      // Filter out expired ephemeral
      final activeEphemeral = ephemeral.where((e) => !e.isExpired).toList();

      final topicKeys = topics.map((t) => t.topicKey).toList();
      final ephemeralKeys = activeEphemeral.map((e) => e.contextKey).toList();

      // Nothing to select from
      if (topicKeys.isEmpty && ephemeralKeys.isEmpty) return '';

      // Take last N messages for the selection prompt
      final messagesToUse = recentMessages.length > MemoryConstants.recentMessagesForSelection
          ? recentMessages.sublist(recentMessages.length - MemoryConstants.recentMessagesForSelection)
          : recentMessages;

      final messagesText = _formatMessagesForPrompt(messagesToUse);

      final prompt = MemoryConstants.buildSelectionPrompt(
        recentMessagesText: messagesText,
        conversationSummary: conversationSummary,
        topicKeys: topicKeys,
        ephemeralKeys: ephemeralKeys,
      );

      final responseBody = await _callCloudModel(prompt, model: _retrievalModel);
      if (responseBody == null) return '';

      final parsed = _extractJson(responseBody);
      if (parsed == null) return '';

      final relevantKeys = (parsed['relevant_keys'] as List<dynamic>?)
              ?.map((k) => k.toString())
              .toList() ??
          [];

      if (relevantKeys.isEmpty) return '';

      // Fetch full content for selected keys
      final entries = <String>[];
      for (final key in relevantKeys) {
        // Check topics
        final matchingTopic = topics.where((t) => t.topicKey == key).toList();
        if (matchingTopic.isNotEmpty) {
          entries.add(matchingTopic.first.toPromptEntry());
          continue;
        }
        // Check ephemeral
        final matchingEphemeral =
            activeEphemeral.where((e) => e.contextKey == key).toList();
        if (matchingEphemeral.isNotEmpty) {
          entries.add(matchingEphemeral.first.toPromptEntry());
        }
      }

      return entries.join('\n');
    } catch (e) {
      debugPrint('MemoryService selectRelevantContext failed: $e');
      return '';
    }
  }

  // ============================================================
  // Async Update (fire-and-forget)
  // ============================================================

  void triggerMemoryUpdate({
    required String chatId,
    required List<OllamaMessage> messages,
    bool skipAgentMemory = false,
  }) {
    if (!isEnabled) return;
    if (_isUpdating) return;

    // Fire and forget
    performUpdate(chatId: chatId, messages: messages, skipAgentMemory: skipAgentMemory);
  }

  @visibleForTesting
  Future<void> performUpdate({
    required String chatId,
    required List<OllamaMessage> messages,
    bool skipAgentMemory = false,
  }) async {
    _isUpdating = true;
    _isAgentMemoryUpdating = !skipAgentMemory;
    _updatingChatId = chatId;
    _lastError = null;
    notifyListeners();

    try {
      // Fetch existing memories first — the coverage marker tells us where the
      // summary currently ends, so we ingest exactly the un-summarized tail and
      // never leave a gap. See debug-context-pollution.md F2.
      final existingConvMemory = await getConversationMemory(chatId);
      final existingProfile = await getAgentMemory();
      final existingTopics = await getTopics();
      final existingEphemeral = await getEphemeralContexts();

      final startIndex = existingConvMemory?.summarizedMessageCount ?? 0;
      final messagesToSummarize =
          (startIndex > 0 && startIndex < messages.length)
              ? messages.sublist(startIndex)
              : messages;
      final messagesText = _formatMessagesForPrompt(messagesToSummarize);

      // Cleanup expired ephemeral entries
      await _db.cleanupExpiredEphemeral();

      // Build summarization prompt with all three tiers
      final prompt = MemoryConstants.buildSummarizationPrompt(
        messagesText: messagesText,
        existingConversationMemory: existingConvMemory?.toJson(),
        existingProfile: existingProfile != null
            ? jsonEncode(existingProfile.toMap())
            : null,
        existingTopics: existingTopics.isNotEmpty
            ? existingTopics.map((t) => t.toMap()).toList()
            : null,
        existingEphemeral: existingEphemeral.isNotEmpty
            ? existingEphemeral.where((e) => !e.isExpired).map((e) => e.toMap()).toList()
            : null,
      );

      // Call cloud model (async generation — off the critical path)
      final responseBody = await _callCloudModel(prompt, model: _generationModel);
      if (responseBody == null) {
        return;
      }
      _lastError = null;

      // Declare the summary authoritative for everything except the recent
      // window, which stays in the raw send window. See debug-context-pollution.md F2.
      final newCoverage = messages.length > MemoryConstants.recentMessagesToKeep
          ? messages.length - MemoryConstants.recentMessagesToKeep
          : 0;
      await parseAndSave(chatId, responseBody,
          skipAgentMemory: skipAgentMemory, summarizedThrough: newCoverage);
    } catch (e) {
      debugPrint('MemoryService update failed: $e');
    } finally {
      _isUpdating = false;
      _isAgentMemoryUpdating = false;
      _updatingChatId = null;
      notifyListeners();
    }
  }

  Future<String?> _callCloudModel(String prompt, {required String model}) async {
    final url = Uri.parse('$_cloudBaseUrl/api/chat');

    try {
      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'stream': false,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final responseBody = utf8.decode(response.bodyBytes);
        final json = jsonDecode(responseBody);
        return json['message']?['content'] as String?;
      } else if (response.statusCode == 404) {
        _lastError = 'Model "$model" not found. Change it in Settings → Memory Model.';
        return null;
      } else {
        _lastError = 'API error ${response.statusCode}';
        return null;
      }
    } catch (e) {
      _lastError = 'Network error: $e';
      return null;
    }
  }

  @visibleForTesting
  Future<void> parseAndSave(String chatId, String responseBody,
      {bool skipAgentMemory = false, int? summarizedThrough}) async {
    try {
      final parsed = _extractJson(responseBody);
      if (parsed == null) {
        // Non-JSON response: keep the last good memory instead of storing raw
        // model output verbatim. Prose, meta-commentary, or half-JSON would be
        // injected as authoritative "Conversation Context" and hallucinated as
        // fact. See debug-context-pollution.md F1.
        debugPrint(
            'MemoryService: non-JSON memory response ignored (kept prior memory)');
        return;
      }

      // Parse conversation memory
      final convMap = parsed['conversation_memory'] as Map<String, dynamic>?;
      if (convMap != null) {
        var convMemory = ConversationMemory.fromMap(convMap);
        if (summarizedThrough != null) {
          convMemory =
              convMemory.copyWith(summarizedMessageCount: summarizedThrough);
        }
        _conversationMemoryCache[chatId] = convMemory;
        _db.updateConversationMemory(chatId, convMemory);
      }

      if (skipAgentMemory) return;

      // Parse profile updates (confidence-gated)
      final profileUpdates = parsed['profile_updates'] as Map<String, dynamic>?;
      if (profileUpdates != null) {
        final existing = await getAgentMemory() ?? AgentMemory();
        final updated = applyProfileUpdates(existing, profileUpdates);
        if (updated.toMap().toString() != existing.toMap().toString()) {
          _profileCache = updated;
          await _db.updateAgentMemory(updated);
        }
      }

      // Parse topic updates
      final topicUpdates = parsed['topic_updates'] as List<dynamic>?;
      if (topicUpdates != null && topicUpdates.isNotEmpty) {
        final existingTopics = await getTopics();
        final actions = parseTopicUpdates(topicUpdates, existingTopics);
        for (final action in actions) {
          switch (action.type) {
            case TopicActionType.create:
              await _db.insertTopic(MemoryTopic(
                topicKey: action.key,
                content: action.content,
              ));
              break;
            case TopicActionType.update:
              await _db.updateTopic(MemoryTopic(
                topicKey: action.key,
                content: action.content,
              ));
              break;
            case TopicActionType.merge:
              await _db.mergeTopics(
                action.fromKey!,
                action.key,
                action.content,
              );
              break;
          }
        }
        _topicsCache = null; // Invalidate cache
      }

      // Parse ephemeral updates
      final ephemeralUpdates = parsed['ephemeral_updates'] as List<dynamic>?;
      if (ephemeralUpdates != null && ephemeralUpdates.isNotEmpty) {
        final newEntries = parseEphemeralUpdates(ephemeralUpdates, chatId);
        for (final entry in newEntries) {
          await _db.insertEphemeralContext(entry);
        }
        _ephemeralCache = null; // Invalidate cache
      }
    } catch (e) {
      // Do NOT fall back to storing raw text — that pollutes the conversation
      // summary with unstructured model output. Keep the last good memory.
      debugPrint('MemoryService parseAndSave failed (kept prior memory): $e');
    }
  }

  Map<String, dynamic>? _extractJson(String responseBody) {
    try {
      var jsonStr = responseBody.trim();
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
      if (jsonMatch != null) {
        jsonStr = jsonMatch.group(0)!;
      }
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  String _formatMessagesForPrompt(List<OllamaMessage> messages) {
    final buffer = StringBuffer();
    for (final m in messages) {
      final role = m.role.name.toUpperCase();
      final model = m.model != null ? ' [${m.model}]' : '';
      buffer.writeln('$role$model: ${m.content}');
      if (m.images != null && m.images!.isNotEmpty) {
        buffer.writeln('[User sent ${m.images!.length} image(s)]');
      }
    }
    return buffer.toString();
  }

  // ============================================================
  // Static helpers (for testability)
  // ============================================================

  /// Applies profile updates, only accepting fields with high confidence.
  static AgentMemory applyProfileUpdates(
    AgentMemory existing,
    Map<String, dynamic> updates,
  ) {
    String? extractHigh(String fieldKey) {
      final entry = updates[fieldKey];
      if (entry is! Map) return null;
      if (entry['confidence'] != 'high') return null;
      final value = entry['value'];
      if (value == null) return null;
      return value.toString();
    }

    return existing.copyWith(
      name: extractHigh('name'),
      primaryLanguage: extractHigh('primary_language'),
      toneAndFormality: extractHigh('tone_and_formality'),
      roleAndBackground: extractHigh('role_and_background'),
      communicationStyle: extractHigh('communication_style'),
    );
  }

  /// Parses topic update instructions into a list of TopicAction objects.
  static List<TopicAction> parseTopicUpdates(
    List<dynamic> updates,
    List<MemoryTopic> existingTopics,
  ) {
    final actions = <TopicAction>[];

    for (final update in updates) {
      if (update is! Map) continue;

      final action = update['action']?.toString();
      final key = (update['key'] ?? update['into'])?.toString();
      final content = update['content']?.toString() ?? '';

      if (action == null || key == null || key.isEmpty) continue;

      switch (action) {
        case 'create':
          actions.add(TopicAction(
            type: TopicActionType.create,
            key: key,
            content: content,
          ));
          break;
        case 'update':
          actions.add(TopicAction(
            type: TopicActionType.update,
            key: key,
            content: content,
          ));
          break;
        case 'merge':
          final fromKey = update['from']?.toString();
          if (fromKey == null || fromKey.isEmpty) continue;
          actions.add(TopicAction(
            type: TopicActionType.merge,
            key: key,
            content: content,
            fromKey: fromKey,
          ));
          break;
      }
    }

    return actions;
  }

  /// Parses ephemeral update instructions into EphemeralContext objects.
  /// TTL is clamped to max 14 days.
  static List<EphemeralContext> parseEphemeralUpdates(
    List<dynamic> updates,
    String chatId,
  ) {
    final results = <EphemeralContext>[];

    for (final update in updates) {
      if (update is! Map) continue;

      final action = update['action']?.toString();
      if (action != 'create') continue;

      final key = update['key']?.toString();
      final content = update['content']?.toString() ?? '';
      if (key == null || key.isEmpty) continue;

      final ttlDays = (update['ttl_days'] is int)
          ? update['ttl_days'] as int
          : EphemeralContext.defaultTtlDays;

      results.add(EphemeralContext.withTtlDays(
        contextKey: key,
        content: content,
        sourceChatId: chatId,
        ttlDays: ttlDays,
      ));
    }

    return results;
  }

  // ============================================================
  // Memory Management (for UI)
  // ============================================================

  Future<void> updateConversationMemoryField(
    String chatId,
    ConversationMemory memory,
  ) async {
    _conversationMemoryCache.remove(chatId); // Remove old position
    _conversationMemoryCache[chatId] = memory; // Add at end (most recent)
    while (_conversationMemoryCache.length > _maxConversationCacheSize) {
      _conversationMemoryCache.remove(_conversationMemoryCache.keys.first);
    }
    await _db.updateConversationMemory(chatId, memory);
    notifyListeners();
  }

  Future<void> updateAgentMemoryField(AgentMemory memory) async {
    _profileCache = memory;
    await _db.updateAgentMemory(memory);
    notifyListeners();
  }

  Future<void> clearAgentMemory() async {
    _profileCache = null;
    await _db.clearAgentMemory();
    notifyListeners();
  }

  void invalidateConversationMemoryCache(String chatId) {
    _conversationMemoryCache.remove(chatId);
  }

  // --- Topic management ---

  Future<void> saveTopic(MemoryTopic topic) async {
    if (topic.id != null) {
      await _db.updateTopic(topic);
    } else {
      await _db.insertTopic(topic);
    }
    _topicsCache = null;
    notifyListeners();
  }

  Future<void> deleteTopicById(int id) async {
    await _db.deleteTopicById(id);
    _topicsCache = null;
    notifyListeners();
  }

  Future<void> clearAllTopics() async {
    await _db.clearAllTopics();
    _topicsCache = null;
    notifyListeners();
  }

  // --- Ephemeral management ---

  Future<void> saveEphemeralContext(EphemeralContext ctx) async {
    if (ctx.id != null) {
      await _db.updateEphemeralContext(ctx);
    } else {
      await _db.insertEphemeralContext(ctx);
    }
    _ephemeralCache = null;
    notifyListeners();
  }

  Future<void> deleteEphemeralContextById(int id) async {
    await _db.deleteEphemeralContextById(id);
    _ephemeralCache = null;
    notifyListeners();
  }

  Future<void> clearAllEphemeral() async {
    await _db.clearAllEphemeral();
    _ephemeralCache = null;
    notifyListeners();
  }

  // --- Clear all agent memory (all 3 tiers) ---

  Future<void> clearAllAgentMemory() async {
    _profileCache = null;
    _topicsCache = null;
    _ephemeralCache = null;
    await _db.clearAgentMemory();
    await _db.clearAllTopics();
    await _db.clearAllEphemeral();
    notifyListeners();
  }

  // ============================================================
  // Resummarization (when user edits exceed token limits)
  // ============================================================

  Future<String?> resummarize(String content, int tokenLimit) async {
    if (!isEnabled) return null;

    _isUpdating = true;
    notifyListeners();

    try {
      final prompt = MemoryConstants.buildResummarizationPrompt(content, tokenLimit);
      return await _callCloudModel(prompt, model: _generationModel);
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
    super.dispose();
  }
}

// ============================================================
// Supporting types
// ============================================================

enum TopicActionType { create, update, merge }

class TopicAction {
  final TopicActionType type;
  final String key;
  final String content;
  final String? fromKey;

  TopicAction({
    required this.type,
    required this.key,
    required this.content,
    this.fromKey,
  });
}
