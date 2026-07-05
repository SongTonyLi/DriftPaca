import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Constants/memory_constants.dart';

void main() {
  group('MemoryConstants', () {
    group('buildSummarizationPrompt', () {
      test('includes profile, topics, and ephemeral sections', () {
        final prompt = MemoryConstants.buildSummarizationPrompt(
          messagesText: 'USER: Hello',
          existingProfile: '{"name": "Song"}',
          existingTopics: [{'topic_key': 'physics', 'content': 'quantum stuff'}],
          existingEphemeral: [{'context_key': 'debug', 'content': 'crash fix'}],
        );
        expect(prompt, contains('profile_updates'));
        expect(prompt, contains('topic_updates'));
        expect(prompt, contains('ephemeral_updates'));
        expect(prompt, contains('confidence'));
        expect(prompt, contains('"Song"'));
        expect(prompt, contains('physics'));
        expect(prompt, contains('debug'));
      });

      test('handles null existing data', () {
        final prompt = MemoryConstants.buildSummarizationPrompt(
          messagesText: 'USER: Hi',
        );
        expect(prompt, contains('None yet'));
        expect(prompt, contains('No topics yet'));
        expect(prompt, contains('No ephemeral context yet'));
      });
    });

    test('buildForgetPrompt includes removed text and existing memory', () {
      final prompt = MemoryConstants.buildForgetPrompt(
        removedText: 'USER: my cat is named Mittens',
        existingProfile: '{"name":"Song"}',
        existingTopics: [
          {'topic_key': 'pets', 'content': 'has a cat named Mittens'}
        ],
        existingEphemeral: null,
      );

      expect(prompt, contains('Mittens'));
      expect(prompt, contains('pets'));
      expect(prompt, contains('Song'));
      // Must instruct explicit deletion marking and strict JSON.
      expect(prompt.toLowerCase(), contains('delete'));
      expect(prompt, contains('"profile"'));
      expect(prompt, contains('"topics"'));
      expect(prompt, contains('"ephemeral"'));
    });

    group('buildSelectionPrompt', () {
      test('includes recent messages and key lists', () {
        final prompt = MemoryConstants.buildSelectionPrompt(
          recentMessagesText: 'USER: How do I fix this Flutter bug?',
          conversationSummary: 'Debugging a widget layout issue',
          topicKeys: ['Flutter development', 'quantum physics'],
          ephemeralKeys: ['debugging crashloop'],
        );
        expect(prompt, contains('Flutter bug'));
        expect(prompt, contains('Flutter development'));
        expect(prompt, contains('quantum physics'));
        expect(prompt, contains('debugging crashloop'));
        expect(prompt, contains('relevant_keys'));
      });

      test('handles empty keys gracefully', () {
        final prompt = MemoryConstants.buildSelectionPrompt(
          recentMessagesText: 'USER: Hi',
          topicKeys: [],
          ephemeralKeys: [],
        );
        expect(prompt, contains('relevant_keys'));
      });
    });

    group('buildMemoryInjection', () {
      test('includes all three sections when provided', () {
        final injection = MemoryConstants.buildMemoryInjection(
          profileBlock: '- **Name**: Song',
          relevantContextBlock: '- **[physics]**: quantum stuff',
          conversationMemoryBlock: '- **Summary**: we talked about physics',
        );
        expect(injection, contains('About This User'));
        expect(injection, contains('Relevant Context'));
        expect(injection, contains('Conversation Context'));
      });

      test('omits empty sections', () {
        final injection = MemoryConstants.buildMemoryInjection(
          profileBlock: '- **Name**: Song',
          relevantContextBlock: '',
          conversationMemoryBlock: '',
        );
        expect(injection, contains('About This User'));
        expect(injection, isNot(contains('Relevant Context')));
        expect(injection, isNot(contains('Conversation Context')));
      });
    });
  });
}
