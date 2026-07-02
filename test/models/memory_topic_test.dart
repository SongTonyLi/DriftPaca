import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/memory_topic.dart';

void main() {
  group('MemoryTopic', () {
    test('fromMap parses all fields', () {
      final map = {
        'id': 1,
        'topic_key': 'Flutter state management',
        'content': 'User prefers Riverpod over Provider',
        'created_at': 1716100000000,
        'updated_at': 1716100000000,
      };
      final topic = MemoryTopic.fromMap(map);
      expect(topic.id, 1);
      expect(topic.topicKey, 'Flutter state management');
      expect(topic.content, 'User prefers Riverpod over Provider');
      expect(topic.createdAt.millisecondsSinceEpoch, 1716100000000);
      expect(topic.updatedAt.millisecondsSinceEpoch, 1716100000000);
    });

    test('toMap round-trips correctly', () {
      final topic = MemoryTopic(
        id: 5,
        topicKey: 'cooking',
        content: 'likes Italian food',
      );
      final map = topic.toMap();
      final restored = MemoryTopic.fromMap(map);
      expect(restored.topicKey, 'cooking');
      expect(restored.content, 'likes Italian food');
    });

    test('toInsertMap excludes id for auto-increment', () {
      final topic = MemoryTopic(topicKey: 'test', content: 'data');
      final map = topic.toInsertMap();
      expect(map.containsKey('id'), isFalse);
      expect(map['topic_key'], 'test');
      expect(map['content'], 'data');
      expect(map.containsKey('created_at'), isTrue);
      expect(map.containsKey('updated_at'), isTrue);
    });

    test('estimatedTokens uses chars/4 heuristic', () {
      final topic = MemoryTopic(topicKey: 'x', content: 'a' * 200);
      expect(topic.estimatedTokens, 51);
    });

    test('toPromptEntry stamps the last-updated date so stale topics are discountable', () {
      final topic = MemoryTopic(
        topicKey: 'physics',
        content: 'quantum stuff',
        updatedAt: DateTime(2026, 1, 15),
      );
      // A never-expiring topic must carry provenance; the agent-memory block
      // injects "current time" so the model can judge staleness. See F3.
      expect(topic.toPromptEntry(),
          '- **[physics]** (as of 2026-01-15): quantum stuff');
    });
  });
}
