import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/conversation_memory.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Services/ollama_service.dart';

void main() {
  List<OllamaMessage> conversation(int n) => List.generate(
        n,
        (i) => OllamaMessage('m$i',
            role:
                i.isEven ? OllamaMessageRole.user : OllamaMessageRole.assistant),
      );

  group('F2: coverage-based history window', () {
    test(
        'sends raw from the summary boundary, never dropping unsummarized messages',
        () async {
      final service = OllamaService();
      final messages = conversation(40);
      final mem = ConversationMemory(
          summary: 'prior summary', summarizedMessageCount: 15);

      final prepared = await service.prepareMessagesWithSystemPrompt(
        messages,
        'SYS',
        conversationMemory: mem,
        currentModel: 'test-model',
      );

      final nonSystem = prepared.where((m) => m['role'] != 'system').toList();
      // Boundary is 15 → raw window must be messages[15..40) = 25 messages.
      // The OLD fixed-20 window sent messages[20..40) and silently DROPPED
      // m15..m19 — the gap the summary had not yet caught up on.
      expect(nonSystem.length, 25,
          reason:
              'raw window must start at the summary boundary, not a fixed 20');
      expect(nonSystem.first['content'], 'm15');
    });

    test('no coverage marker (legacy/short) sends the full history', () async {
      final service = OllamaService();
      final messages = conversation(30);
      final mem = ConversationMemory(summary: 'prior', summarizedMessageCount: 0);

      final prepared = await service.prepareMessagesWithSystemPrompt(
        messages,
        'SYS',
        conversationMemory: mem,
        currentModel: 'test-model',
      );

      final nonSystem = prepared.where((m) => m['role'] != 'system').toList();
      expect(nonSystem.length, 30);
      expect(nonSystem.first['content'], 'm0');
    });
  });

  group('F4: prior thinking + search-data blob are not re-sent', () {
    test('no history message carries a thinking field, but content is kept',
        () async {
      final service = OllamaService();
      final user = OllamaMessage('what is the answer?',
          role: OllamaMessageRole.user);
      final assistant = OllamaMessage(
        'The answer is 42.',
        role: OllamaMessageRole.assistant,
        thinking: '<!--SEARCH_DATA:eyJ4IjoxfQ==-->\nlet me reason about thisâ€¦',
      );

      final prepared =
          await service.prepareMessagesWithSystemPrompt([user, assistant], null);

      for (final m in prepared) {
        expect(m.containsKey('thinking'), isFalse,
            reason:
                'prior reasoning and the persisted search-data blob must not be '
                're-sent to the model');
      }
      expect(prepared.any((m) => m['content'] == 'The answer is 42.'), isTrue,
          reason: 'the visible answer must still be sent');
    });
  });

  group('tool transcript extraMessages', () {
    test('extraMessages survive even when summarizedMessageCount == history.length', () async {
      final service = OllamaService();
      final history = [
        OllamaMessage('latest user turn', role: OllamaMessageRole.user),
        OllamaMessage(
          'prior answer',
          role: OllamaMessageRole.assistant,
          thinking: 'history thinking must be stripped',
        ),
      ];
      final extra = [
        OllamaMessage(
          '',
          role: OllamaMessageRole.assistant,
          thinking: 'keep tool-call thinking',
          toolCalls: [
            const OllamaToolCall(
              name: 'web_search',
              arguments: {'query': 'gdp'},
            ),
          ],
        ),
        OllamaMessage(
          'tool result body',
          role: OllamaMessageRole.tool,
          toolName: 'web_search',
        ),
      ];
      final mem = ConversationMemory(
        summary: 'covers everything',
        summarizedMessageCount: history.length,
      );

      final prepared = await service.prepareMessagesWithSystemPrompt(
        history,
        'SYS',
        conversationMemory: mem,
        extraMessages: extra,
      );

      expect(
        prepared.any((m) => m['content'] == 'latest user turn'),
        isTrue,
        reason: 'fully-summarized history must not drop the latest user turn',
      );
      expect(
        prepared.any((m) => m['content'] == 'tool result body'),
        isTrue,
        reason: 'extraMessages must be appended after the coverage window',
      );
      expect(prepared.any((m) => m['role'] == 'tool'), isTrue);
    });

    test('extraMessages with toolCalls keep thinking; history thinking is stripped', () async {
      final service = OllamaService();
      final history = [
        OllamaMessage('q', role: OllamaMessageRole.user),
        OllamaMessage(
          'visible answer',
          role: OllamaMessageRole.assistant,
          thinking: 'do not resend',
        ),
      ];
      final extra = [
        OllamaMessage(
          '',
          role: OllamaMessageRole.assistant,
          thinking: 'replay thinking',
          toolCalls: [
            const OllamaToolCall(
              name: 'web_search',
              arguments: {'query': 'q'},
            ),
          ],
        ),
      ];

      final prepared = await service.prepareMessagesWithSystemPrompt(
        history,
        null,
        extraMessages: extra,
      );

      final historyAssistant = prepared.firstWhere((m) => m['content'] == 'visible answer');
      expect(historyAssistant.containsKey('thinking'), isFalse);

      final replay = prepared.firstWhere((m) => m['tool_calls'] != null);
      expect(replay['thinking'], 'replay thinking');
    });
  });
}
