# Memory System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add conversation memory and agent memory to enable smooth multi-turn conversations across model switches and sessions.

**Architecture:** A dedicated `MemoryService` asynchronously calls `gpt-oss-20b` (Ollama Cloud) after each assistant response to generate structured memory summaries. Memories are injected into the system prompt alongside the last 10 raw messages. Both memory types are viewable/editable from the sidebar.

**Tech Stack:** Flutter, Provider, SQLite (sqflite), Hive, HTTP (Ollama Cloud API)

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `lib/Models/conversation_memory.dart` | ConversationMemory data model (6 sections) |
| Create | `lib/Models/agent_memory.dart` | AgentMemory data model (5 sections) |
| Create | `lib/Services/memory_service.dart` | Memory orchestration: summarize, store, retrieve |
| Create | `lib/Constants/memory_constants.dart` | Summarization prompts, token limits |
| Create | `lib/Widgets/memory_bottom_sheet.dart` | Shared bottom sheet for viewing/editing memory |
| Create | `lib/Widgets/memory_status_indicator.dart` | Glowing star widget for summarization status |
| Modify | `lib/Services/database_service.dart` | Migration v4: add conversation_memory column + agent_memory table |
| Modify | `lib/Services/ollama_service.dart` | Update `_prepareMessagesWithSystemPrompt` to accept memories + limit messages |
| Modify | `lib/Providers/chat_provider.dart` | Integrate MemoryService triggers, fix edit+resend |
| Modify | `lib/Pages/chat_page/chat_page_view_model.dart` | Proxy MemoryService state for UI |
| Modify | `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart` | Fix edit+resend to add new message at bottom |
| Modify | `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_actions.dart` | Fix edit action to not call regenerate |
| Modify | `lib/Pages/chat_page/subwidgets/chat_text_field.dart` | Add memory status indicator star |
| Modify | `lib/Widgets/chat_drawer.dart` | Add Agent Memory tile + Memory option in context menu |
| Modify | `lib/Pages/settings_page/settings_page.dart` | Add memory model setting |
| Modify | `lib/Pages/settings_page/subwidgets/server_settings.dart` | Add memory model dropdown |
| Modify | `lib/Services/services.dart` | Export memory_service |
| Modify | `lib/main.dart` | Register MemoryService in provider tree |

---

### Task 1: Data Models — ConversationMemory + AgentMemory

**Files:**
- Create: `lib/Models/conversation_memory.dart`
- Create: `lib/Models/agent_memory.dart`

- [ ] **Step 1: Create ConversationMemory model**

```dart
// lib/Models/conversation_memory.dart
import 'dart:convert';

class ConversationMemory {
  final String summary;
  final String keyContext;
  final String mediaDescriptions;
  final String currentState;
  final String modelHistory;
  final String unresolvedItems;
  final DateTime updatedAt;

  ConversationMemory({
    this.summary = '',
    this.keyContext = '',
    this.mediaDescriptions = '',
    this.currentState = '',
    this.modelHistory = '',
    this.unresolvedItems = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  bool get isEmpty =>
      summary.isEmpty &&
      keyContext.isEmpty &&
      mediaDescriptions.isEmpty &&
      currentState.isEmpty &&
      modelHistory.isEmpty &&
      unresolvedItems.isEmpty;

  factory ConversationMemory.fromJson(String jsonString) {
    try {
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      return ConversationMemory.fromMap(map);
    } catch (_) {
      // If JSON parsing fails, treat the entire string as a raw summary
      return ConversationMemory(summary: jsonString);
    }
  }

  factory ConversationMemory.fromMap(Map<String, dynamic> map) {
    return ConversationMemory(
      summary: map['summary'] ?? '',
      keyContext: map['key_context'] ?? '',
      mediaDescriptions: map['media_descriptions'] ?? '',
      currentState: map['current_state'] ?? '',
      modelHistory: map['model_history'] ?? '',
      unresolvedItems: map['unresolved_items'] ?? '',
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'])
          : null,
    );
  }

  String toJson() {
    return jsonEncode({
      'summary': summary,
      'key_context': keyContext,
      'media_descriptions': mediaDescriptions,
      'current_state': currentState,
      'model_history': modelHistory,
      'unresolved_items': unresolvedItems,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    });
  }

  ConversationMemory copyWith({
    String? summary,
    String? keyContext,
    String? mediaDescriptions,
    String? currentState,
    String? modelHistory,
    String? unresolvedItems,
  }) {
    return ConversationMemory(
      summary: summary ?? this.summary,
      keyContext: keyContext ?? this.keyContext,
      mediaDescriptions: mediaDescriptions ?? this.mediaDescriptions,
      currentState: currentState ?? this.currentState,
      modelHistory: modelHistory ?? this.modelHistory,
      unresolvedItems: unresolvedItems ?? this.unresolvedItems,
    );
  }

  /// Approximate token count using chars/4 heuristic.
  int get estimatedTokens {
    final total = summary.length +
        keyContext.length +
        mediaDescriptions.length +
        currentState.length +
        modelHistory.length +
        unresolvedItems.length;
    return (total / 4).ceil();
  }

  /// Formats memory as natural language for system prompt injection.
  String toPromptBlock() {
    final sections = <String>[];
    if (summary.isNotEmpty) sections.add('- **Summary**: $summary');
    if (keyContext.isNotEmpty) sections.add('- **Key Context**: $keyContext');
    if (mediaDescriptions.isNotEmpty) sections.add('- **Media Descriptions**: $mediaDescriptions');
    if (currentState.isNotEmpty) sections.add('- **Current State**: $currentState');
    if (modelHistory.isNotEmpty) sections.add('- **Model History**: $modelHistory');
    if (unresolvedItems.isNotEmpty) sections.add('- **Unresolved Items**: $unresolvedItems');
    return sections.join('\n');
  }
}
```

