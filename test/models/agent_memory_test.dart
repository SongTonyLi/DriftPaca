import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/agent_memory.dart';

void main() {
  group('StableProfile', () {
    test('fromMap parses all fields', () {
      final map = {
        'name': 'Song',
        'primary_language': 'English / Chinese',
        'tone_and_formality': 'concise, casual',
        'role_and_background': 'Flutter developer',
        'communication_style': 'direct, no fluff',
        'updated_at': 1716100000000,
      };
      final profile = AgentMemory.fromMap(map);
      expect(profile.name, 'Song');
      expect(profile.primaryLanguage, 'English / Chinese');
      expect(profile.toneAndFormality, 'concise, casual');
      expect(profile.roleAndBackground, 'Flutter developer');
      expect(profile.communicationStyle, 'direct, no fluff');
      expect(profile.updatedAt.millisecondsSinceEpoch, 1716100000000);
    });

    test('toMap round-trips correctly', () {
      final profile = AgentMemory(
        name: 'Song',
        primaryLanguage: 'Chinese',
        toneAndFormality: 'casual',
        roleAndBackground: 'developer',
        communicationStyle: 'concise',
      );
      final map = profile.toMap();
      final restored = AgentMemory.fromMap(map);
      expect(restored.name, profile.name);
      expect(restored.primaryLanguage, profile.primaryLanguage);
      expect(restored.toneAndFormality, profile.toneAndFormality);
      expect(restored.roleAndBackground, profile.roleAndBackground);
      expect(restored.communicationStyle, profile.communicationStyle);
    });

    test('isEmpty returns true when all fields empty', () {
      expect(AgentMemory().isEmpty, isTrue);
    });

    test('isEmpty returns false when any field set', () {
      expect(AgentMemory(name: 'Song').isEmpty, isFalse);
    });

    test('toPromptBlock includes system info and non-empty fields', () {
      final profile = AgentMemory(
        name: 'Song',
        primaryLanguage: 'Chinese',
      );
      final block = profile.toPromptBlock();
      expect(block, contains('System Info'));
      expect(block, contains('Current time:'));
      expect(block, contains('Song'));
      expect(block, contains('Chinese'));
      expect(block, isNot(contains('Tone')));
      expect(block, isNot(contains('Role')));
    });

    test('estimatedTokens uses chars/4 heuristic', () {
      final profile = AgentMemory(name: 'a' * 100);
      expect(profile.estimatedTokens, 25);
    });

    test('copyWith replaces specified fields only', () {
      final original = AgentMemory(name: 'Song', primaryLanguage: 'Chinese');
      final updated = original.copyWith(name: 'Li');
      expect(updated.name, 'Li');
      expect(updated.primaryLanguage, 'Chinese');
    });

    test('fromMap handles null and list values', () {
      final map = {
        'name': null,
        'primary_language': ['English', 'Chinese'],
        'tone_and_formality': '',
      };
      final profile = AgentMemory.fromMap(map);
      expect(profile.name, '');
      expect(profile.primaryLanguage, 'English\nChinese');
      expect(profile.toneAndFormality, '');
    });
  });
}
