import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/agent_memory.dart';
import 'package:llamaseek/Models/conversation_memory.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Utils/goal_derivation_context.dart';

void main() {
  OllamaMessage user(String text) => OllamaMessage(text, role: OllamaMessageRole.user);
  OllamaMessage assistant(String text) =>
      OllamaMessage(text, role: OllamaMessageRole.assistant);

  group('goalContextMessages', () {
    test('is the turns before the message being briefed', () {
      final history = [
        user('Tell me about Mercury, the planet'),
        assistant('Mercury is the innermost planet.'),
        user('and its moons?'),
      ];
      expect(goalContextMessages(history).map((m) => m.content),
          ['Tell me about Mercury, the planet', 'Mercury is the innermost planet.']);
    });

    test('is empty for a first message', () {
      expect(goalContextMessages([user('Tell me about Mercury')]), isEmpty);
      expect(goalContextMessages(const []), isEmpty);
    });

    test('drops tool and system turns and empty ones', () {
      final history = [
        OllamaMessage('be brief', role: OllamaMessageRole.system),
        user('Tell me about Mercury'),
        OllamaMessage('{"results": []}', role: OllamaMessageRole.tool, toolName: 'web_search'),
        assistant('   '),
        assistant('Mercury is the innermost planet.'),
        user('and its moons?'),
      ];
      expect(goalContextMessages(history).map((m) => m.content),
          ['Tell me about Mercury', 'Mercury is the innermost planet.']);
    });

    test('keeps the most recent turns when there are more than the window holds', () {
      final history = [
        for (var i = 0; i < 20; i++) i.isEven ? user('u$i') : assistant('a$i'),
        user('final'),
      ];
      final kept = goalContextMessages(history).map((m) => m.content).toList();
      expect(kept.length, maxGoalContextMessages);
      expect(kept.first, 'u${20 - maxGoalContextMessages}');
      expect(kept.last, 'a19');
    });

    test('starts after the turns a conversation summary already covers', () {
      final history = [
        user('u0'),
        assistant('a1'),
        user('u2'),
        assistant('a3'),
        user('final'),
      ];
      final memory = ConversationMemory(summary: 'They discussed u0.', summarizedMessageCount: 2);
      expect(goalContextMessages(history, conversationMemory: memory).map((m) => m.content),
          ['u2', 'a3']);
    });

    test('ignores a summary that claims to cover everything, so the window is never empty by mistake', () {
      final history = [user('u0'), assistant('a1'), user('final')];
      final memory = ConversationMemory(summary: 'Everything.', summarizedMessageCount: 5);
      expect(goalContextMessages(history, conversationMemory: memory).map((m) => m.content),
          ['u0', 'a1']);
    });
  });

  group('renderGoalDerivationContext', () {
    test('is empty when there is nothing to show', () {
      expect(renderGoalDerivationContext(history: [user('Mercury?')]), isEmpty);
      expect(goalDerivationMessage('Mercury?', ''), 'Mercury?',
          reason: 'a first message goes bare, as it always did');
    });

    test('lays out summary, then turns, then what is remembered, and the message last', () {
      final history = [
        user('u0'),
        assistant('a1'),
        user('Tell me about Mercury, the planet'),
        assistant('Mercury is the innermost planet.'),
        user('and its moons?'),
      ];
      final context = renderGoalDerivationContext(
        history: history,
        conversationMemory: ConversationMemory(
            summary: 'Opened with small talk.', summarizedMessageCount: 2),
        profile: AgentMemory(name: 'Sam', roleAndBackground: 'amateur astronomer'),
        relevantContext: '- telescope: owns an 8-inch Dobsonian',
      );
      final message = goalDerivationMessage('and its moons?', context);

      int at(String needle) {
        final i = message.indexOf(needle);
        expect(i, greaterThanOrEqualTo(0), reason: 'missing: $needle');
        return i;
      }

      expect(at('Summary of the conversation before that:'), lessThan(at('Opened with small talk.')));
      expect(at('Opened with small talk.'), lessThan(at('Earlier turns of this conversation:')));
      expect(at('User: Tell me about Mercury, the planet'),
          lessThan(at('Assistant: Mercury is the innermost planet.')));
      expect(at('Assistant: Mercury'), lessThan(at('What is remembered about the user:')));
      expect(at('Sam'), lessThan(at('8-inch Dobsonian')));
      expect(at('8-inch Dobsonian'), lessThan(at('The message to turn into a brief')));
      expect(message, endsWith('\nand its moons?'));
      expect(message, isNot(contains('User: u0')), reason: 'the summary stands in for u0/a1');
    });

    test('leaves the summary out when it covers nothing the turns omit', () {
      final history = [user('u0'), assistant('a1'), user('final')];
      final context = renderGoalDerivationContext(
        history: history,
        conversationMemory: ConversationMemory(summary: 'Nothing yet.'),
      );
      expect(context, isNot(contains('Nothing yet.')));
      expect(context, contains('User: u0'));
    });

    test('flattens and clips a long turn', () {
      final long = List.filled(400, 'word').join(' ');
      final history = [
        user('first'),
        assistant('line one\n\n  line two\n$long'),
        user('final'),
      ];
      final context = renderGoalDerivationContext(history: history);
      final line = context.split('\n').firstWhere((l) => l.startsWith('Assistant:'));
      expect(line, startsWith('Assistant: line one line two word'));
      expect(line, endsWith('…'));
      expect(line.length, lessThanOrEqualTo('Assistant: '.length + maxGoalContextCharsPerMessage + 1));
    });

    test('remembered notes alone still make a context', () {
      final context = renderGoalDerivationContext(
        history: [user('what is the weather like?')],
        relevantContext: '- home: Toronto',
      );
      expect(context, startsWith('What is remembered about the user:'));
      expect(context, contains('Toronto'));
      expect(goalDerivationMessage('what is the weather like?', context),
          endsWith('\nwhat is the weather like?'));
    });
  });
}