- [ ] **Step 2: Create AgentMemory model**

```dart
// lib/Models/agent_memory.dart
import 'dart:convert';

class AgentMemory {
  final String userProfile;
  final String preferences;
  final String learnedFacts;
  final String interestsAndExpertise;
  final String languageAndTone;
  final DateTime updatedAt;

  AgentMemory({
    this.userProfile = '',
    this.preferences = '',
    this.learnedFacts = '',
    this.interestsAndExpertise = '',
    this.languageAndTone = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  bool get isEmpty =>
      userProfile.isEmpty &&
      preferences.isEmpty &&
      learnedFacts.isEmpty &&
      interestsAndExpertise.isEmpty &&
      languageAndTone.isEmpty;

  factory AgentMemory.fromMap(Map<String, dynamic> map) {
    return AgentMemory(
      userProfile: map['user_profile'] ?? '',
      preferences: map['preferences'] ?? '',
      learnedFacts: map['learned_facts'] ?? '',
      interestsAndExpertise: map['interests_and_expertise'] ?? '',
      languageAndTone: map['language_and_tone'] ?? '',
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_profile': userProfile,
      'preferences': preferences,
      'learned_facts': learnedFacts,
      'interests_and_expertise': interestsAndExpertise,
      'language_and_tone': languageAndTone,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  AgentMemory copyWith({
    String? userProfile,
    String? preferences,
    String? learnedFacts,
    String? interestsAndExpertise,
    String? languageAndTone,
  }) {
    return AgentMemory(
      userProfile: userProfile ?? this.userProfile,
      preferences: preferences ?? this.preferences,
      learnedFacts: learnedFacts ?? this.learnedFacts,
      interestsAndExpertise: interestsAndExpertise ?? this.interestsAndExpertise,
      languageAndTone: languageAndTone ?? this.languageAndTone,
    );
  }

  int get estimatedTokens {
    final total = userProfile.length +
        preferences.length +
        learnedFacts.length +
        interestsAndExpertise.length +
        languageAndTone.length;
    return (total / 4).ceil();
  }

  String toPromptBlock() {
    final sections = <String>[];
    if (userProfile.isNotEmpty) sections.add('- **Profile**: $userProfile');
    if (preferences.isNotEmpty) sections.add('- **Preferences**: $preferences');
    if (interestsAndExpertise.isNotEmpty) sections.add('- **Interests & Expertise**: $interestsAndExpertise');
    if (languageAndTone.isNotEmpty) sections.add('- **Language & Tone**: $languageAndTone');
    return sections.join('\n');
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/Models/conversation_memory.dart lib/Models/agent_memory.dart
git commit -m "Add ConversationMemory and AgentMemory data models"
```

---

### Task 2: Database Migration v4

**Files:**
- Modify: `lib/Services/database_service.dart`

- [ ] **Step 1: Add migration v4 and agent_memory table creation**

In `database_service.dart`, change `version: 3` to `version: 4` in `openDatabase()`, add the v4 migration case, and add `agent_memory` table to `onCreate`:

```dart
// In open() method, change version from 3 to 4:
_db = await openDatabase(
  path.join(await getDatabasesPathForPlatform(), databaseFile),
  version: 4,
  onUpgrade: (Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE messages ADD COLUMN thinking TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE messages ADD COLUMN model TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE chats ADD COLUMN conversation_memory TEXT');
      await db.execute('''CREATE TABLE IF NOT EXISTS agent_memory (
id INTEGER PRIMARY KEY DEFAULT 1,
user_profile TEXT DEFAULT '',
preferences TEXT DEFAULT '',
learned_facts TEXT DEFAULT '',
interests_and_expertise TEXT DEFAULT '',
language_and_tone TEXT DEFAULT '',
updated_at INTEGER
)''');
    }
  },
  onCreate: (Database db, int version) async {
    // ... existing chats table creation ...
    // ... existing messages table creation ...
    // ... existing cleanup_jobs table creation ...
    // ... existing trigger creation ...

    // Add conversation_memory to chats table (already in CREATE TABLE above, add column):
    // UPDATE: Add conversation_memory column to the chats CREATE TABLE:
```

The `chats` CREATE TABLE in `onCreate` needs the new column:

```sql
CREATE TABLE IF NOT EXISTS chats (
chat_id TEXT PRIMARY KEY,
model TEXT NOT NULL,
chat_title TEXT NOT NULL,
system_prompt TEXT,
options TEXT,
conversation_memory TEXT
) WITHOUT ROWID;
```

And add after the trigger creation:

```dart
    await db.execute('''CREATE TABLE IF NOT EXISTS agent_memory (
id INTEGER PRIMARY KEY DEFAULT 1,
user_profile TEXT DEFAULT '',
preferences TEXT DEFAULT '',
learned_facts TEXT DEFAULT '',
interests_and_expertise TEXT DEFAULT '',
language_and_tone TEXT DEFAULT '',
updated_at INTEGER
)''');
```

- [ ] **Step 2: Add conversation memory DB methods**

Add these methods to `DatabaseService`:

