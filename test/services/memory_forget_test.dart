import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Services/memory_service.dart';

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
  });
}
