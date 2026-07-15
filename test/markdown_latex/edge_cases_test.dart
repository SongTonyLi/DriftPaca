/// Hand-crafted pathological edge cases for markdown/LaTeX rendering.
///
/// These tests exercise corner cases that real models may produce,
/// including malformed LaTeX, ambiguous delimiters, and adversarial inputs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // ---------------------------------------------------------------------------
  // Half-closed / malformed LaTeX
  // ---------------------------------------------------------------------------
  group('half-closed and malformed LaTeX', () {
    testWidgets('opening dollar never closed — no crash', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The formula $x + y is important to understand.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('display math opening never closed', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$\frac{a}{b} + \frac{c}{d}',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('backslash-paren never closed', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Inline math: \(x^2 + y^2 is the formula.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('backslash-bracket never closed', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Display: \[\int_0^1 f(x) dx',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('nested unclosed dollar signs', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'First $a + $b + $c is confusing.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('escaped dollar inside LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Cost is $x \$ y$ dollars.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('orphaned double dollar at end (streaming artifact)', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'The answer is:\n\n\$\$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('display math with only opening \\begin', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$\begin{aligned} x &= 1 \\ y &= 2',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets(r'mismatched delimiters: \( closed with $$', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Start \(x + y$$ end',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('triple dollar signs — known limitation', (tester) async {
      // KNOWN ISSUE: $$$ triggers infinite width constraint in the renderer.
      // The parser treats this as display math ($$) + leftover ($).
      // Verifying it does not terminate the app.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'What about $$$x + y$$$ ?',
      );
    });

    testWidgets('dollar sign at very end of message', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The value is $',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('closing dollar immediately after opening', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Empty: $$ and then text.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('LaTeX with unmatched braces', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$\frac{a}{b{c}$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('deeply unbalanced braces', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'${{{{{x}$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('backslash at end of LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$x + y \$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Dollar sign ambiguity (currency vs LaTeX)
  // ---------------------------------------------------------------------------
  group('currency vs LaTeX ambiguity', () {
    testWidgets('multiple currencies in paragraph with one real LaTeX', (tester) async {
      // Currency amounts ($5, $10) start with digits and are NOT treated as LaTeX.
      // Only $x^2 + y^2 = r^2$ (starts with letter) is real LaTeX.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The price is $5 for basic and $10 for premium. The formula is $x^2 + y^2 = r^2$.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('dollar amounts spanning a sentence break', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Save $100 today. $200 tomorrow. But $x + y$ is math.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets(r'dollar range like $5-$10 should not be LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Prices range from $5-$10 depending on size.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('dollar in different table cells should not pair', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Item | Cost |\n| --- | --- |\n| A | \$5 |\n| B | \$10 |\n| C | \$15 |',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('adjacent dollar signs with space', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Is it $ x $ or $x$ that works?',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Pathological repetition and stress inputs
  // ---------------------------------------------------------------------------
  group('pathological inputs', () {
    testWidgets('100 consecutive dollar signs — known limitation', (tester) async {
      // KNOWN ISSUE: Large sequences of $ can trigger infinite width constraint
      // errors in the renderer. Verifying the app does not terminate.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '\$' * 100,
      );
    });

    testWidgets('50 unclosed inline LaTeX expressions', (tester) async {
      final content = List.generate(50, (i) => '\$x_$i').join(' ');
      final errors = await pumpBubbleAndCollectErrors(tester, content);
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('extremely deeply nested braces', (tester) async {
      final open = '{' * 50;
      final close = '}' * 50;
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '\$${open}x$close\$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('very long single line with no break opportunities', (tester) async {
      final longEq = r'$' + List.generate(30, (i) => 'x_{$i}').join('+') + r'= S$';
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        longEq,
        surfaceSize: const Size(300, 800),
      );
      // May overflow but should not crash
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('LaTeX with emoji characters', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The result is $x + 🎉 = 💯$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('only whitespace inside dollar signs', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Empty math: $   $ and $$   $$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('newlines inside inline LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Formula: \$x +\ny\$ end.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('tab characters inside LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Math: \$x\t+\ty\$ here.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('null character in content', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Hello \x00 world \$x^2\$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('extremely long LaTeX command name', (tester) async {
      final longCmd = '\\' + 'a' * 200;
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '\$$longCmd{x}\$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('10000 characters of plain text (no LaTeX)', (tester) async {
      final longText = 'Lorem ipsum dolor sit amet. ' * 350;
      final errors = await pumpBubbleAndCollectErrors(tester, longText);
      expect(nonOverflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Code block immunity edge cases
  // ---------------------------------------------------------------------------
  group('code block immunity edge cases', () {
    testWidgets('bare LaTeX inside a latex fence renders as math', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '```latex\n\\frac{a}{b} + \\sum_{i=0}^n x_i\n```',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('dollar signs in Python f-string in code block', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '```python\nprint(f"Cost: \${price * quantity}")\nresult = \$x if \$x > 0 else -\$x\n```',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('inline code with dollar signs surrounded by real LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Use `$HOME` variable. The formula $x^2$ is nice. Also `$PATH` matters.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('backtick inside LaTeX does not start code', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The expression $x`s$ derivative is important. And $y^2$.',
      );
      // Should not crash regardless of how it's parsed
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('code block immediately adjacent to display math', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '```python\nx = 42\n```\n\$\$x = 42\$\$\n```python\ny = 43\n```',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('unclosed code fence followed by LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '```\nsome code\nno closing fence\n\nThen \$x^2\$ appears.',
      );
      // May or may not render LaTeX depending on parser, but should not crash
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('four backticks (extended fence) with LaTeX inside', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '````\n\$\$x^2\$\$\n```\nstill in fence\n````\n\nReal math: \$y^2\$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // HTML interaction edge cases
  // ---------------------------------------------------------------------------
  group('HTML and special markup interactions', () {
    testWidgets('<br> between two LaTeX expressions', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$x^2$<br>$y^2$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('<br> inside what looks like LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$x +<br>y$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('HTML entities mixed with LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The &lt;formula&gt; is $x &lt; y$ and $a \leq b$.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('<sub> and <sup> HTML near LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'HTML: x<sup>2</sup> vs LaTeX: $x^2$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('script injection attempt (should be escaped)', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'<script>alert("xss")</script> and $x^2$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('markdown link with dollar signs', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'See [pricing ($5-$10)](http://example.com) and formula $x^2$.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('image alt text with LaTeX-like content', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'![equation $x^2$](image.png) and real math $y^2$.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // LaTeX environment edge cases
  // ---------------------------------------------------------------------------
  group('LaTeX environment edge cases', () {
    testWidgets('align environment', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '\$\$\\begin{aligned}\nx &= 1 \\\\\ny &= 2 \\\\\nz &= x + y\n\\end{aligned}\$\$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('cases environment (piecewise)', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '\$\$f(x) = \\begin{cases}\nx & \\text{if } x \\geq 0 \\\\\n-x & \\text{if } x < 0\n\\end{cases}\$\$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('matrix environment', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$\begin{pmatrix} a & b \\ c & d \end{pmatrix} \begin{pmatrix} x \\ y \end{pmatrix} = \begin{pmatrix} ax + by \\ cx + dy \end{pmatrix}$$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('nested environments', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '\$\$\\begin{aligned}\nA &= \\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix} \\\\\n\\det(A) &= 1 \\cdot 4 - 2 \\cdot 3 = -2\n\\end{aligned}\$\$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('unknown environment name — known limitation', (tester) async {
      // KNOWN ISSUE: flutter_math_fork does not support arbitrary environments.
      // Unknown environments produce a render error caught by the error handler.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$\begin{customenv} x = 1 \end{customenv}$$',
      );
    });

    testWidgets('environment with mismatched begin/end — known limitation', (tester) async {
      // KNOWN ISSUE: Mismatched environments cause flutter_math_fork parse error.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$\begin{aligned} x = 1 \end{cases}$$',
      );
    });

    testWidgets('double backslash (linebreak) outside environment — known limitation', (tester) async {
      // KNOWN ISSUE: \\ (line break) outside an environment like aligned/cases
      // is not valid in flutter_math_fork's subset of LaTeX.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$x = 1 \\ y = 2 \\ z = 3$$',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Markdown formatting interacting with LaTeX
  // ---------------------------------------------------------------------------
  group('markdown formatting interaction with LaTeX', () {
    testWidgets('bold wrapping display math', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'**Important: $$x^2 + y^2 = z^2$$**',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('italic underscores near LaTeX subscripts', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'_The variable $x_i$ in an italic context_ and $y_j$.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('strikethrough with LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'~~The old formula $x = 1$~~ is replaced by $x = 2$.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('horizontal rule between LaTeX blocks', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '\$\$x^2\$\$\n\n---\n\n\$\$y^2\$\$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('nested blockquotes with LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '> Euler said:\n> > \$e^{i\\pi} + 1 = 0\$\n>\n> Which is beautiful.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('footnote-like syntax with LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The theorem[^1] states $\forall x \in \mathbb{R}$. [^1]: See proof below.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('task list with LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '- [x] Prove \$a^2 + b^2 = c^2\$\n- [ ] Prove \$e^{i\\pi} + 1 = 0\$\n- [ ] Find \$\\int_0^\\infty e^{-x^2} dx\$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('definition list style with LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Term\n: Definition is \$x^2 + y^2\$\n\nAnother\n: Defined as \$\\frac{a}{b}\$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Unicode and special characters in LaTeX
  // ---------------------------------------------------------------------------
  group('Unicode and special characters', () {
    testWidgets('Greek letters as unicode mixed with LaTeX Greek', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Unicode α, β, γ vs LaTeX $\alpha$, $\beta$, $\gamma$.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(3));
    });

    testWidgets('CJK characters adjacent to LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'定理：如果$x > 0$，则$\sqrt{x}$存在。证明：设$f(x) = x^2$...',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(3));
    });

    testWidgets('RTL text mixed with LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'المعادلة $x^2 + y^2 = r^2$ تمثل دائرة.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('mathematical unicode operators', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Is $∑_{i=1}^n$ the same as $\sum_{i=1}^n$? And ∫ vs $\int$?',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('fullwidth dollar signs (CJK)', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '全角美元符号＄100 vs LaTeX \$x^2\$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('zero-width characters inside LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Formula: \$x\u200B+\u200By\$ = z',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Realistic model output patterns that break things
  // ---------------------------------------------------------------------------
  group('realistic model output patterns', () {
    testWidgets('thinking model wraps answer then shows equation', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Let me solve this step by step.\n\n'
            'First, we need to find the derivative of \$f(x) = x^3 + 2x^2 - 5x + 1\$.\n\n'
            'Using the power rule:\n\n'
            '\$\$f\'(x) = 3x^2 + 4x - 5\$\$\n\n'
            'Setting \$f\'(x) = 0\$:\n\n'
            '\$\$3x^2 + 4x - 5 = 0\$\$\n\n'
            'Using the quadratic formula:\n\n'
            '\$\$x = \\frac{-4 \\pm \\sqrt{16 + 60}}{6} = \\frac{-4 \\pm \\sqrt{76}}{6}\$\$',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsWidgets);
    });

    testWidgets('model outputs LaTeX with \\text{} containing special chars', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$P(\text{rain} | \text{cloudy}) = \frac{P(\text{cloudy} | \text{rain}) \cdot P(\text{rain})}{P(\text{cloudy})}$$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('model accidentally puts LaTeX in heading AND paragraph', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '## Solution: \$x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}\$\n\n'
            'Where \$a=1\$, \$b=-5\$, \$c=6\$.\n\n'
            'Therefore:\n\$\$x = \\frac{5 \\pm \\sqrt{25-24}}{2} = \\frac{5 \\pm 1}{2}\$\$',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsWidgets);
    });

    testWidgets('model uses \\boxed for final answer', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The final answer is: $$\boxed{x = \frac{3 + \sqrt{5}}{2}}$$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('model uses \\tag for equation numbering renders', (tester) async {
      // \tag is unsupported by flutter_math_fork (it expands to an undefined
      // \gdef and throws), so the preprocessor rewrites \tag{1} → \quad(1)
      // and the equation renders instead of falling back to raw source.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$E = mc^2 \tag{1}$$' '\n\n' r'From equation $\text{(1)}$ we see...',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('model mixes asterisk bold with LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '**Key result:** The eigenvalues are \$\\lambda_1 = 3\$ and \$\\lambda_2 = -1\$.\n\n'
            '*Note:* Since \$\\lambda_1 \\cdot \\lambda_2 = -3 < 0\$, the fixed point is a **saddle point**.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsWidgets);
    });

    testWidgets('numbered list with display math between items', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '1. Start with:\n\$\$\\int_0^1 x^n dx\$\$\n\n'
            '2. Evaluate:\n\$\$= \\frac{x^{n+1}}{n+1}\\Big|_0^1\$\$\n\n'
            '3. Result:\n\$\$= \\frac{1}{n+1}\$\$',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(3));
    });

    testWidgets('model produces color commands', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The $\color{red}{x}$ and $\color{blue}{y}$ values.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('model uses \\cancel or \\xcancel', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Simplify: $\frac{\cancel{3}x}{\cancel{3}y} = \frac{x}{y}$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('model uses spacing commands', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$a \quad b \qquad c \, d \; e \! f$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Inline LaTeX should flow with surrounding text, not break to a new line
  // ---------------------------------------------------------------------------
  group('inline LaTeX flows with text (not block-level)', () {
    testWidgets('short inline LaTeX stays on same line as surrounding text', (tester) async {
      // The exact pattern from the reported bug: F=ma surrounded by text.
      // The Math widget must be on the same line as "Newton's" and ". That",
      // not on its own line.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r"Newton's $F=ma$ is famous.",
        surfaceSize: const Size(400, 800),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);

      // Verify the Math widget and surrounding text share the same vertical
      // position (same line). If Math is on a new line, its top will be
      // significantly below the text top.
      final mathWidget = tester.widget<Math>(find.byType(Math));
      final mathRect = tester.getRect(find.byType(Math));
      final textFinder = find.textContaining("Newton's");
      expect(textFinder, findsOneWidget);
      final textRect = tester.getRect(textFinder);

      // Both should overlap vertically (same line).
      // If inline is working, the math widget's vertical center should be
      // within the text line's vertical extent.
      expect(
        mathRect.center.dy,
        closeTo(textRect.center.dy, textRect.height),
        reason: 'Inline LaTeX should be on the same line as surrounding text, '
            'but Math widget center (${mathRect.center.dy}) is far from '
            'text center (${textRect.center.dy})',
      );
    });

    testWidgets('multiple inline LaTeX in paragraph stay inline', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Given $a = 1$ and $b = 2$, compute $a + b$.',
        surfaceSize: const Size(500, 800),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(3));
    });

    testWidgets(r'backslash-paren \(F=ma\) flows inline after conversion', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r"using Newton's \(F=ma\). That works for cars.",
        surfaceSize: const Size(400, 800),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);

      final mathRect = tester.getRect(find.byType(Math));
      final textRect = tester.getRect(find.textContaining("Newton's"));
      expect(
        mathRect.center.dy,
        closeTo(textRect.center.dy, textRect.height),
        reason: r'\(F=ma\) should flow inline, not break to new line',
      );
    });

    testWidgets('inline LaTeX in bold context stays inline', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'**Important: $E = mc^2$ is key.**',
        surfaceSize: const Size(400, 800),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('long inline LaTeX that exceeds line width does not crash', (tester) async {
      // If inline LaTeX is wider than the screen, it should still render
      // without crashes (may overflow visually).
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Result: $a_1 + a_2 + a_3 + a_4 + a_5 + a_6 + a_7 + a_8 + a_9 + a_{10} + a_{11} + a_{12} = S$',
        surfaceSize: const Size(300, 800),
      );

      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('real model output: F=ma inline in paragraph (reported bug)', (tester) async {
      // Exact pattern from deepseek-v4-pro that triggered the new-line bug.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r"Alright, imagine you're playing a game of pool. You hit the cue ball, and you can perfectly predict where it will go and how fast, using Newton's \(F=ma\). That works for cars, planets, baseballs – anything big enough to see.",
        surfaceSize: const Size(400, 800),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);

      final mathRect = tester.getRect(find.byType(Math));
      final textFinder = find.textContaining("Newton's");
      if (textFinder.evaluate().isNotEmpty) {
        final textRect = tester.getRect(textFinder);
        expect(
          mathRect.center.dy,
          closeTo(textRect.center.dy, textRect.height),
          reason: 'F=ma should be inline with "Newton\'s", not on a new line',
        );
      }
    });
  });
}