```dart
  // Memory Operations

  Future<ConversationMemory?> getConversationMemory(String chatId) async {
    final List<Map<String, dynamic>> maps = await _db.query(
      'chats',
      columns: ['conversation_memory'],
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );

    if (maps.isEmpty || maps.first['conversation_memory'] == null) {
      return null;
    }

    return ConversationMemory.fromJson(maps.first['conversation_memory']);
  }

  Future<void> updateConversationMemory(String chatId, ConversationMemory memory) async {
    await _db.update(
      'chats',
      {'conversation_memory': memory.toJson()},
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );
  }

  Future<AgentMemory?> getAgentMemory() async {
    final List<Map<String, dynamic>> maps = await _db.query('agent_memory');

    if (maps.isEmpty) {
      return null;
    }

    return AgentMemory.fromMap(maps.first);
  }

  Future<void> updateAgentMemory(AgentMemory memory) async {
    final exists = (await _db.query('agent_memory')).isNotEmpty;

    if (exists) {
      await _db.update('agent_memory', memory.toMap());
    } else {
      await _db.insert('agent_memory', {'id': 1, ...memory.toMap()});
    }
  }

  Future<void> clearAgentMemory() async {
    await _db.delete('agent_memory');
  }
```

Add the import at the top of `database_service.dart`:

```dart
import 'package:llamaseek/Models/conversation_memory.dart';
import 'package:llamaseek/Models/agent_memory.dart';
```

- [ ] **Step 3: Commit**

```bash
git add lib/Services/database_service.dart
git commit -m "Add database migration v4: conversation_memory column + agent_memory table"
```

---

### Task 3: Memory Constants — Prompts and Token Limits

**Files:**
- Create: `lib/Constants/memory_constants.dart`

- [ ] **Step 1: Create memory constants file**

```dart
// lib/Constants/memory_constants.dart

class MemoryConstants {
  static const String defaultModel = 'gpt-oss-20b';

  static const int maxConversationMemoryTokens = 8000;
  static const int maxAgentMemoryTokens = 4000;
  static const int maxPerSectionTokens = 1500;
  static const int recentMessagesToKeep = 10;

  /// Estimates token count from text using chars/4 heuristic.
  static int estimateTokens(String text) => (text.length / 4).ceil();

  /// The summarization prompt sent to gpt-oss-20b.
  static String buildSummarizationPrompt({
    required String messagesText,
    String? existingConversationMemory,
    String? existingAgentMemory,
  }) {
    return '''You are a conversation memory manager. Analyze the conversation and update two memory structures.

IMPORTANT: Be concise. Conversation memory total must not exceed $maxConversationMemoryTokens tokens (~${maxConversationMemoryTokens * 4} characters). Agent memory total must not exceed $maxAgentMemoryTokens tokens (~${maxAgentMemoryTokens * 4} characters). Summarize, don't transcribe.

## Existing Conversation Memory:
${existingConversationMemory ?? 'None yet'}

## Existing Agent Memory:
${existingAgentMemory ?? 'None yet'}

## Conversation Messages:
$messagesText

---

Merge new information with existing memory. Don't discard prior context — update and extend it. Return a JSON object with exactly these keys:

{
  "conversation_memory": {
    "summary": "Main goal and what this conversation is about",
    "key_context": "Important facts, decisions, conclusions reached",
    "media_descriptions": "Textual descriptions of all images/files discussed",
    "current_state": "Where the conversation is at now",
    "model_history": "Which models were used and for what purpose",
    "unresolved_items": "Open questions, pending tasks"
  },
  "agent_memory": {
    "user_profile": "Name, role, background if mentioned",
    "preferences": "Communication style, response format preferences",
    "learned_facts": "Specific facts learned about the user",
    "interests_and_expertise": "Topics they discuss, domains of knowledge",
    "language_and_tone": "Primary language, formality level, verbosity preference"
  }
}

Return ONLY the JSON object, no other text.''';
  }

  /// Builds the memory injection block for the active model's system prompt.
  static String buildMemoryInjection({
    required String conversationMemoryBlock,
    required String agentMemoryBlock,
  }) {
    final parts = <String>[];

    if (conversationMemoryBlock.isNotEmpty) {
      parts.add('''
## Conversation Context
The following is a summary of earlier conversation history. Use it to maintain continuity.

$conversationMemoryBlock''');
    }

    if (agentMemoryBlock.isNotEmpty) {
      parts.add('''
## About This User
$agentMemoryBlock''');
    }

    if (parts.isNotEmpty) {
      parts.add(
        'If images were described in the conversation memory but are not visible in recent messages, use the textual descriptions provided. Recent messages follow below for full detail.',
      );
    }

    return parts.join('\n\n');
  }

  /// Prompt for resummarizing memory that exceeds token limits.
  static String buildResummarizationPrompt(String memoryContent, int tokenLimit) {
    return '''The following memory content exceeds the allowed size (~$tokenLimit tokens / ~${tokenLimit * 4} characters). Condense it while preserving all key information. Return the condensed text only, no explanation.

$memoryContent''';
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/Constants/memory_constants.dart
git commit -m "Add memory constants: prompts, token limits, injection builder"
```

---

### Task 4: MemoryService — Core Orchestration

**Files:**
- Create: `lib/Services/memory_service.dart`
- Modify: `lib/Services/services.dart`

- [ ] **Step 1: Create MemoryService**

```dart
// lib/Services/memory_service.dart
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
```

- [ ] **Step 2: Export MemoryService**

In `lib/Services/services.dart`, add:

```dart
export 'memory_service.dart';
```

- [ ] **Step 3: Commit**

```bash
git add lib/Services/memory_service.dart lib/Services/services.dart
git commit -m "Add MemoryService: async summarization, caching, cloud API"
```

---

### Task 5: Register MemoryService in Provider Tree

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add MemoryService to the provider tree**

In `lib/main.dart`, add the import and register the provider. The MemoryService needs `DatabaseService`, so it must come after it.

Add import:

```dart
import 'package:llamaseek/Services/memory_service.dart';
```

