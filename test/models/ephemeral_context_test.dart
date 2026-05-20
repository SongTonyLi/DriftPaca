import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ephemeral_context.dart';

void main() {
  group('EphemeralContext', () {
    test('fromMap parses all fields', () {
      final map = {
        'id': 1,
        'context_key': 'debugging crashloop',
        'content': 'App crashes on iOS 18 when opening camera',
        'source_chat_id': 'chat-abc-123',
        'created_at': 1716100000000,
        'expires_at': 1716704800000,
      };
      final ctx = EphemeralContext.fromMap(map);
      expect(ctx.id, 1);
      expect(ctx.contextKey, 'debugging crashloop');
      expect(ctx.content, 'App crashes on iOS 18 when opening camera');
      expect(ctx.sourceChatId, 'chat-abc-123');
      expect(ctx.createdAt.millisecondsSinceEpoch, 1716100000000);
      expect(ctx.expiresAt.millisecondsSinceEpoch, 1716704800000);
    });

    test('default TTL is 7 days from creation', () {
      final ctx = EphemeralContext(
        contextKey: 'test',
        content: 'data',
      );
      final diff = ctx.expiresAt.difference(ctx.createdAt);
      expect(diff.inDays, 7);
    });

    test('custom TTL is clamped to max 14 days', () {
      final ctx = EphemeralContext.withTtlDays(
        contextKey: 'test',
        content: 'data',
        ttlDays: 30,
      );
      final diff = ctx.expiresAt.difference(ctx.createdAt);
      expect(diff.inDays, 14);
    });

    test('isExpired returns true when past expiresAt', () {
      final ctx = EphemeralContext(
        contextKey: 'old',
        content: 'stale',
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(ctx.isExpired, isTrue);
    });

    test('isExpired returns false when before expiresAt', () {
      final ctx = EphemeralContext(
        contextKey: 'fresh',
        content: 'new',
        expiresAt: DateTime.now().add(const Duration(days: 3)),
      );
      expect(ctx.isExpired, isFalse);
    });

    test('toInsertMap excludes id', () {
      final ctx = EphemeralContext(contextKey: 'k', content: 'v');
      final map = ctx.toInsertMap();
      expect(map.containsKey('id'), isFalse);
      expect(map['context_key'], 'k');
    });

    test('toPromptEntry formats with recent tag', () {
      final ctx = EphemeralContext(contextKey: 'bug fix', content: 'fixed null error');
      expect(ctx.toPromptEntry(), '- **[recent: bug fix]**: fixed null error');
    });

    test('daysRemaining returns correct value', () {
      final ctx = EphemeralContext(
        contextKey: 'test',
        content: 'data',
        expiresAt: DateTime.now().add(const Duration(days: 3, hours: 12)),
      );
      expect(ctx.daysRemaining, inInclusiveRange(3, 4));
    });
  });
}
