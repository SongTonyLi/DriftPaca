/// Guards the one property `selectSupportingExcerpt` leans on when it picks
/// which slice of a long candidate to quote.
///
/// The ledger excerpt is now the best-scoring `splitText(best, chunkSize:
/// maxLength, overlap: 0)` window of the winning candidate rather than its
/// first [maxLength] characters (research_ledger.dart), which is what stops
/// a page that won on a sentence deep in the article from being recorded as
/// its navigation sidebar. That substitution is only safe while splitText
/// respects the cap on EVERY separator path — including the `_hardSplit`
/// fallback for text with no separators at all — because the checklist line
/// it feeds is re-injected into the system prompt on every turn, and an
/// unbounded window there means an unbounded prompt.
///
/// `overlap: 0` is load-bearing: `_applyOverlap` prepends the tail of the
/// previous chunk to each subsequent one, so any positive overlap produces
/// windows LONGER than chunkSize.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Utils/text_splitter.dart';

const _maxLength = 220;

String _repeat(String seed, int times) => List.filled(times, seed).join(' ');

void main() {
  group('splitText windows for a ledger excerpt', () {
    final fixtures = <String, String>{
      'paragraph-separated prose': [
        _repeat('Paragraph one carries a few ordinary sentences.', 6),
        _repeat('Paragraph two continues in much the same register.', 6),
        _repeat('Paragraph three closes the passage out.', 6),
      ].join('\n\n'),
      'line-separated prose':
          List.filled(12, _repeat('A single line of text.', 3)).join('\n'),
      'sentence-only prose': _repeat(
          'One sentence follows another with no line breaks anywhere. ', 14),
      'space-only text': _repeat('token', 400),
      'no separators at all': 'x' * 1200,
    };

    fixtures.forEach((name, text) {
      test('never emits a window over the cap for $name', () {
        final windows = splitText(text, chunkSize: _maxLength, overlap: 0);

        expect(windows, isNotEmpty,
            reason: 'a non-empty candidate must yield somewhere to quote '
                'from; an empty list sends selectSupportingExcerpt back to '
                'its substring fallback');
        expect(windows.length, greaterThan(1),
            reason: 'the fixture is long enough to actually exercise '
                'splitting rather than returning the text whole');
        for (final w in windows) {
          expect(w.length, lessThanOrEqualTo(_maxLength),
              reason: 'a ${w.length}-char window would put more than '
                  '$_maxLength characters of scraped page text onto one '
                  'checklist line, and that line is rendered into the '
                  'system prompt every turn');
        }
      });

      test('every window is a verbatim slice of the source for $name', () {
        for (final w in splitText(text, chunkSize: _maxLength, overlap: 0)) {
          expect(text, contains(w),
              reason: 'the excerpt has to be quotable as-is — splitText must '
                  'not rewrite the text it is dividing');
        }
      });
    });

    test('a candidate at or under the cap comes back whole', () {
      const short = 'Vietnam GDP grew 7.1% in 2024, led by exports.';
      expect(splitText(short, chunkSize: _maxLength, overlap: 0), [short],
          reason: 'selectSupportingExcerpt short-circuits before this, but '
              'the boundary must not fragment a quotable sentence');
    });
  });
}