In the `MultiProvider.providers` list, after the `DatabaseService` provider and before `ChatProvider`, add:

```dart
ChangeNotifierProvider(
  create: (context) => MemoryService(
    db: context.read<DatabaseService>(),
  ),
),
```

Update `ChatProvider` creation to accept `MemoryService`:

```dart
ChangeNotifierProvider(
  create: (context) => ChatProvider(
    ollamaService: context.read(),
    databaseService: context.read(),
    memoryService: context.read<MemoryService>(),
  ),
),
```

- [ ] **Step 2: Commit**

```bash
git add lib/main.dart
git commit -m "Register MemoryService in provider tree"
```

---

### Task 6: Integrate MemoryService into ChatProvider

**Files:**
- Modify: `lib/Providers/chat_provider.dart`

- [ ] **Step 1: Accept MemoryService in constructor**

Add field and update constructor:

```dart
final MemoryService _memoryService;

ChatProvider({
  required OllamaService ollamaService,
  required DatabaseService databaseService,
  required MemoryService memoryService,
})  : _ollamaService = ollamaService,
      _databaseService = databaseService,
      _memoryService = memoryService {
  _initialize();
}
```

Add import:

```dart
import 'package:llamaseek/Services/memory_service.dart';
```

- [ ] **Step 2: Trigger memory update after response completes**

In `_initializeChatStream`, after saving the assistant message to the database (the `if (ollamaMessage != null)` block near the end), add the memory trigger:

```dart
    // Save the Ollama message to the database
    if (ollamaMessage != null) {
      await _databaseService.addMessage(ollamaMessage, chat: associatedChat);

      // Trigger async memory update (fire-and-forget)
      _memoryService.triggerMemoryUpdate(
        chatId: associatedChat.id,
        messages: _messages,
      );
    }
```

- [ ] **Step 3: Pass memories to OllamaService for prompt injection**

In `_streamOllamaMessage`, before calling `_ollamaService.chatStream`, fetch memories and pass them. Replace the `_ollamaService.chatStream(messagesToSend, chat: associatedChat)` call:

```dart
  Future<OllamaMessage?> _streamOllamaMessage(OllamaChat associatedChat, {String? searchContext}) async {
    if (_messages.isEmpty) return null;

    // Fetch current memories for injection
    final conversationMemory = await _memoryService.getConversationMemory(associatedChat.id);
    final agentMemory = await _memoryService.getAgentMemory();

    // If search context is provided, inject it as a system message before the conversation
    List<OllamaMessage> messagesToSend = _messages;
    if (searchContext != null && searchContext.isNotEmpty) {
      messagesToSend = [
        OllamaMessage(searchContext, role: OllamaMessageRole.system),
        ..._messages,
      ];
    }

    final stream = _ollamaService.chatStream(
      messagesToSend,
      chat: associatedChat,
      conversationMemory: conversationMemory,
      agentMemory: agentMemory,
    );

    // ... rest of method unchanged ...
```

- [ ] **Step 4: Invalidate cache when chat is deleted**

In `deleteChat` and `deleteCurrentChat`, add cache invalidation:

```dart
  Future<void> deleteCurrentChat() async {
    final chat = currentChat;
    if (chat == null) return;

    _resetChat();

    _chats.remove(chat);
    _activeChatStreams.remove(chat.id);
    _memoryService.invalidateConversationMemoryCache(chat.id);

    await _databaseService.deleteChat(chat.id);
  }

  Future<void> deleteChat(OllamaChat chat) async {
    // ... existing logic ...
    _memoryService.invalidateConversationMemoryCache(chat.id);
    await _databaseService.deleteChat(chat.id);
    notifyListeners();
  }
```

- [ ] **Step 5: Commit**

```bash
git add lib/Providers/chat_provider.dart
git commit -m "Integrate MemoryService into ChatProvider: trigger updates, inject memories"
```

---

### Task 7: Update OllamaService — Memory Injection + Message Limiting

**Files:**
- Modify: `lib/Services/ollama_service.dart`

- [ ] **Step 1: Update _prepareMessagesWithSystemPrompt signature**

Add memory parameters and message limiting logic:

```dart
import 'package:llamaseek/Constants/memory_constants.dart';
import 'package:llamaseek/Models/conversation_memory.dart';
import 'package:llamaseek/Models/agent_memory.dart';
```

Update the method signature and body:

```dart
  Future<List<Map<String, dynamic>>> _prepareMessagesWithSystemPrompt(
    List<OllamaMessage> messages,
    String? systemPrompt, {
    ConversationMemory? conversationMemory,
    AgentMemory? agentMemory,
  }) async {
    // Determine which messages to send
    final hasMemory = conversationMemory != null && !conversationMemory.isEmpty;
    final messagesToProcess = hasMemory && messages.length > MemoryConstants.recentMessagesToKeep
        ? messages.sublist(messages.length - MemoryConstants.recentMessagesToKeep)
        : messages;

    final jsonMessages = <Map<String, dynamic>>[];

    for (final m in messagesToProcess) {
      final json = await m.toChatJson();
      if (m.role == OllamaMessageRole.assistant &&
          m.model != null &&
          m.model!.isNotEmpty) {
        final displayName =
            m.model!.contains(':') ? m.model!.split(':').first : m.model!;
        json['content'] = '[$displayName]\n${json['content']}';
      }
      jsonMessages.add(json);
    }

    // Build the system prompt with memory injection
    final systemParts = <String>[];

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      systemParts.add(systemPrompt);
    }

    // Inject memories if available
    final convBlock = conversationMemory?.toPromptBlock() ?? '';
    final agentBlock = agentMemory?.toPromptBlock() ?? '';
    if (convBlock.isNotEmpty || agentBlock.isNotEmpty) {
      systemParts.add(MemoryConstants.buildMemoryInjection(
        conversationMemoryBlock: convBlock,
        agentMemoryBlock: agentBlock,
      ));
    }

    if (systemParts.isNotEmpty) {
      final combinedSystem = systemParts.join('\n\n');
      final sp = OllamaMessage(combinedSystem, role: OllamaMessageRole.system);
      jsonMessages.insert(0, await sp.toChatJson());
    }

    return jsonMessages;
  }
```

