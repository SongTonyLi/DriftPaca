import 'dart:convert';
import 'dart:io';

import 'package:llamaseek/Constants/constants.dart';
import 'package:llamaseek/Models/agent_memory.dart';
import 'package:llamaseek/Models/conversation_memory.dart';
import 'package:llamaseek/Models/memory_topic.dart';
import 'package:llamaseek/Models/ephemeral_context.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;

class DatabaseService {
  late Database _db;

  Future<String> getDatabasesPathForPlatform() async {
    if (Platform.isLinux) {
      return PathManager.instance.documentsDirectory.path;
    } else {
      return await getDatabasesPath();
    }
  }

  Future<void> open(String databaseFile) async {
    _db = await openDatabase(
      path.join(await getDatabasesPathForPlatform(), databaseFile),
      version: 8,
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
        if (oldVersion < 5) {
          await db.execute("ALTER TABLE agent_memory ADD COLUMN key_people TEXT DEFAULT ''");
          await db.execute("ALTER TABLE agent_memory ADD COLUMN ongoing_projects TEXT DEFAULT ''");
          await db.execute("ALTER TABLE agent_memory ADD COLUMN past_conversation_refs TEXT DEFAULT ''");
        }
        if (oldVersion < 6) {
          await db.execute("ALTER TABLE chats ADD COLUMN is_incognito INTEGER DEFAULT 0");
        }
        if (oldVersion < 7) {
          await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id)');
        }
        if (oldVersion < 8) {
          await db.execute('DROP TABLE IF EXISTS agent_memory');
          await db.execute('''CREATE TABLE IF NOT EXISTS agent_memory (
id INTEGER PRIMARY KEY DEFAULT 1,
name TEXT DEFAULT '',
primary_language TEXT DEFAULT '',
tone_and_formality TEXT DEFAULT '',
role_and_background TEXT DEFAULT '',
communication_style TEXT DEFAULT '',
updated_at INTEGER
)''');
          await db.execute('''CREATE TABLE IF NOT EXISTS agent_memory_topics (
id INTEGER PRIMARY KEY AUTOINCREMENT,
topic_key TEXT NOT NULL,
content TEXT NOT NULL,
created_at INTEGER NOT NULL,
updated_at INTEGER NOT NULL
)''');
          await db.execute('''CREATE TABLE IF NOT EXISTS agent_memory_ephemeral (
id INTEGER PRIMARY KEY AUTOINCREMENT,
context_key TEXT NOT NULL,
content TEXT NOT NULL,
source_chat_id TEXT,
created_at INTEGER NOT NULL,
expires_at INTEGER NOT NULL
)''');
        }
      },
      onCreate: (Database db, int version) async {
        await db.execute('''CREATE TABLE IF NOT EXISTS chats (
chat_id TEXT PRIMARY KEY,
model TEXT NOT NULL,
chat_title TEXT NOT NULL,
system_prompt TEXT,
options TEXT,
conversation_memory TEXT,
is_incognito INTEGER DEFAULT 0
) WITHOUT ROWID;''');

        await db.execute('''CREATE TABLE IF NOT EXISTS messages (
message_id TEXT PRIMARY KEY,
chat_id TEXT NOT NULL,
content TEXT NOT NULL,
thinking TEXT,
images TEXT,
role TEXT CHECK(role IN ('user', 'assistant', 'system')) NOT NULL,
model TEXT,
timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
FOREIGN KEY (chat_id) REFERENCES chats(chat_id) ON DELETE CASCADE
) WITHOUT ROWID;''');

        // Create cleanup_jobs table
        await db.execute('''CREATE TABLE IF NOT EXISTS cleanup_jobs (
id INTEGER PRIMARY KEY AUTOINCREMENT,
image_paths TEXT NOT NULL
)''');

        // Create trigger to handle image deletion
        await db.execute('''CREATE TRIGGER IF NOT EXISTS delete_images_trigger
AFTER DELETE ON messages
WHEN OLD.images IS NOT NULL
BEGIN
  INSERT INTO cleanup_jobs (image_paths) VALUES (OLD.images);
END;''');

        await db.execute('''CREATE TABLE IF NOT EXISTS agent_memory (
id INTEGER PRIMARY KEY DEFAULT 1,
name TEXT DEFAULT '',
primary_language TEXT DEFAULT '',
tone_and_formality TEXT DEFAULT '',
role_and_background TEXT DEFAULT '',
communication_style TEXT DEFAULT '',
updated_at INTEGER
)''');

        await db.execute('''CREATE TABLE IF NOT EXISTS agent_memory_topics (
id INTEGER PRIMARY KEY AUTOINCREMENT,
topic_key TEXT NOT NULL,
content TEXT NOT NULL,
created_at INTEGER NOT NULL,
updated_at INTEGER NOT NULL
)''');

        await db.execute('''CREATE TABLE IF NOT EXISTS agent_memory_ephemeral (
id INTEGER PRIMARY KEY AUTOINCREMENT,
context_key TEXT NOT NULL,
content TEXT NOT NULL,
source_chat_id TEXT,
created_at INTEGER NOT NULL,
expires_at INTEGER NOT NULL
)''');

        await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id)');
      },
    );
  }

  Future<void> close() async => _db.close();

  // Chat Operations

  Future<OllamaChat> createChat(String model, {bool isIncognito = false}) async {
    final id = Uuid().v4();

    await _db.insert('chats', {
      'chat_id': id,
      'model': model,
      'chat_title': isIncognito ? 'Incognito Chat' : 'New Chat',
      'system_prompt': null,
      'options': null,
      'is_incognito': isIncognito ? 1 : 0,
    });

    return (await getChat(id))!;
  }

  Future<OllamaChat?> getChat(String chatId) async {
    final List<Map<String, dynamic>> maps = await _db.query(
      'chats',
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );

    if (maps.isEmpty) {
      return null;
    } else {
      return OllamaChat.fromMap(maps.first);
    }
  }

  Future<void> updateChat(
    OllamaChat chat, {
    String? newModel,
    String? newTitle,
    String? newSystemPrompt,
    OllamaChatOptions? newOptions,
  }) async {
    await _db.update(
      'chats',
      {
        'model': newModel ?? chat.model,
        'chat_title': newTitle ?? chat.title,
        'system_prompt': newSystemPrompt ?? chat.systemPrompt,
        'options': newOptions?.toJson() ?? chat.options.toJson(),
      },
      where: 'chat_id = ?',
      whereArgs: [chat.id],
    );
  }

  Future<void> deleteChat(String chatId) async {
    await _db.delete(
      'chats',
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );

    await _db.delete(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );

    // ? Should we run with Isolate.run?
    _cleanupDeletedImages();
  }

  Future<OllamaChat?> getChatWithLastUpdate(String chatId) async {
    final List<Map<String, dynamic>> maps = await _db.rawQuery(
      '''SELECT chats.*, MAX(messages.timestamp) AS last_update
      FROM chats
      LEFT JOIN messages ON chats.chat_id = messages.chat_id
      WHERE chats.chat_id = ?
      GROUP BY chats.chat_id''',
      [chatId],
    );

    if (maps.isEmpty) return null;
    return OllamaChat.fromMap(maps.first);
  }

  Future<List<OllamaChat>> getAllChats() async {
    final List<Map<String, dynamic>> maps = await _db.rawQuery(
        '''SELECT chats.chat_id, chats.model, chats.chat_title, chats.system_prompt, chats.options, chats.is_incognito, MAX(messages.timestamp) AS last_update
FROM chats
LEFT JOIN messages ON chats.chat_id = messages.chat_id
GROUP BY chats.chat_id
ORDER BY last_update DESC;''');

    return List.generate(maps.length, (i) {
      return OllamaChat.fromMap(maps[i]);
    });
  }

  // Message Operations

  Future<void> addMessage(
    OllamaMessage message, {
    required OllamaChat chat,
  }) async {
    await _db.insert('messages', {
      'chat_id': chat.id,
      ...message.toDatabaseMap(),
    });
  }

  Future<OllamaMessage?> getMessage(String messageId) async {
    final List<Map<String, dynamic>> maps = await _db.query(
      'messages',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );

    if (maps.isEmpty) {
      return null;
    } else {
      return OllamaMessage.fromDatabase(maps.first);
    }
  }

  Future<void> updateMessage(
    OllamaMessage message, {
    String? newContent,
  }) async {
    await _db.update(
      'messages',
      {
        'content': newContent ?? message.content,
      },
      where: 'message_id = ?',
      whereArgs: [message.id],
    );
  }

  Future<void> deleteMessage(String messageId) async {
    await _db.delete(
      'messages',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );

    _cleanupDeletedImages();
  }

  Future<List<OllamaMessage>> getMessages(String chatId) async {
    final List<Map<String, dynamic>> maps = await _db.query(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'timestamp ASC',
    );

    return List.generate(maps.length, (i) {
      return OllamaMessage.fromDatabase(maps[i]);
    });
  }

  Future<void> deleteMessages(List<OllamaMessage> messages) async {
    await _db.transaction((txn) async {
      for (final message in messages) {
        await txn.delete(
          'messages',
          where: 'message_id = ?',
          whereArgs: [message.id],
        );
      }
    });

    _cleanupDeletedImages();
  }

  // ? Should we trigger this cleanup on every message deletion?
  // ? Or should we run it on every app start?
  Future<void> _cleanupDeletedImages() async {
    final List<Map<String, dynamic>> results = await _db.query(
      'cleanup_jobs',
      columns: ['id', 'image_paths'],
      where: 'image_paths IS NOT NULL',
    );

    for (final result in results) {
      try {
        final images = _constructImages(result['image_paths']);
        if (images == null) continue;

        for (final image in images) {
          if (await image.exists()) {
            await image.delete();
          }
        }

        // Delete the row after images are deleted
        await _db.delete(
          'cleanup_jobs',
          where: 'id = ?',
          whereArgs: [result['id']],
        );
      } catch (_) {}
    }
  }

  static List<File>? _constructImages(String? raw) {
    if (raw != null) {
      final List<dynamic> decoded = jsonDecode(raw);
      return decoded.map((imageRelativePath) {
        return File(path.join(
          PathManager.instance.documentsDirectory.path,
          imageRelativePath,
        ));
      }).toList();
    }

    return null;
  }

  // ============================================================
  // Memory Operations
  // ============================================================

  // --- Conversation Memory (unchanged) ---

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

  Future<Map<String, ConversationMemory>> getAllConversationMemories() async {
    final List<Map<String, dynamic>> maps = await _db.query(
      'chats',
      columns: ['chat_id', 'conversation_memory'],
      where: 'conversation_memory IS NOT NULL AND (is_incognito IS NULL OR is_incognito = 0)',
    );

    final result = <String, ConversationMemory>{};
    for (final row in maps) {
      final chatId = row['chat_id'] as String;
      result[chatId] = ConversationMemory.fromJson(row['conversation_memory']);
    }
    return result;
  }

  // --- Tier 1: Stable Profile ---

  Future<AgentMemory?> getAgentMemory() async {
    final List<Map<String, dynamic>> maps = await _db.query(
      'agent_memory',
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return AgentMemory.fromMap(maps.first);
  }

  Future<void> updateAgentMemory(AgentMemory memory) async {
    final exists = (await _db.query('agent_memory', limit: 1)).isNotEmpty;

    if (exists) {
      await _db.update('agent_memory', memory.toMap());
    } else {
      await _db.insert('agent_memory', {'id': 1, ...memory.toMap()});
    }
  }

  Future<void> clearAgentMemory() async {
    await _db.delete('agent_memory');
  }

  // --- Tier 2: Topic Store ---

  Future<List<MemoryTopic>> getAllTopics() async {
    final maps = await _db.query('agent_memory_topics', orderBy: 'updated_at DESC');
    return maps.map((m) => MemoryTopic.fromMap(m)).toList();
  }

  Future<MemoryTopic?> getTopicByKey(String topicKey) async {
    final maps = await _db.query(
      'agent_memory_topics',
      where: 'topic_key = ?',
      whereArgs: [topicKey],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return MemoryTopic.fromMap(maps.first);
  }

  Future<int> insertTopic(MemoryTopic topic) async {
    return await _db.insert('agent_memory_topics', topic.toInsertMap());
  }

  Future<void> updateTopic(MemoryTopic topic) async {
    await _db.update(
      'agent_memory_topics',
      {
        'topic_key': topic.topicKey,
        'content': topic.content,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'topic_key = ?',
      whereArgs: [topic.topicKey],
    );
  }

  Future<void> deleteTopic(String topicKey) async {
    await _db.delete(
      'agent_memory_topics',
      where: 'topic_key = ?',
      whereArgs: [topicKey],
    );
  }

  Future<void> deleteTopicById(int id) async {
    await _db.delete(
      'agent_memory_topics',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> mergeTopics(String fromKey, String intoKey, String content) async {
    await _db.transaction((txn) async {
      await txn.delete('agent_memory_topics', where: 'topic_key = ?', whereArgs: [fromKey]);
      final existing = await txn.query('agent_memory_topics', where: 'topic_key = ?', whereArgs: [intoKey]);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (existing.isNotEmpty) {
        await txn.update(
          'agent_memory_topics',
          {'content': content, 'updated_at': now},
          where: 'topic_key = ?',
          whereArgs: [intoKey],
        );
      } else {
        await txn.insert('agent_memory_topics', {
          'topic_key': intoKey,
          'content': content,
          'created_at': now,
          'updated_at': now,
        });
      }
    });
  }

  Future<void> clearAllTopics() async {
    await _db.delete('agent_memory_topics');
  }

  // --- Tier 3: Ephemeral Context ---

  Future<List<EphemeralContext>> getAllEphemeralContexts() async {
    final maps = await _db.query('agent_memory_ephemeral', orderBy: 'created_at DESC');
    return maps.map((m) => EphemeralContext.fromMap(m)).toList();
  }

  Future<int> insertEphemeralContext(EphemeralContext ctx) async {
    return await _db.insert('agent_memory_ephemeral', ctx.toInsertMap());
  }

  Future<void> updateEphemeralContext(EphemeralContext ctx) async {
    await _db.update(
      'agent_memory_ephemeral',
      {
        'context_key': ctx.contextKey,
        'content': ctx.content,
        'expires_at': ctx.expiresAt.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [ctx.id],
    );
  }

  Future<void> deleteEphemeralContextById(int id) async {
    await _db.delete(
      'agent_memory_ephemeral',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> cleanupExpiredEphemeral() async {
    return await _db.delete(
      'agent_memory_ephemeral',
      where: 'expires_at < ?',
      whereArgs: [DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<void> clearAllEphemeral() async {
    await _db.delete('agent_memory_ephemeral');
  }
}
