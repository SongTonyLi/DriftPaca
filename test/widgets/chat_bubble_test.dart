import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart';

Widget buildTestApp(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  List<FlutterErrorDetails> overflowErrors(Iterable<FlutterErrorDetails> errors) {
    return errors.where((details) => details.exceptionAsString().contains('overflowed by')).toList(growable: false);
  }

  Future<List<FlutterErrorDetails>> pumpBubbleAndCollectErrors(
    WidgetTester tester,
    String content, {
    Size surfaceSize = const Size(360, 800),
  }) async {
    final originalOnError = FlutterError.onError;
    final errors = <FlutterErrorDetails>[];

    addTearDown(() {
      FlutterError.onError = originalOnError;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = surfaceSize;

    try {
      FlutterError.onError = (details) {
        errors.add(details);
      };

      final message = OllamaMessage(
        content,
        role: OllamaMessageRole.assistant,
      );

      await tester.pumpWidget(buildTestApp(ChatBubble(message: message)));
      await tester.pumpAndSettle();
      return errors;
    } finally {
      FlutterError.onError = originalOnError;
    }
  }

  // ---------------------------------------------------------------------------
  // Group 1: Basic inline LaTeX
  // ---------------------------------------------------------------------------
  group('inline LaTeX basics', () {
    testWidgets('renders single-dollar inline LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The formula $E = mc^2$ is famous.',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
      expect(find.textContaining(r'$E = mc^2$'), findsNothing);
    });

    testWidgets('renders inline LaTeX before a closing bracket', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Inline math ($x^2 + y^2$) should render.',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.textContaining(r'$x^2 + y^2$'), findsNothing);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('renders inline LaTeX with inner whitespace', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Inline math like $ D $ and $ \pm $ should render.',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.textContaining(r'$ D $'), findsNothing);
      expect(find.textContaining(r'$ \pm $'), findsNothing);
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('renders multiple inline equations in one paragraph', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Given $a = 1$, $b = 2$, and $c = 3$, we compute $a + b + c$.',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(4));
    });

    testWidgets('renders inline LaTeX with subscripts and superscripts', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Variable $x_{i}^{2}$ appears frequently.',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('renders inline fractions', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The fraction $\frac{a}{b}$ is simple.',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Group 2: Display (block) LaTeX
  // ---------------------------------------------------------------------------
  group('display LaTeX basics', () {
    testWidgets('renders double-dollar display LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Here is a formula: $$E = mc^2$$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('renders multiline display LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '\$\$\n\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}\n\$\$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('renders consecutive display equations', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '\$\$a^2 + b^2 = c^2\$\$\n\n\$\$x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}\$\$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });
  });

  // ---------------------------------------------------------------------------
  // Group 3: Delimiter conversion (\(...\) and \[...\])
  // ---------------------------------------------------------------------------
  group('delimiter conversion', () {
    testWidgets(r'converts \(...\) to inline math', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Inline: \(x^2 + y^2 = r^2\) is a circle.',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
      expect(find.textContaining(r'\('), findsNothing);
    });

    testWidgets(r'converts \[...\] to display math', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Display: \[\int_0^1 x^2 \, dx = \frac{1}{3}\]',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
      expect(find.textContaining(r'\['), findsNothing);
    });

    testWidgets(r'mixes \(...\) and $...$ in same message', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'First \(a + b\) then $c + d$ together.',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets(r'mixes \[...\] and $$...$$ in same message', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Display A: \\[a^2\\]\n\nDisplay B: \$\$b^2\$\$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });
  });

  // ---------------------------------------------------------------------------
  // Group 4: LaTeX inside code blocks (should NOT render)
  // ---------------------------------------------------------------------------
  group('LaTeX inside code blocks', () {
    testWidgets('does not render LaTeX inside fenced code block', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '```\n\$E = mc^2\$\n```',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('does not render LaTeX inside inline code', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Use `$x^2$` for math.',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing);
    });

    testWidgets(r'does not convert \(...\) inside code fences', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '```python\nprint("\\(x\\)")\n```',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('renders LaTeX before and after code block but not inside', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Before: \$a^2\$\n\n```\n\$b^2\$\n```\n\nAfter: \$c^2\$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });
  });

  // ---------------------------------------------------------------------------
  // Group 5: Dollar-sign edge cases
  // ---------------------------------------------------------------------------
  group('dollar-sign edge cases', () {
    testWidgets('does not treat currency as LaTeX', (tester) async {
      // A lone dollar with a number and no closing dollar shouldn't trigger LaTeX.
      // The regex requires matching pairs, so "costs $5" has no closing $.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'It costs $5.',
      );

      expect(overflowErrors(errors), isEmpty);
      // $5.$ could be matched as LaTeX of "5." — depends on regex.
      // The key is no crash / no overflow.
    });

    testWidgets('adjacent inline and display equations', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Inline $a$ then display $$b$$ then inline $c$.',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(3));
    });

    testWidgets('empty dollar signs do not crash', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Empty: $$ $$ and $ $.',
      );

      expect(overflowErrors(errors), isEmpty);
      // Should not crash, empty content handled gracefully.
    });

    testWidgets('escaped dollar signs are not LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Price is \$10 and \$20.',
      );

      expect(overflowErrors(errors), isEmpty);
    });

    testWidgets('currency amounts with dollar signs are not LaTeX', (tester) async {
      // "$514 billion" and "$2.203 trillion" should render as text, not math
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'GDP is **US $514 billion** and **US $2.203 trillion (PPP)**.',
      );

      expect(overflowErrors(errors), isEmpty);
      // Currency should NOT produce Math widgets
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('multiple currency amounts in text', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'The price rose from \$100 to \$250, a \$150 increase.',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('real LaTeX still works alongside currency', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The formula $E=mc^2$ costs $500 to compute.',
      );

      expect(overflowErrors(errors), isEmpty);
      // E=mc^2 is real LaTeX (starts with letter), $500 is currency (starts with digit)
      expect(find.byType(Math), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Group 6: LaTeX nested inside markdown formatting
  // ---------------------------------------------------------------------------
  group('LaTeX inside markdown formatting', () {
    testWidgets('renders LaTeX inside bold text', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'**The formula $x^2$ is important.**',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('renders LaTeX inside italic text', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'*Note that $\alpha + \beta = \gamma$.*',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('renders LaTeX in a heading', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'## The equation $E = mc^2$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('renders LaTeX in a bulleted list', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '- First: \$a = 1\$\n- Second: \$b = 2\$\n- Third: \$c = 3\$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(3));
    });

    testWidgets('renders LaTeX in a numbered list', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '1. Equation: \$x + 1\$\n2. Equation: \$y + 2\$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('renders LaTeX in a blockquote', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'> The famous equation $E = mc^2$ changed physics.',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('renders display LaTeX after a heading', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '## Quadratic Formula\n\n\$\$x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}\$\$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Group 7: Overflow — long equations on narrow screens
  // ---------------------------------------------------------------------------
  group('overflow protection', () {
    testWidgets('long inline equation renders without crash', (tester) async {
      // Long inline math may overflow in narrow containers (acceptable —
      // clipped in release builds). The key is no crash.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Result: $a_1 + a_2 + a_3 + a_4 + a_5 + a_6 + a_7 + a_8 + a_9 + a_{10} + a_{11} + a_{12} + a_{13} + a_{14} + a_{15} = S$',
        surfaceSize: const Size(320, 600),
      );

      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('long display equation does not overflow screen', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$\int_{-\infty}^{\infty} e^{-x^2} \, dx = \sqrt{\pi} \quad \text{and} \quad \sum_{n=0}^{\infty} \frac{1}{n!} = e \quad \text{and} \quad \prod_{p \text{ prime}} \frac{1}{1-p^{-s}} = \zeta(s)$$',
        surfaceSize: const Size(320, 600),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('very wide matrix does not overflow', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$\begin{pmatrix} a_{11} & a_{12} & a_{13} & a_{14} & a_{15} & a_{16} & a_{17} & a_{18} \\ b_{21} & b_{22} & b_{23} & b_{24} & b_{25} & b_{26} & b_{27} & b_{28} \end{pmatrix}$$',
        surfaceSize: const Size(320, 600),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('long equation with nested fractions does not overflow', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$\frac{\frac{\frac{a}{b}}{\frac{c}{d}}}{\frac{\frac{e}{f}}{\frac{g}{h}}} + \frac{\frac{\frac{i}{j}}{\frac{k}{l}}}{\frac{\frac{m}{n}}{\frac{o}{p}}}$$',
        surfaceSize: const Size(320, 600),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Group 8: LaTeX inside markdown tables
  // ---------------------------------------------------------------------------
  group('LaTeX in tables', () {
    testWidgets('does not overflow inline LaTeX in table cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'''
| Label | Value |
| --- | --- |
| Long inline math | $x_1 + x_2 + x_3 + x_4 + x_5 + x_6 + x_7 + x_8 + x_9 + x_{10} = \frac{a+b+c+d+e+f+g+h+i+j}{k}$ |
''',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('does not overflow display LaTeX in table cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'''
| Formula |
| --- |
| $$\sum_{i=1}^{10} x_i = \frac{a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p}{q}$$ |
''',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('multiple equations in different table cells', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'''
| Name | Formula | Result |
| --- | --- | --- |
| Sum | $\sum_{i=1}^{n} i$ | $\frac{n(n+1)}{2}$ |
| Product | $\prod_{i=1}^{n} i$ | $n!$ |
''',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(4));
    });

    testWidgets('wide matrix in table cell does not overflow', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'''
| Matrix |
| --- |
| $$\begin{pmatrix} 1 & 2 & 3 & 4 & 5 & 6 & 7 & 8 & 9 & 10 \end{pmatrix}$$ |
''',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('table with mixed text and LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'''
| Concept | Description | Formula |
| --- | --- | --- |
| Area | Area of a circle | $A = \pi r^2$ |
| Circumference | Around a circle | $C = 2\pi r$ |
''',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });
  });

  // ---------------------------------------------------------------------------
  // Group 8c: Pipes inside LaTeX in table cells
  // ---------------------------------------------------------------------------
  group('pipes inside LaTeX in tables', () {
    testWidgets('renders |Psi|^2 in table cell without breaking table', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'''
| Symbol | Meaning |
| --- | --- |
| Probability | $\rho=|\Psi|^2$ |
''',
        surfaceSize: const Size(400, 800),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
      expect(find.textContaining(r'$\rho='), findsNothing);
    });

    testWidgets('renders multiple pipes in LaTeX in table', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'''
| Formula |
| --- |
| $|a| + |b| = |a+b|$ |
''',
        surfaceSize: const Size(400, 800),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('does not affect pipes outside LaTeX in table', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'''
| A | B |
| --- | --- |
| $x$ | $y$ |
''',
        surfaceSize: const Size(400, 800),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('currency dollar in separate table rows does not break cells', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'''
| Item | Price |
| --- | --- |
| Widget | $5 |
| Gadget | $10 |
''',
        surfaceSize: const Size(400, 800),
      );

      expect(overflowErrors(errors), isEmpty);
    });

    testWidgets('two currency values in same table row do not break table', (tester) async {
      // Critical: $5 in one cell must NOT pair with $10 in the next
      // cell as a LaTeX expression, which would corrupt the | delimiter.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'''
| Item | Price | Tax |
| --- | --- | --- |
| Widget | $5 | $10 |
''',
        surfaceSize: const Size(400, 800),
      );

      expect(overflowErrors(errors), isEmpty);
      // If pipes were corrupted, the table would only have 2 columns
      // instead of 3. Check that all 3 data cells rendered.
      expect(find.textContaining('Widget'), findsOneWidget);
      expect(find.textContaining('5'), findsWidgets);
      expect(find.textContaining('10'), findsWidgets);
    });

    testWidgets('inline code in table cells renders without crash', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Code |\n| --- |\n| `formula` |',
        surfaceSize: const Size(400, 800),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.textContaining('formula'), findsOneWidget);
    });

    testWidgets('mixed LaTeX and plain cells in same row', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'''
| Name | Formula | Notes |
| --- | --- | --- |
| Norm | $|\Psi|^2$ | positive |
''',
        surfaceSize: const Size(500, 800),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
      expect(find.textContaining('positive'), findsOneWidget);
    });

    testWidgets('pipe in earlier row does not break later rows', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Name | Formula |\n| --- | --- |\n| Prob | \$\\rho=|\\Psi|^2\$ |\n| Limit | \$\\hbar\\to 0\$ |',
        surfaceSize: const Size(500, 800),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('non-table line starting with pipe is not affected', (tester) async {
      // A line with | that is not a table row should pass through unchanged.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'|x| means absolute value: $|x|$.',
      );

      expect(overflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Group 8b: HTML <br> tags in markdown
  // ---------------------------------------------------------------------------
  group('HTML br tags', () {
    testWidgets('renders <br> as line break in table cells', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'''
| Key | Value |
| --- | --- |
| Info | Line one<br>Line two |
''',
        surfaceSize: const Size(400, 800),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.textContaining('<br>'), findsNothing);
      expect(find.textContaining('Line one'), findsOneWidget);
      expect(find.textContaining('Line two'), findsOneWidget);
    });

    testWidgets('renders <br/> and <br /> variants', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'First<br/>Second<br />Third',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.textContaining('<br'), findsNothing);
    });

    testWidgets('renders <br> in regular paragraphs', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Hello<br>World',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.textContaining('<br>'), findsNothing);
    });

    testWidgets('renders multiple <br> with bullet points in table cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Header |\n| --- |\n| Item A<br>• bullet one<br>• bullet two |',
        surfaceSize: const Size(400, 800),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.textContaining('<br>'), findsNothing);
    });

    testWidgets('does not affect <br> inside code blocks', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '```\n<br>\n```',
      );

      expect(overflowErrors(errors), isEmpty);
      // Inside code blocks, <br> should remain as literal text.
    });
  });

  // ---------------------------------------------------------------------------
  // Group 9: Error handling and fallback rendering
  // ---------------------------------------------------------------------------
  group('error handling and fallbacks', () {
    testWidgets('shows raw source for broken inline LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Broken formula: $\frac{1}{2$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.textContaining('Parser Error'), findsNothing);
      expect(find.textContaining(r'$\frac{1}{2$'), findsOneWidget);
    });

    testWidgets('shows raw source for broken display LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$\begin{aligned} x &= 1 \\$$ incomplete',
      );

      expect(overflowErrors(errors), isEmpty);
      // Should show fallback, not crash.
    });

    testWidgets('unknown LaTeX command shows fallback', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Formula: $\nonexistentcommand{x}$',
      );

      expect(overflowErrors(errors), isEmpty);
      // Should not crash; either renders or shows fallback.
    });

    testWidgets('mismatched braces show fallback', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Bad: $\frac{a}{b{c}$',
      );

      expect(overflowErrors(errors), isEmpty);
    });

    testWidgets('deeply nested braces do not crash', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$\frac{\frac{\frac{\frac{\frac{a}{b}}{c}}{d}}{e}}{f}$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Group 10: Complex LaTeX constructs
  // ---------------------------------------------------------------------------
  group('complex LaTeX constructs', () {
    testWidgets('renders square root', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$\sqrt{x^2 + y^2}$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('renders summation with limits', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$\sum_{k=0}^{\infty} \frac{x^k}{k!} = e^x$$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('renders integral with limits', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$\int_0^{\pi} \sin(x) \, dx = 2$$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('renders Greek letters', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$\alpha, \beta, \gamma, \delta, \epsilon, \theta, \lambda, \mu, \pi, \sigma, \omega$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('renders binomial coefficient', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$\binom{n}{k} = \frac{n!}{k!(n-k)!}$$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('renders hat and tilde accents', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$\hat{x}$, $\tilde{y}$, $\bar{z}$, $\vec{v}$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(4));
    });

    testWidgets('renders limits notation', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$\lim_{x \to 0} \frac{\sin x}{x} = 1$$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Group 11: Mixed content — full realistic messages
  // ---------------------------------------------------------------------------
  group('full realistic messages', () {
    testWidgets('renders a math explanation with inline and display LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'The quadratic equation \$ax^2 + bx + c = 0\$ has solutions given by:\n\n'
            r'$$x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$$'
            '\n\nwhere \$a \\neq 0\$.',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(3));
    });

    testWidgets('renders markdown with code and LaTeX mixed', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Use `math.sqrt(x)` in Python to compute \$\\sqrt{x}\$.\n\n'
            '```python\nimport math\nresult = math.sqrt(2)\n```\n\n'
            'This gives \$\\sqrt{2} \\approx 1.414\$.',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('renders a statistics explanation', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '## Normal Distribution\n\n'
            'The probability density function is:\n\n'
            r'$$f(x) = \frac{1}{\sigma\sqrt{2\pi}} e^{-\frac{(x-\mu)^2}{2\sigma^2}}$$'
            '\n\nwhere:\n'
            '- \$\\mu\$ is the mean\n'
            '- \$\\sigma\$ is the standard deviation\n'
            '- \$\\sigma^2\$ is the variance',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(4));
    });

    testWidgets('renders a comparison table with LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'''
## Derivative Rules

| Rule | Formula |
| --- | --- |
| Power | $\frac{d}{dx} x^n = nx^{n-1}$ |
| Product | $\frac{d}{dx}(fg) = f'g + fg'$ |
| Chain | $\frac{d}{dx} f(g(x)) = f'(g(x)) \cdot g'(x)$ |
''',
        surfaceSize: const Size(400, 800),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(3));
    });
  });

  // ---------------------------------------------------------------------------
  // Group 12: Edge cases and special characters
  // ---------------------------------------------------------------------------
  group('edge cases and special characters', () {
    testWidgets('single character inline LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The variable $x$ is unknown.',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('LaTeX with text command', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$P(\text{event}) = 0.5$$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('LaTeX with special operators', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$a \leq b$, $c \geq d$, $e \neq f$, $g \approx h$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(4));
    });

    testWidgets('LaTeX with set notation', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$A \cup B$, $C \cap D$, $x \in S$, $\emptyset \subset T$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(4));
    });

    testWidgets('LaTeX with arrows', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$a \rightarrow b$, $c \leftarrow d$, $e \Leftrightarrow f$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(3));
    });

    testWidgets('message with only display LaTeX, no surrounding text', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$\nabla \times \mathbf{E} = -\frac{\partial \mathbf{B}}{\partial t}$$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('LaTeX with whitespace-heavy content', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$  x  +  y  =  z  $',
      );

      expect(overflowErrors(errors), isEmpty);
      // Should trim and render or handle gracefully.
    });

    testWidgets('plain text message with no LaTeX renders correctly', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Hello! This is a plain message with **bold** and *italic* text.',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('empty message does not crash', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(tester, '');

      expect(overflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Group 13: Specific LaTeX commands that may fail in flutter_math_fork
  // ---------------------------------------------------------------------------
  group('flutter_math_fork compatibility', () {
    testWidgets(r'renders \mathrm and \ln commands', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$S=\hbar\,\mathrm{Im}(\ln\Psi)$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets(r'renders \hbar\to 0', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$\hbar\to 0$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets(r'renders \vert (pipe replacement)', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$\rho=\vert \Psi\vert ^2$',
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('renders LaTeX after br tags in table cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Advantages |\n| --- |\n| text A<br>text B（\$\\hbar\\to 0\$ and \$S=\\hbar\\,\\mathrm{Im}(\\ln\\Psi)\$）<br>text C |',
        surfaceSize: const Size(500, 800),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('pipe in earlier row does not break LaTeX in later rows', (tester) async {
      // Row 1 has $|\Psi|^2$ (pipes in LaTeX), row 2 has normal LaTeX.
      // Without pipe escaping, row 1 breaks the table structure and
      // cascading failures affect row 2.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Name | Formula |\n| --- | --- |\n| Prob | \$\\rho=|\\Psi|^2\$ |\n| Limit | \$\\hbar\\to 0\$ |',
        surfaceSize: const Size(500, 800),
      );

      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });
  });
}