- [ ] **Step 2: Update chatStream and chat method signatures**

Pass memory parameters through both methods:

```dart
  Future<OllamaMessage> chat(
    List<OllamaMessage> messages, {
    required OllamaChat chat,
    ConversationMemory? conversationMemory,
    AgentMemory? agentMemory,
  }) async {
    final url = constructUrl("/api/chat");

    final response = await http.post(
      url,
      headers: headers,
      body: json.encode({
        "model": chat.model,
        "messages": await _prepareMessagesWithSystemPrompt(
          messages, chat.systemPrompt,
          conversationMemory: conversationMemory,
          agentMemory: agentMemory,
        ),
        if (_buildOptions(chat.options) != null) "options": _buildOptions(chat.options),
        "stream": false,
      }),
    );
    // ... rest unchanged ...
  }

  Stream<OllamaMessage> chatStream(
    List<OllamaMessage> messages, {
    required OllamaChat chat,
    ConversationMemory? conversationMemory,
    AgentMemory? agentMemory,
  }) async* {
    final url = constructUrl('/api/chat');

    final request = http.Request("POST", url);
    request.headers.addAll(headers);
    request.body = json.encode({
      "model": chat.model,
      "messages": await _prepareMessagesWithSystemPrompt(
        messages, chat.systemPrompt,
        conversationMemory: conversationMemory,
        agentMemory: agentMemory,
      ),
      if (_buildOptions(chat.options) != null) "options": _buildOptions(chat.options),
      "stream": true,
    });
    // ... rest unchanged ...
  }
```

- [ ] **Step 3: Commit**

```bash
git add lib/Services/ollama_service.dart
git commit -m "Update OllamaService: inject memories into system prompt, limit to last 10 messages"
```

---

### Task 8: Fix Edit+Resend Bug

**Files:**
- Modify: `lib/Providers/chat_provider.dart`
- Modify: `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart`
- Modify: `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_actions.dart`

- [ ] **Step 1: Add editAndResend method to ChatProvider**

Add this new method to `ChatProvider`:

```dart
  /// Sends the edited text as a new message at the bottom, preserving all history.
  Future<void> editAndResend(OllamaMessage originalMessage, String newContent) async {
    final associatedChat = currentChat!;

    // Create a new user message with the edited content
    final newMessage = OllamaMessage(
      newContent.trim(),
      role: OllamaMessageRole.user,
      images: originalMessage.images,
    );
    _messages.add(newMessage);

    _activeChatStreams[associatedChat.id] = null;
    notifyListeners();

    // Save the new message to the database
    await _databaseService.addMessage(newMessage, chat: associatedChat);

    // Start a new response
    await _initializeChatStream(associatedChat);
  }
```

- [ ] **Step 2: Update chat_bubble_actions.dart — change handleEdit to return edited text without saving**

Replace `handleEdit` so it no longer calls `chatProvider.updateMessage`. It should only return the new text:

```dart
  /// Opens edit sheet. Returns the new text if saved, null if cancelled.
  Future<String?> handleEdit(BuildContext context) async {
    return await showModalBottomSheet<String?>(
      context: context,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) {
        String textFieldText = message.content;

        return ChatBubbleBottomSheet(
          title: 'Edit Message',
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (textFieldText.isNotEmpty) {
                  Navigator.pop(context, textFieldText);
                }
              },
              child: const Text('Send as New'),
            ),
          ],
          child: TextFormField(
            initialValue: textFieldText,
            onChanged: (value) => textFieldText = value,
            autofocus: true,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(border: OutlineInputBorder()),
          ),
        );
      },
    );
  }
```

- [ ] **Step 3: Update chat_bubble.dart — call editAndResend instead of regenerate**

In `_UserActionButtons`, change the Edit button's `onTap`:

```dart
        _ActionChip(
          icon: Icons.edit_outlined,
          label: 'Edit',
          color: colorScheme.onSurfaceVariant,
          onTap: () async {
            final result = await actions.handleEdit(context);
            if (result != null && context.mounted) {
              final chatProvider = Provider.of<ChatProvider>(context, listen: false);
              chatProvider.editAndResend(message, result);
            }
          },
        ),
```

- [ ] **Step 4: Commit**

```bash
git add lib/Providers/chat_provider.dart lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_actions.dart
git commit -m "Fix edit+resend: add edited text as new message, preserve all history"
```

---

### Task 9: Memory Status Indicator (Glowing Star)

**Files:**
- Create: `lib/Widgets/memory_status_indicator.dart`
- Modify: `lib/Pages/chat_page/subwidgets/chat_text_field.dart`

- [ ] **Step 1: Create the glowing star widget**

