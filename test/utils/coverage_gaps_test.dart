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

    test('reads an emphasised NONE whose punctuation falls outside it', () {
      // `**NONE**.` is the ordinary markdown spelling — the full stop is
      // written OUTSIDE the bold — and it is one keystroke from the
      // `**None.**` above. Stripping only the runs at a line's very edges
      // leaves `NONE**.`, with the closing markers stranded INSIDE the
      // string where an anchored verdict test cannot see past them, so the
      // gate's report of completeness became a gap again. The verdict is
      // therefore judged with every emphasis character removed.
      expect(parseCoverageGaps('**NONE**.'), isEmpty);
      expect(parseCoverageGaps('**NONE**!'), isEmpty);
      expect(parseCoverageGaps('**NONE**?'), isEmpty);
      expect(parseCoverageGaps('*NONE*.'), isEmpty);
      expect(parseCoverageGaps('__NONE__.'), isEmpty);
      expect(parseCoverageGaps('`NONE`.'), isEmpty);
      expect(parseCoverageGaps('~~NONE~~.'), isEmpty);
      expect(parseCoverageGaps('***NONE***.'), isEmpty);
      expect(parseCoverageGaps('- **NONE**.'), isEmpty);
      expect(parseCoverageGaps('1. **NONE**.'), isEmpty);
      // And a bullet swallowed by the emphasis rather than the other way
      // round, which needs the unwrap on both sides of the bullet strip.
      expect(parseCoverageGaps('**- NONE**'), isEmpty);
    });

    test('reads an emphasised NONE that is ALSO justified', () {
      // The two tolerances have to compose: a model that bolds its verdict
      // is precisely the model that also punctuates it or explains itself,
      // and each of these lines used to open a research gap named after the
      // gate agreeing the draft was finished.
      expect(parseCoverageGaps('**NONE** - the draft covers every part'),
          isEmpty);
      expect(parseCoverageGaps('**NONE** — every part is addressed'), isEmpty);
      expect(parseCoverageGaps('**NONE**, everything is covered'), isEmpty);
      expect(parseCoverageGaps('**NONE**: the draft covers it'), isEmpty);
      expect(parseCoverageGaps('**NONE**. The draft covers everything.'),
          isEmpty);
      expect(parseCoverageGaps('`NONE` - all covered'), isEmpty);
      expect(parseCoverageGaps('_NONE_ - the draft is complete'), isEmpty);
      expect(parseCoverageGaps('- **NONE** — every part is addressed'),
          isEmpty);
      expect(
        parseCoverageGaps(
            'Assessment:\n\n**NONE** - the draft answers the whole question.'),
        isEmpty,
        reason: 'and the verdict still wins from inside a multi-line reply, '
            'where the lines above it would otherwise be returned as gaps '
            'alongside the mangled verdict itself',
      );
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
      // Emphasis does not flip a guard either: the verdict test ignores
      // markup, but what it then looks for is the SEPARATOR after the word,
      // and prose does not have one.
      expect(parseCoverageGaps('**none of the sources give the 2027 winner**'),
          ['none of the sources give the 2027 winner']);
    });

    test('a gap phrased as a negative sentence is swallowed, knowingly', () {
      // The cost of accepting a justified verdict, pinned so it is a
      // decision rather than a surprise: a line that opens with "none" AND
      // a punctuation separator reads as the verdict, even when the rest of
      // it names something missing. The gate prompt asks for "the missing
      // thing, one per line, with no other commentary"
      // (chat_provider.dart:90), so a real gap arrives as "the population of
      // Delhi" rather than as a sentence about it. Narrow _noneWithReason if
      // that ever stops holding — this test is what will notice.
      expect(parseCoverageGaps('None: the population is missing'), isEmpty);
      expect(parseCoverageGaps('none, the population of Delhi is missing'),
          isEmpty);
      expect(parseCoverageGaps('none — of the sources give a date'), isEmpty);
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

    test('leaves emphasis that does not wrap the whole line alone', () {
      // Only a run that wraps the line end to end is markup ABOUT the gap;
      // anything else is markup INSIDE it. Removing the outer half of each
      // inner pair would hand the panel checklist and the gap notice
      // `who won** and **when` — markdown orphaned into nonsense, strictly
      // worse to read than the line the model actually wrote.
      expect(parseCoverageGaps('**Winner** of the 2027 election'),
          ['**Winner** of the 2027 election']);
      expect(parseCoverageGaps('- **who won** and **when**'),
          ['**who won** and **when**']);
      expect(parseCoverageGaps('_x_ and _y_'), ['_x_ and _y_']);
      expect(parseCoverageGaps('- the **2027** winner'),
          ['the **2027** winner']);
      // The bullet strip is what makes this delicate: `*` is both a bullet
      // and an emphasis marker, so it must decline a DOUBLED asterisk (that
      // is bold, not a list) while still eating a real one.
      expect(parseCoverageGaps('* which college'), ['which college']);
      expect(parseCoverageGaps('*which college'), ['which college']);
    });
  });
}
