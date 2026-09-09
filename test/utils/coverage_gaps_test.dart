import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Utils/coverage_gaps.dart';

void main() {
  group('parseCoverageGaps', () {
    test('reads NONE as a complete answer, however the model cases it', () {
      expect(parseCoverageGaps('NONE'), isEmpty);
      expect(parseCoverageGaps('none'), isEmpty);
      expect(parseCoverageGaps('  None.  '), isEmpty);
      expect(parseCoverageGaps(''), isEmpty);
      expect(parseCoverageGaps('   \n  \n'), isEmpty);
    });

    test('strips bullet and number prefixes from listed gaps', () {
      expect(
        parseCoverageGaps('- which college the MVP attended\n'
            '- what the final series score was'),
        ['which college the MVP attended', 'what the final series score was'],
      );
      expect(
        parseCoverageGaps('1. which college\n2) what year'),
        ['which college', 'what year'],
      );
      expect(parseCoverageGaps('* which college'), ['which college']);
    });

    test('caps the number of gaps', () {
      // Over-decomposition is the regression risk this whole feature runs:
      // a gate that returns six "gaps" for a simple question manufactures
      // the 8-round over-searching that 8e0b64b fixed.
      final many = List.generate(9, (i) => '- gap number $i').join('\n');
      expect(parseCoverageGaps(many), hasLength(maxCoverageGaps));
    });

    test('drops a NONE line mixed in with prose', () {
      expect(parseCoverageGaps('NONE\n\nThe answer covers everything.'),
          isEmpty);
    });

    test('ignores a blank-ish line but keeps real content', () {
      expect(
        parseCoverageGaps('\n- which college\n\n-\n- what year\n'),
        ['which college', 'what year'],
      );
    });

    test('reads a NONE wrapped in markdown emphasis', () {
      // `*` is both a bullet character and an emphasis marker, and the
      // bullet strip can only eat one of them: `**NONE**` used to arrive at
      // the verdict test as `*NONE**` and be opened as a research gap named
      // after the gate's own report that the draft was complete.
      expect(parseCoverageGaps('**NONE**'), isEmpty);
      expect(parseCoverageGaps('***NONE***'), isEmpty);
      expect(parseCoverageGaps('__NONE__'), isEmpty);
      expect(parseCoverageGaps('`NONE`'), isEmpty);
      expect(parseCoverageGaps('**None.**'), isEmpty);
      // Emphasis on either side of a bullet, which is why the strip runs
      // both before and after the bullet strip.
      expect(parseCoverageGaps('* **NONE**'), isEmpty);
      expect(parseCoverageGaps('- **NONE**'), isEmpty);
    });

    test('reads a NONE the model justified on the same line', () {
      // The prompt asks for exactly "NONE", but a model that has just
      // reasoned about completeness frequently says why. That is still a
      // verdict, not a missing part of the question.
      expect(parseCoverageGaps('NONE - the draft covers every part'), isEmpty);
      expect(parseCoverageGaps('NONE — every part is addressed'), isEmpty);
      expect(parseCoverageGaps('NONE—complete'), isEmpty);
      expect(parseCoverageGaps('NONE: the draft covers it'), isEmpty);
      expect(parseCoverageGaps('NONE, everything is covered'), isEmpty);
      expect(parseCoverageGaps('NONE. The draft covers everything.'), isEmpty);
    });

    test('a NONE anywhere in the reply wins, past the cap', () {
      const reasonedThenComplete = 'The question asks for the height.\n'
          'The draft gives it with a citation.\n'
          'It also names who measured it.\n'
          'And when.\n'
          'So nothing is left over.\n'
          'NONE';
      expect(parseCoverageGaps(reasonedThenComplete), isEmpty,
          reason: 'maxCoverageGaps bounds the returned list, not how far the '
              'reply is scanned — otherwise five lines of the model '
              'agreeing the draft is complete become gaps');

      // The cap itself is untouched: the same five lines with no verdict
      // still yield exactly maxCoverageGaps.
      expect(
        parseCoverageGaps('The question asks for the height.\n'
            'The draft gives it with a citation.\n'
            'It also names who measured it.\n'
            'And when.\n'
            'So nothing is left over.'),
        hasLength(maxCoverageGaps),
      );
    });

    test('a gap that merely starts with "none" is still a gap', () {
      // The guard against over-widening the verdict test. A false
      // "complete" costs the user the research the gate exists to trigger,
      // which is strictly worse than the wasted round a false gap costs —
      // so the verdict needs a punctuation separator after the word, and a
      // plain hyphen needs whitespace on one side of it.
      expect(parseCoverageGaps('none of the sources give the 2027 winner'),
          ['none of the sources give the 2027 winner']);
      expect(parseCoverageGaps('None of the pages state the population'),
          ['None of the pages state the population']);
      expect(parseCoverageGaps('nonetheless the college is missing'),
          ['nonetheless the college is missing']);
      expect(parseCoverageGaps('none-the-less something is missing'),
          ['none-the-less something is missing']);
    });

    test('strips wrapping emphasis from gap text', () {
      // The gap string is shown to the user as a checklist item in the
      // research panel and restated to the model as a part of the question
      // it missed, so it must be the gap, not the gap's markup.
      expect(parseCoverageGaps('- **the 2027 winner**'), ['the 2027 winner']);
      expect(parseCoverageGaps('`what the final score was`'),
          ['what the final score was']);
      // A line that is only decoration cleans to empty and is skipped, just
      // like the bare `-` above.
      expect(parseCoverageGaps('**\n_\n- which college\n~~'),
          ['which college']);
    });
  });
}