```dart
// lib/Widgets/memory_status_indicator.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:llamaseek/Services/memory_service.dart';

class MemoryStatusIndicator extends StatefulWidget {
  const MemoryStatusIndicator({super.key});

  @override
  State<MemoryStatusIndicator> createState() => _MemoryStatusIndicatorState();
}

class _MemoryStatusIndicatorState extends State<MemoryStatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MemoryService>(
      builder: (context, memoryService, _) {
        if (!memoryService.isEnabled) return const SizedBox.shrink();

        if (memoryService.isUpdating) {
          _controller.repeat(reverse: true);
        } else {
          _controller.stop();
          _controller.value = 0.0;
        }

        return AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            final color = memoryService.isUpdating
                ? Theme.of(context).colorScheme.primary.withValues(alpha: _animation.value)
                : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3);

            return Tooltip(
              message: memoryService.isUpdating
                  ? 'Updating memory...'
                  : 'Memory idle',
              child: Icon(
                Icons.auto_awesome,
                size: 18,
                color: color,
              ),
            );
          },
        );
      },
    );
  }
}
```

- [ ] **Step 2: Add the indicator to chat_text_field.dart**

Read `lib/Pages/chat_page/subwidgets/chat_text_field.dart` first, then add the `MemoryStatusIndicator` widget near the text field (e.g., as a prefix or next to the send button area). The exact placement depends on the current layout — add it as a small icon to the left of the text field or in the input row.

Add import:

```dart
import 'package:llamaseek/Widgets/memory_status_indicator.dart';
```

Insert the widget in the input row. The exact position will need to be adapted to the current layout, but it should be a small icon visible during chat.

- [ ] **Step 3: Commit**

```bash
git add lib/Widgets/memory_status_indicator.dart lib/Pages/chat_page/subwidgets/chat_text_field.dart
git commit -m "Add glowing star memory status indicator near chat input"
```

---

### Task 10: Memory Bottom Sheet (Shared Viewer/Editor)

**Files:**
- Create: `lib/Widgets/memory_bottom_sheet.dart`

Uses the same `ChatBubbleBottomSheet` pattern (Scaffold + AppBar with close button + bottom actions) for consistent UI/UX with the existing chat bubble edit window.

- [ ] **Step 1: Create the reusable memory bottom sheet**

```dart
// lib/Widgets/memory_bottom_sheet.dart
import 'package:flutter/material.dart';
import 'package:llamaseek/Constants/memory_constants.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_bottom_sheet.dart';

class MemorySection {
  final String label;
  final String key;
  String value;

  MemorySection({required this.label, required this.key, required this.value});

  int get estimatedTokens => (value.length / 4).ceil();
}

/// Shows a memory editor bottom sheet using the same Scaffold+AppBar pattern
/// as ChatBubbleBottomSheet for consistent UI/UX.
Future<void> showMemoryBottomSheet(
  BuildContext context, {
  required String title,
  required List<MemorySection> sections,
  required int maxTotalTokens,
  required void Function(List<MemorySection> updatedSections) onSave,
  VoidCallback? onClear,
  Future<String?> Function(String content, int tokenLimit)? onResummarize,
}) {
  return showModalBottomSheet(
    context: context,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.9,
    ),
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (context) {
      return _MemoryEditorSheet(
        title: title,
        sections: sections,
        maxTotalTokens: maxTotalTokens,
        onSave: onSave,
        onClear: onClear,
        onResummarize: onResummarize,
      );
    },
  );
}

class _MemoryEditorSheet extends StatefulWidget {
  final String title;
  final List<MemorySection> sections;
  final int maxTotalTokens;
  final void Function(List<MemorySection> updatedSections) onSave;
  final VoidCallback? onClear;
  final Future<String?> Function(String content, int tokenLimit)? onResummarize;

  const _MemoryEditorSheet({
    required this.title,
    required this.sections,
    required this.maxTotalTokens,
    required this.onSave,
    this.onClear,
    this.onResummarize,
  });

  @override
  State<_MemoryEditorSheet> createState() => _MemoryEditorSheetState();
}

class _MemoryEditorSheetState extends State<_MemoryEditorSheet> {
  late List<MemorySection> _sections;

  @override
  void initState() {
    super.initState();
    _sections = widget.sections
        .map((s) => MemorySection(label: s.label, key: s.key, value: s.value))
        .toList();
  }

  int get _totalTokens =>
      _sections.fold(0, (sum, s) => sum + s.estimatedTokens);

  bool get _exceedsLimit => _totalTokens > widget.maxTotalTokens;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Uses ChatBubbleBottomSheet pattern: Scaffold + AppBar + bottom actions
    return ChatBubbleBottomSheet(
      title: widget.title,
      actions: [
        if (widget.onClear != null)
          TextButton(
            onPressed: () => _confirmClear(context),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        Text(
          '~$_totalTokens tokens',
          style: TextStyle(
            fontSize: 12,
            color: _exceedsLimit ? Colors.red : colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _handleSave,
          child: const Text('Save'),
        ),
      ],
      child: Column(
        children: [
          if (_exceedsLimit)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Memory exceeds token limit. Reduce content or it will be auto-resummarized.',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: _sections.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final section = _sections[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          section.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          '~${section.estimatedTokens} tokens',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: section.value,
                      onChanged: (value) {
                        setState(() {
                          section.value = value;
                        });
                      },
                      maxLines: null,
                      minLines: 2,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                        hintText: 'No ${section.label.toLowerCase()} recorded',
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSave() async {
    if (_exceedsLimit && widget.onResummarize != null) {
      final shouldResummarize = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Memory Too Large'),
          content: const Text(
            'Memory exceeds the allowed size. Reduce content manually, or auto-resummarize to fit?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Go Back'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Auto-Resummarize'),
            ),
          ],
        ),
      );

      if (shouldResummarize == true) {
        for (final section in _sections) {
          if (section.estimatedTokens > MemoryConstants.maxPerSectionTokens) {
            final condensed = await widget.onResummarize!(
              section.value,
              MemoryConstants.maxPerSectionTokens,
            );
            if (condensed != null) {
              setState(() {
                section.value = condensed;
              });
            }
          }
        }
      } else {
        return;
      }
    }

    widget.onSave(_sections);
    if (mounted) Navigator.pop(context);
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Memory?'),
        content: const Text('This will delete all memory data. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              widget.onClear?.call();
              Navigator.pop(this.context); // close bottom sheet
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/Widgets/memory_bottom_sheet.dart
git commit -m "Add reusable MemoryBottomSheet: section editor with token warnings"
```

