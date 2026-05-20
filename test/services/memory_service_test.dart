import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/agent_memory.dart';
import 'package:llamaseek/Models/memory_topic.dart';
import 'package:llamaseek/Models/ephemeral_context.dart';
import 'package:llamaseek/Services/memory_service.dart';

void main() {
  group('MemoryService parse logic', () {
    test('applyProfileUpdates only applies high-confidence fields', () {
      final existing = AgentMemory(name: 'Song');
      final updates = {
        'name': {'value': 'Song Li', 'confidence': 'high'},
        'primary_language': {'value': 'Chinese', 'confidence': 'medium'},
        'role_and_background': {'value': 'student', 'confidence': 'low'},
        'tone_and_formality': {'value': 'casual', 'confidence': 'high'},
      };

      final result = MemoryService.applyProfileUpdates(existing, updates);
      expect(result.name, 'Song Li');
      expect(result.primaryLanguage, '');
      expect(result.roleAndBackground, '');
      expect(result.toneAndFormality, 'casual');
    });

    test('applyProfileUpdates skips null values even with high confidence', () {
      final existing = AgentMemory(name: 'Song');
      final updates = {
        'name': {'value': null, 'confidence': 'high'},
      };
      final result = MemoryService.applyProfileUpdates(existing, updates);
      expect(result.name, 'Song');
    });

    test('parseTopicUpdates handles create, update, merge', () {
      final existingTopics = [
        MemoryTopic(id: 1, topicKey: 'Flutter dev', content: 'uses Provider'),
        MemoryTopic(id: 2, topicKey: 'React basics', content: 'learning JSX'),
      ];

      final updates = [
        {'action': 'create', 'key': 'cooking', 'content': 'likes pasta'},
        {
          'action': 'update',
          'key': 'Flutter dev',
          'content': 'uses Provider, migrating to Riverpod'
        },
        {
          'action': 'merge',
          'from': 'React basics',
          'into': 'frontend web dev',
          'content': 'learning React + Vue'
        },
      ];

      final actions = MemoryService.parseTopicUpdates(updates, existingTopics);
      expect(actions.length, 3);
      expect(actions[0].type, TopicActionType.create);
      expect(actions[0].key, 'cooking');
      expect(actions[1].type, TopicActionType.update);
      expect(actions[1].key, 'Flutter dev');
      expect(actions[2].type, TopicActionType.merge);
      expect(actions[2].fromKey, 'React basics');
      expect(actions[2].key, 'frontend web dev');
    });

    test('parseEphemeralUpdates clamps TTL to max 14 days', () {
      final updates = [
        {
          'action': 'create',
          'key': 'debugging',
          'content': 'crash on startup',
          'ttl_days': 30
        },
      ];
      final result = MemoryService.parseEphemeralUpdates(updates, 'chat-123');
      expect(result.length, 1);
      expect(result[0].daysRemaining, lessThanOrEqualTo(14));
    });
  });
}
