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
  });
}
