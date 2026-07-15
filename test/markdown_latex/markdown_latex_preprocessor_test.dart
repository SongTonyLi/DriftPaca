import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Utils/markdown_latex_preprocessor.dart';

void main() {
  group('code protection', () {
    test('preserves triple-backtick code exactly', () {
      const source = '```text\n'
          r'$[ref](https://example.com)$'
          '\n'
          r'| $|x|$ |'
          '\n```';

      expect(preprocessMarkdownLatex(source), source);
    });

    test('preserves tilde-fenced code exactly', () {
      const source = '~~~text\n'
          r'\tag{1} \(x\)'
          '\n~~~';

      expect(preprocessMarkdownLatex(source), source);
    });

    test('preserves longer and incomplete code fences', () {
      const closed = '````text\n'
          r'``` \(x\) ```'
          '\n````';
      const incomplete = '~~~text\n'
          r'\tag{1} \(x\)';

      expect(preprocessMarkdownLatex(closed), closed);
      expect(preprocessMarkdownLatex(incomplete), incomplete);
    });

    test('preserves matching-run inline code and indented code', () {
      const source = 'Use ``'
          r'\tag{1} \(x\)'
          '`` here.\n\n'
          '    '
          r'$[ref](https://example.com)$';

      expect(preprocessMarkdownLatex(source), source);
    });
  });

  group('target fences and delimiters', () {
    test('unwraps markdown fences and renders bare latex fences as display math', () {
      expect(
        preprocessMarkdownLatex(
          '```markdown\n'
          '**bold**\n'
          '```',
        ),
        '**bold**\n',
      );
      expect(
        preprocessMarkdownLatex(
          '```latex\n'
          r'\frac{a}{b}'
          '\n```',
        ),
        '\$\$\n'
        r'\frac{a}{b}'
        '\n\$\$',
      );
      expect(
        preprocessMarkdownLatex(
          '```math\n'
          r'$x^2$'
          '\n```',
        ),
        r'$x^2$' '\n',
      );
      expect(
        preprocessMarkdownLatex(
          '```math\n'
          r'\(x^2\)'
          '\n```',
        ),
        r'$x^2$' '\n',
      );
    });

    test(r'rewrites \tag only inside confirmed math', () {
      expect(
        preprocessMarkdownLatex(
          r'Write `\tag{1}` or \tag{2}; math is $x=1\tag{3}$.',
        ),
        r'Write `\tag{1}` or \tag{2}; math is $x=1\quad(3)$.',
      );
    });

    test('leaves unmatched latex delimiters literal', () {
      const source = r'Incomplete \(x and \[y.';
      expect(preprocessMarkdownLatex(source), source);
    });
  });

  group('currency and links', () {
    test('escapes one currency marker without consuming later math', () {
      expect(
        preprocessMarkdownLatex(
          r'The plan costs $5 and formula is $x^2$.',
        ),
        r'The plan costs \$5 and formula is $x^2$.',
      );
    });

    test('keeps digit-led math as math', () {
      const source = r'Equation: $1+1=2$ and $\text{cost}=5$.';
      expect(preprocessMarkdownLatex(source), source);
    });

    test('unwraps dollar-wrapped links with balanced URL parentheses', () {
      expect(
        preprocessMarkdownLatex(
          r'$[reference](https://en.wikipedia.org/wiki/Foo_(bar))$',
        ),
        r'[reference](https://en.wikipedia.org/wiki/Foo_(bar))',
      );
    });

    test('leaves incomplete wrapped links literal', () {
      const source = r'$[reference](https://example.com/path';
      expect(preprocessMarkdownLatex(source), source);
    });

    test('preserves dollars inside ordinary Markdown link destinations', () {
      const source = r'[pricing](https://example.com/$5/path) and $x^2$.';
      expect(preprocessMarkdownLatex(source), source);
    });
  });

  group('tables', () {
    test('escapes math pipes in tables without leading edge pipes', () {
      expect(
        preprocessMarkdownLatex(
          'Formula | Meaning\n'
          '--- | ---\n'
          r'$|x|$ | absolute value',
        ),
        'Formula | Meaning\n'
        '--- | ---\n'
        r'$\vert x\vert $ | absolute value',
      );
    });

    test('escapes math pipes in blockquote tables', () {
      expect(
        preprocessMarkdownLatex(
          '> | Formula |\n'
          '> | --- |\n'
          r'> | $|x|$ |',
        ),
        '> | Formula |\n'
        '> | --- |\n'
        r'> | $\vert x\vert $ |',
      );
    });
  });

  test('is idempotent', () {
    const source = '```latex\n'
        r'\frac{a}{b}'
        '\n```\n\n'
        r'The plan costs $5 and formula is $|x|$.';

    final once = preprocessMarkdownLatex(source);
    expect(preprocessMarkdownLatex(once), once);
  });
}
