import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:llamaseek/Models/ephemeral_context.dart';
import 'package:llamaseek/Models/memory_topic.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Services/database_service.dart';
import 'package:llamaseek/Services/memory_service.dart';

/// Minimal fake DB: only the reads the retrieval/generation paths touch.
class _FakeDb extends DatabaseService {
  @override
  Future<List<MemoryTopic>> getAllTopics() async =>
      [MemoryTopic(id: 1, topicKey: 'Flutter development', content: 'uses streams')];

  @override
  Future<List<EphemeralContext>> getAllEphemeralContexts() async => [];
}

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('mem_route_test').path);
    await Hive.openBox('settings');
  });

  setUp(() {
    final box = Hive.box('settings');
    box.put('cloudApiKey', 'test-key');
    box.delete('memoryModel');
    box.delete('memoryRetrievalModel');
  });

  test('retrieval (selectRelevantContext) uses the fast retrieval model', () async {
    String? captured;
    final mock = MockClient((req) async {
      captured = (jsonDecode(req.body) as Map)['model'] as String;
      return http.Response(
          jsonEncode({'message': {'content': '{"relevant_keys": []}'}}), 200);
    });
    final mem = MemoryService(db: _FakeDb(), client: mock);

    await mem.selectRelevantContext(
      [OllamaMessage('How do I use Flutter streams?', role: OllamaMessageRole.user)],
    );

    expect(captured, 'ministral-3:8b');
  });

  test('generation (resummarize) uses the powerful generation model', () async {
    String? captured;
    final mock = MockClient((req) async {
      captured = (jsonDecode(req.body) as Map)['model'] as String;
      return http.Response(
          jsonEncode({'message': {'content': 'condensed'}}), 200);
    });
    final mem = MemoryService(db: _FakeDb(), client: mock);

    await mem.resummarize('a long block of memory content to condense', 1000);

    expect(captured, 'gpt-oss:120b-cloud');
  });
}