---

### Task 11: Sidebar Integration — Agent Memory Tile + Chat Context Menu

**Files:**
- Modify: `lib/Widgets/chat_drawer.dart`

- [ ] **Step 1: Add Agent Memory tile to sidebar**

Add imports at the top of `chat_drawer.dart`:

```dart
import 'package:provider/provider.dart';
import 'package:llamaseek/Services/memory_service.dart';
import 'package:llamaseek/Models/agent_memory.dart';
import 'package:llamaseek/Models/conversation_memory.dart';
import 'package:llamaseek/Constants/memory_constants.dart';
import 'package:llamaseek/Widgets/memory_bottom_sheet.dart';
```

In `ChatDrawer.build()`, add the Agent Memory tile between the `Expanded(child: ChatNavigationDrawer())` and the settings icon container:

```dart
child: Column(
  children: [
    const Expanded(child: ChatNavigationDrawer()),
    Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
      child: _AgentMemoryTile(),
    ),
    Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 10),
      child: IconButton(
        icon: const Icon(Icons.settings_outlined),
        onPressed: () {
          // ... existing settings navigation ...
        },
      ),
    ),
  ],
),
```

Add the `_AgentMemoryTile` widget class:

```dart
class _AgentMemoryTile extends StatelessWidget {
  const _AgentMemoryTile();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () => _showAgentMemory(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            Icon(Icons.auto_awesome_outlined, color: colorScheme.onSurfaceVariant, size: 22),
            const SizedBox(width: 12),
            Text(
              'Agent Memory',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  void _showAgentMemory(BuildContext context) async {
    final memoryService = Provider.of<MemoryService>(context, listen: false);
    final agentMemory = await memoryService.getAgentMemory() ?? AgentMemory();

    if (!context.mounted) return;

    showMemoryBottomSheet(
      context,
      title: 'Agent Memory',
      maxTotalTokens: MemoryConstants.maxAgentMemoryTokens,
      sections: [
          MemorySection(label: 'User Profile', key: 'user_profile', value: agentMemory.userProfile),
          MemorySection(label: 'Preferences', key: 'preferences', value: agentMemory.preferences),
          MemorySection(label: 'Learned Facts', key: 'learned_facts', value: agentMemory.learnedFacts),
          MemorySection(label: 'Interests & Expertise', key: 'interests_and_expertise', value: agentMemory.interestsAndExpertise),
          MemorySection(label: 'Language & Tone', key: 'language_and_tone', value: agentMemory.languageAndTone),
        ],
      onSave: (sections) {
        final updated = AgentMemory(
          userProfile: sections.firstWhere((s) => s.key == 'user_profile').value,
          preferences: sections.firstWhere((s) => s.key == 'preferences').value,
          learnedFacts: sections.firstWhere((s) => s.key == 'learned_facts').value,
          interestsAndExpertise: sections.firstWhere((s) => s.key == 'interests_and_expertise').value,
          languageAndTone: sections.firstWhere((s) => s.key == 'language_and_tone').value,
        );
        memoryService.updateAgentMemoryField(updated);
      },
      onClear: () => memoryService.clearAgentMemory(),
      onResummarize: (content, limit) => memoryService.resummarize(content, limit),
    );
  }
}
```

- [ ] **Step 2: Add "Memory" option to chat context menu**

In `ChatNavigationDrawer._showChatContextMenu`, add the `memory` option to `_GlassContextMenu`:

```dart
child: _GlassContextMenu(
  onRename: () => Navigator.pop(dialogContext, 'rename'),
  onMemory: () => Navigator.pop(dialogContext, 'memory'),
  onDelete: () => Navigator.pop(dialogContext, 'delete'),
  chatTitle: chat.title,
),
```

Handle the result:

```dart
    } else if (result == 'memory') {
      _showConversationMemory(context, chat);
    } else if (result == 'delete') {
```

Add the `_showConversationMemory` method:

```dart
  void _showConversationMemory(BuildContext context, OllamaChat chat) async {
    final memoryService = Provider.of<MemoryService>(context, listen: false);
    final convMemory = await memoryService.getConversationMemory(chat.id) ?? ConversationMemory();

    if (!context.mounted) return;

    showMemoryBottomSheet(
      context,
      title: 'Conversation Memory',
      maxTotalTokens: MemoryConstants.maxConversationMemoryTokens,
      sections: [
          MemorySection(label: 'Summary', key: 'summary', value: convMemory.summary),
          MemorySection(label: 'Key Context', key: 'key_context', value: convMemory.keyContext),
          MemorySection(label: 'Media Descriptions', key: 'media_descriptions', value: convMemory.mediaDescriptions),
          MemorySection(label: 'Current State', key: 'current_state', value: convMemory.currentState),
          MemorySection(label: 'Model History', key: 'model_history', value: convMemory.modelHistory),
          MemorySection(label: 'Unresolved Items', key: 'unresolved_items', value: convMemory.unresolvedItems),
        ],
      onSave: (sections) {
        final updated = ConversationMemory(
          summary: sections.firstWhere((s) => s.key == 'summary').value,
          keyContext: sections.firstWhere((s) => s.key == 'key_context').value,
          mediaDescriptions: sections.firstWhere((s) => s.key == 'media_descriptions').value,
          currentState: sections.firstWhere((s) => s.key == 'current_state').value,
          modelHistory: sections.firstWhere((s) => s.key == 'model_history').value,
          unresolvedItems: sections.firstWhere((s) => s.key == 'unresolved_items').value,
        );
        memoryService.updateConversationMemoryField(chat.id, updated);
      },
      onClear: () {
        memoryService.updateConversationMemoryField(chat.id, ConversationMemory());
      },
      onResummarize: (content, limit) => memoryService.resummarize(content, limit),
    );
  }
```

