import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:llamaseek/Models/agent_memory.dart';
import 'package:llamaseek/Models/conversation_memory.dart';
import 'package:llamaseek/Models/ephemeral_context.dart';
import 'package:llamaseek/Models/memory_topic.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Services/database_service.dart';
import 'package:llamaseek/Services/memory_service.dart';

/// Records conversation-memory writes so a test can assert what — if
/// anything — gets persisted. Overrides only the surface the memory paths touch.
class _CapturingDb extends DatabaseService {
  final List<ConversationMemory> convWrites = [];
  ConversationMemory? seededConvMemory;

  @override
  Future<ConversationMemory?> getConversationMemory(String chatId) async =>
      seededConvMemory;

  @override
  Future<void> updateConversationMemory(
      String chatId, ConversationMemory memory) async {
    convWrites.add(memory);
  }

  @override
  Future<AgentMemory?> getAgentMemory() async => null;

  @override
  Future<List<MemoryTopic>> getAllTopics() async => [];

  @override
  Future<List<EphemeralContext>> getAllEphemeralContexts() async => [];

  @override
  Future<int> cleanupExpiredEphemeral() async => 0;
}

List<OllamaMessage> _conversation(int n) => List.generate(
      n,
      (i) => OllamaMessage('m$i',
          role: i.isEven ? OllamaMessageRole.user : OllamaMessageRole.assistant),
    );

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('mem_pollution_test').path);
    await Hive.openBox('settings');
    await Hive.box('settings').put('cloudApiKey', 'test-key');
  });

  group('F1a: raw memory-model output must not pollute conversation memory', () {
    test('non-JSON response does NOT overwrite existing conversation memory',
        () async {
      final db = _CapturingDb()
        ..seededConvMemory = ConversationMemory(summary: 'GOOD prior summary');
      final mem = MemoryService(db: db);

      // Model failed to return JSON and instead emitted prose/meta-commentary.
      await mem.parseAndSave(
        'chat-1',
        'Sure! Here is the summary you asked for: the user likes pasta.',
        skipAgentMemory: true,
      );

      expect(
        db.convWrites,
        isEmpty,
        reason:
            'raw non-JSON output must not be persisted as the conversation '
            'summary — it would be injected verbatim as authoritative context',
      );
    });

    // Regression guard: the fix must not disable the valid path.
    test('valid JSON conversation_memory IS still persisted', () async {
      final db = _CapturingDb();
      final mem = MemoryService(db: db);

      await mem.parseAndSave(
        'chat-1',
        '{"conversation_memory": {"summary": "user is building a Flutter app"}}',
        skipAgentMemory: true,
      );

      expect(db.convWrites, hasLength(1));
      expect(db.convWrites.single.summary, 'user is building a Flutter app');
    });
  });

  group('F2: coverage marker advances without gaps', () {
    test('parseAndSave stamps the coverage marker onto saved memory', () async {
      final db = _CapturingDb();
      final mem = MemoryService(db: db);

      await mem.parseAndSave(
        'chat-1',
        '{"conversation_memory": {"summary": "s"}}',
        skipAgentMemory: true,
        summarizedThrough: 25,
      );

      expect(db.convWrites.single.summarizedMessageCount, 25);
    });

    test('summarizer ingests the un-summarized tail and advances coverage',
        () async {
      // 40 messages; the summary currently covers only the first 15.
      final db = _CapturingDb()
        ..seededConvMemory = ConversationMemory(
            summary: 'covers first 15', summarizedMessageCount: 15);

      String? capturedPrompt;
      final mock = MockClient((req) async {
        capturedPrompt =
            (jsonDecode(req.body) as Map)['messages'][0]['content'] as String;
        return http.Response(
          jsonEncode({
            'message': {'content': '{"conversation_memory": {"summary": "u"}}'}
          }),
          200,
        );
      });
      final mem = MemoryService(db: db, client: mock);

      await mem.performUpdate(
        chatId: 'chat-1',
        messages: _conversation(40),
        skipAgentMemory: true,
      );

      // Ingested the tail from the coverage boundary (15) — the OLD last-20
      // window (m20..m39) would have silently skipped m15..m19.
      expect(capturedPrompt, contains('m15'),
          reason: 'summarizer must ingest the gap the summary has not covered');
      expect(capturedPrompt, contains('m39'));
      // Coverage advances to len - recentMessagesToKeep = 40 - 20 = 20.
      expect(db.convWrites, isNotEmpty);
      expect(db.convWrites.last.summarizedMessageCount, 20);
    });
  });
}
