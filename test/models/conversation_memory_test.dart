import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Constants/memory_constants.dart';
import 'package:llamaseek/Models/conversation_memory.dart';

void main() {
  group('ConversationMemory.toPromptBlock injection budget', () {
    test('is capped to maxConversationMemoryTokens', () {
      // A runaway cumulative summary ~3x the injection budget.
      final huge = 'word ' * (MemoryConstants.maxConversationMemoryTokens * 3);
      final mem = ConversationMemory(summary: huge);

      final block = mem.toPromptBlock();

      expect(
        MemoryConstants.estimateTokens(block),
        lessThanOrEqualTo(MemoryConstants.maxConversationMemoryTokens),
        reason:
            'injected conversation memory must be bounded — an uncapped summary '
            'dominates the context window and crowds out real messages',
      );
    });

    // Regression guard: normal-sized memory must pass through untouched.
    test('normal-sized memory is returned intact', () {
      final mem = ConversationMemory(
        summary: 'user is building a Flutter app',
        keyContext: 'uses Provider and sqflite',
      );

      final block = mem.toPromptBlock();

      expect(block, contains('user is building a Flutter app'));
      expect(block, contains('uses Provider and sqflite'));
      expect(block, isNot(contains('memory truncated')));
    });
  });

  group('F2: summarizedMessageCount coverage marker', () {
    test('defaults to 0 and round-trips through JSON', () {
      expect(ConversationMemory(summary: 'x').summarizedMessageCount, 0);

      final m = ConversationMemory(summary: 'x', summarizedMessageCount: 12);
      final restored = ConversationMemory.fromJson(m.toJson());

      expect(restored.summarizedMessageCount, 12);
    });

    test('copyWith preserves the coverage marker unless overridden', () {
      final m = ConversationMemory(summary: 'x', summarizedMessageCount: 5);
      expect(m.copyWith(summary: 'y').summarizedMessageCount, 5);
      expect(m.copyWith(summarizedMessageCount: 9).summarizedMessageCount, 9);
    });
  });
}
