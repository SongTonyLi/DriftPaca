import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'package:llamaseek/Constants/memory_constants.dart';
import 'package:llamaseek/Models/agent_memory.dart';
import 'package:llamaseek/Models/conversation_memory.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Services/database_service.dart';

class MemoryService extends ChangeNotifier {
  final DatabaseService _db;
  static const String _cloudBaseUrl = 'https://ollama.com';

  bool _isUpdating = false;
  bool get isUpdating => _isUpdating;

  /// In-memory cache to avoid DB reads on every message send.
  final Map<String, ConversationMemory> _conversationMemoryCache = {};
  AgentMemory? _agentMemoryCache;

  MemoryService({required DatabaseService db}) : _db = db;

  // ============================================================
  // Configuration
  // ============================================================

  String get _model {
    final box = Hive.box('settings');
    return box.get('memoryModel', defaultValue: MemoryConstants.defaultModel);
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
      return _conversationMemoryCache[chatId];
    }

    final memory = await _db.getConversationMemory(chatId);
    if (memory != null) {
      _conversationMemoryCache[chatId] = memory;
    }
    return memory;
  }

  Future<AgentMemory?> getAgentMemory() async {
    if (_agentMemoryCache != null) return _agentMemoryCache;

    _agentMemoryCache = await _db.getAgentMemory();
    return _agentMemoryCache;
  }

  // ============================================================
  // Async Update (fire-and-forget)
  // ============================================================

  void triggerMemoryUpdate({
    required String chatId,
    required List<OllamaMessage> messages,
  }) {
    if (!isEnabled || _isUpdating) return;

    // Fire and forget
    _performUpdate(chatId: chatId, messages: messages);
  }

  Future<void> _performUpdate({
    required String chatId,
    required List<OllamaMessage> messages,
  }) async {
    _isUpdating = true;
    notifyListeners();

    try {
      // Build messages text for the prompt
      final messagesText = _formatMessagesForPrompt(messages);

      // Get existing memories
      final existingConvMemory = await getConversationMemory(chatId);
      final existingAgentMemory = await getAgentMemory();

      // Build the summarization prompt
      final prompt = MemoryConstants.buildSummarizationPrompt(
        messagesText: messagesText,
        existingConversationMemory: existingConvMemory?.toJson(),
        existingAgentMemory: existingAgentMemory != null
            ? jsonEncode(existingAgentMemory.toMap())
            : null,
      );

      // Call gpt-oss-20b via Ollama Cloud
      final responseBody = await _callCloudModel(prompt);
      if (responseBody == null) return;

      // Parse and save
      _parseAndSave(chatId, responseBody);
    } catch (e) {
      debugPrint('MemoryService update failed: $e');
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }

  Future<String?> _callCloudModel(String prompt) async {
    final url = Uri.parse('$_cloudBaseUrl/api/chat');

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'stream': false,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return json['message']?['content'] as String?;
      } else {
        debugPrint('MemoryService API error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('MemoryService network error: $e');
      return null;
    }
  }

  void _parseAndSave(String chatId, String responseBody) {
    try {
      // Try to extract JSON from the response (model may wrap it in markdown)
      var jsonStr = responseBody.trim();
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(jsonStr);
      if (jsonMatch != null) {
        jsonStr = jsonMatch.group(0)!;
      }

      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Parse conversation memory
      final convMap = parsed['conversation_memory'] as Map<String, dynamic>?;
      if (convMap != null) {
        final convMemory = ConversationMemory.fromMap(convMap);
        _conversationMemoryCache[chatId] = convMemory;
        _db.updateConversationMemory(chatId, convMemory);
      }

      // Parse agent memory
      final agentMap = parsed['agent_memory'] as Map<String, dynamic>?;
      if (agentMap != null) {
        final agentMemory = AgentMemory.fromMap(agentMap);
        _agentMemoryCache = agentMemory;
        _db.updateAgentMemory(agentMemory);
      }
    } catch (_) {
      // JSON parsing failed — store raw text as conversation memory summary
      final convMemory = ConversationMemory(summary: responseBody);
      _conversationMemoryCache[chatId] = convMemory;
      _db.updateConversationMemory(chatId, convMemory);
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
  // Memory Management (for UI)
  // ============================================================

  Future<void> updateConversationMemoryField(
    String chatId,
    ConversationMemory memory,
  ) async {
    _conversationMemoryCache[chatId] = memory;
    await _db.updateConversationMemory(chatId, memory);
    notifyListeners();
  }

  Future<void> updateAgentMemoryField(AgentMemory memory) async {
    _agentMemoryCache = memory;
    await _db.updateAgentMemory(memory);
    notifyListeners();
  }

  Future<void> clearAgentMemory() async {
    _agentMemoryCache = null;
    await _db.clearAgentMemory();
    notifyListeners();
  }

  void invalidateConversationMemoryCache(String chatId) {
    _conversationMemoryCache.remove(chatId);
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
      return await _callCloudModel(prompt);
    } finally {
      _isUpdating = false;
      notifyListeners();
    }
  }
}