Update `_GlassContextMenu` to accept `onMemory`:

```dart
class _GlassContextMenu extends StatelessWidget {
  final VoidCallback onRename;
  final VoidCallback onMemory;
  final VoidCallback onDelete;
  final String chatTitle;

  const _GlassContextMenu({
    required this.onRename,
    required this.onMemory,
    required this.onDelete,
    required this.chatTitle,
  });
```

And add the memory menu item between Rename and Delete:

```dart
            _GlassMenuItem(
              icon: Icons.edit_outlined,
              label: 'Rename',
              onTap: onRename,
            ),
            _GlassMenuItem(
              icon: Icons.auto_awesome_outlined,
              label: 'Memory',
              onTap: onMemory,
            ),
            _GlassMenuItem(
              icon: Icons.delete_outline,
              label: 'Delete',
              onTap: onDelete,
              isDestructive: true,
            ),
```

- [ ] **Step 3: Commit**

```bash
git add lib/Widgets/chat_drawer.dart
git commit -m "Add Agent Memory tile and conversation Memory option to sidebar"
```

---

### Task 12: Settings — Memory Model Configuration

**Files:**
- Modify: `lib/Pages/settings_page/subwidgets/server_settings.dart`
- Modify: `lib/Pages/settings_page/settings_page.dart`

- [ ] **Step 1: Add memory model setting to server_settings.dart**

Read the current file first to find the right place to add the setting. Add a new section below cloud settings for "Memory Model":

```dart
// Inside the server settings widget, add after the cloud API key field:

const SizedBox(height: 16),
Text('Memory Model', style: Theme.of(context).textTheme.titleSmall),
const SizedBox(height: 8),
TextFormField(
  initialValue: settingsBox.get('memoryModel', defaultValue: MemoryConstants.defaultModel),
  decoration: InputDecoration(
    labelText: 'Summarization Model',
    hintText: MemoryConstants.defaultModel,
    border: OutlineInputBorder(),
    helperText: 'Model used for memory summarization (via Ollama Cloud)',
  ),
  onChanged: (value) {
    settingsBox.put('memoryModel', value.trim().isEmpty ? MemoryConstants.defaultModel : value.trim());
  },
),
```

Add import:

```dart
import 'package:llamaseek/Constants/memory_constants.dart';
```

- [ ] **Step 2: Commit**

```bash
git add lib/Pages/settings_page/subwidgets/server_settings.dart
git commit -m "Add memory model setting to server settings"
```

---

### Task 13: Wire ChatPageViewModel for Memory Status

**Files:**
- Modify: `lib/Pages/chat_page/chat_page_view_model.dart`

- [ ] **Step 1: Proxy MemoryService state**

This is only needed if the chat_text_field reads from the ViewModel rather than directly from Provider. Check the current pattern — if `chat_text_field` uses `Consumer<MemoryService>` directly (via the Provider tree), no changes to ViewModel are needed.

If the text field reads from ViewModel, add:

```dart
final MemoryService _memoryService;

// In constructor, add parameter and listener:
ChatPageViewModel({
  required ChatProvider chatProvider,
  required PermissionService permissionService,
  required ImageService imageService,
  required MemoryService memoryService,
})  : _chatProvider = chatProvider,
      _permissionService = permissionService,
      _imageService = imageService,
      _memoryService = memoryService {
  _initialize();
  _memoryService.addListener(_onMemoryServiceChanged);
}

void _onMemoryServiceChanged() {
  notifyListeners();
}

bool get isMemoryUpdating => _memoryService.isUpdating;
```

Update `dispose()`:

```dart
@override
void dispose() {
  _chatProvider.removeListener(_onChatProviderChanged);
  _memoryService.removeListener(_onMemoryServiceChanged);
  // ... rest of dispose ...
}
```

And update `main.dart` to pass `memoryService` to `ChatPageViewModel`:

```dart
ChangeNotifierProvider(
  create: (context) => ChatPageViewModel(
    chatProvider: context.read(),
    permissionService: context.read(),
    imageService: context.read(),
    memoryService: context.read<MemoryService>(),
  ),
),
```

- [ ] **Step 2: Commit**

```bash
git add lib/Pages/chat_page/chat_page_view_model.dart lib/main.dart
git commit -m "Wire ChatPageViewModel with MemoryService for status indicator"
```

---

### Task 14: End-to-End Integration Test

- [ ] **Step 1: Build and verify**

Run:

```bash
cd /Users/songli/LlamaSeek && flutter build ios --release --no-codesign 2>&1 | tail -20
```

Expected: Build succeeds with no errors.

- [ ] **Step 2: Manual verification checklist**

1. App launches without crashing (migration v4 runs)
2. Sending a message with cloud API key configured triggers memory update (star glows)
3. Long-pressing a chat in sidebar shows "Memory" option
4. Tapping "Agent Memory" in sidebar opens the editor
5. Editing a mid-conversation message adds it as a new message at the bottom
6. Without a cloud API key, app functions normally — no memory features, no errors
7. Memory model can be changed in settings

- [ ] **Step 3: Commit any fixes**

```bash
git add -A && git commit -m "Fix integration issues from end-to-end testing"
```
