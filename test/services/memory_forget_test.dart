import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Services/memory_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:llamaseek/Constants/constants.dart';
import 'package:llamaseek/Models/agent_memory.dart';
import 'package:llamaseek/Models/ephemeral_context.dart';
import 'package:llamaseek/Models/memory_topic.dart';
import 'package:llamaseek/Services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'dart:io';

void main() {
  group('parseForgetResponse', () {
    test('parses profile, topic upserts/deletes, ephemeral deletes', () {
      const raw = '''
      Sure, here is the JSON:
      {
        "profile": { "name": "Song", "primary_language": "English",
          "tone_and_formality": "", "role_and_background": "",
          "communication_style": "" },
        "topics": [
          { "key": "pets", "delete": true },
          { "key": "Flutter dev", "content": "uses Provider" }
        ],
        "ephemeral": [ { "key": "debugging crash", "delete": true } ]
      }''';

      final result = MemoryService.parseForgetResponse(raw)!;
      expect(result.profile!.name, 'Song');
      expect(result.profile!.primaryLanguage, 'English');
      expect(result.topicDeletions, contains('pets'));
      expect(result.topicUpserts.map((t) => t.topicKey), contains('Flutter dev'));
      expect(result.topicUpserts.single.content, 'uses Provider');
      expect(result.ephemeralDeletions, contains('debugging crash'));
    });

    test('treats empty topic content as a deletion', () {
      const raw = '{ "topics": [ { "key": "gone", "content": "" } ] }';
      final result = MemoryService.parseForgetResponse(raw)!;
      expect(result.topicDeletions, contains('gone'));
      expect(result.topicUpserts, isEmpty);
    });

    test('returns null on non-JSON', () {
      expect(MemoryService.parseForgetResponse('no json here'), isNull);
    });

    test('empty JSON object yields a non-null result with no mutations', () {
      final result = MemoryService.parseForgetResponse('{}')!;
      expect(result.profile, isNull);
      expect(result.topicUpserts, isEmpty);
      expect(result.topicDeletions, isEmpty);
      expect(result.ephemeralDeletions, isEmpty);
    });

    test('non-list topics/ephemeral are ignored', () {
      const raw = '{ "topics": "oops", "ephemeral": {} }';
      final result = MemoryService.parseForgetResponse(raw)!;
      expect(result.topicUpserts, isEmpty);
      expect(result.topicDeletions, isEmpty);
      expect(result.ephemeralDeletions, isEmpty);
    });

    test('non-map entries inside arrays are skipped', () {
      const raw = '{ "topics": [1, "x", null], "ephemeral": [true, 2] }';
      final result = MemoryService.parseForgetResponse(raw)!;
      expect(result.topicUpserts, isEmpty);
      expect(result.topicDeletions, isEmpty);
      expect(result.ephemeralDeletions, isEmpty);
    });
  });

  group('applyForgetResult', () {
    late DatabaseService db;
    late MemoryService memory;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      PathProviderPlatform.instance = _ForgetFakePathProvider();
      await PathManager.initialize();
      Hive.init(Directory.systemTemp.createTempSync('forget_hive').path);
      if (!Hive.isBoxOpen('settings')) await Hive.openBox('settings');

      final dbPath = path.join(await getDatabasesPath(), 'forget_apply_test.db');
      await databaseFactoryFfi.deleteDatabase(dbPath);
      db = DatabaseService();
      await db.open('forget_apply_test.db');
      memory = MemoryService(db: db);
    });

    test('deletes flagged topics/ephemeral and overwrites the profile', () async {
      await db.updateAgentMemory(AgentMemory(name: 'Song', roleAndBackground: 'chef'));
      final keepId = await db.insertTopic(MemoryTopic(topicKey: 'Flutter dev', content: 'old'));
      await db.insertTopic(MemoryTopic(topicKey: 'pets', content: 'has a cat'));
      await db.insertEphemeralContext(EphemeralContext(contextKey: 'crash', content: 'x'));

      final topics = await db.getAllTopics();
      final ephemeral = await db.getAllEphemeralContexts();

      final result = ForgetResult(
        profile: AgentMemory(name: 'Song'), // role scrubbed
        topicUpserts: [MemoryTopic(topicKey: 'Flutter dev', content: 'uses Provider')],
        topicDeletions: ['pets'],
        ephemeralDeletions: ['crash'],
      );

      await memory.applyForgetResult(result,
          activeEphemeral: ephemeral, existingTopics: topics);

      final profile = await db.getAgentMemory();
      expect(profile!.name, 'Song');
      expect(profile.roleAndBackground, '');

      final remaining = await db.getAllTopics();
      expect(remaining.map((t) => t.topicKey), isNot(contains('pets')));
      expect(remaining.firstWhere((t) => t.topicKey == 'Flutter dev').content, 'uses Provider');
      expect(keepId, isNotNull);

      expect(await db.getAllEphemeralContexts(), isEmpty);
    });
  });
}

class _ForgetFakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      Directory.systemTemp.createTempSync('forget_docs').path;
}
