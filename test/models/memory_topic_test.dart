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

    test('toPromptEntry formats as labeled block', () {
      final topic = MemoryTopic(topicKey: 'physics', content: 'quantum stuff');
      expect(topic.toPromptEntry(), '- **[physics]**: quantum stuff');
    });
  });
}
