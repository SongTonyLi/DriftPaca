import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Widgets/model_selection_bottom_sheet.dart';

void main() {
  group('fuzzySubstringDistance', () {
    test('exact substring returns 0', () {
      expect(fuzzySubstringDistance('qwen', 'qwen2.5:latest'), 0);
      expect(fuzzySubstringDistance('llama', 'llama3:latest'), 0);
      expect(fuzzySubstringDistance('gem', 'gemma2:latest'), 0);
    });

    test('transposition returns 1', () {
      // "wqen" is "qwen" with w,q swapped
      expect(fuzzySubstringDistance('wqen', 'qwen2.5:latest'), 1);
    });

    test('single character deletion returns 1', () {
      // "qwn" is "qwen" with 'e' missing
      expect(fuzzySubstringDistance('qwn', 'qwen2.5:latest'), 1);
    });

    test('single character insertion returns 1', () {
      // "qween" is "qwen" with extra 'e'
      expect(fuzzySubstringDistance('qween', 'qwen2.5:latest'), 1);
    });

    test('single substitution returns 1', () {
      // "qwan" is "qwen" with 'e' -> 'a'
      expect(fuzzySubstringDistance('qwan', 'qwen2.5:latest'), 1);
    });

    test('unrelated query has high distance', () {
      expect(fuzzySubstringDistance('xyz', 'qwen2.5:latest'), greaterThan(2));
      expect(fuzzySubstringDistance('abcdef', 'llama3:latest'), greaterThan(2));
    });

    test('empty query returns 0', () {
      expect(fuzzySubstringDistance('', 'qwen'), 0);
    });

    test('empty target returns query length', () {
      expect(fuzzySubstringDistance('abc', ''), 3);
    });

    test('matches anywhere in target', () {
      // "latest" at the end
      expect(fuzzySubstringDistance('latest', 'qwen2.5:latest'), 0);
      // "laetst" is "latest" with transposition
      expect(fuzzySubstringDistance('laetst', 'qwen2.5:latest'), 1);
    });

    test('case sensitive (caller lowercases)', () {
      // The function itself is case-sensitive; callers normalize
      expect(fuzzySubstringDistance('QWEN', 'qwen'), 4);
      expect(fuzzySubstringDistance('qwen', 'qwen'), 0);
    });
  });
}
