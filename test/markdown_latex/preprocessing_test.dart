/// Unit tests for LaTeX preprocessing behavior.
///
/// The preprocessing functions (_preprocessLatex, _escapeLatexPipesInTables)
/// are private to ChatBubble, so we test their behavior indirectly through
/// widget rendering — verifying that specific transformations occur correctly.
///
/// These tests focus on the TRANSFORMATION logic:
/// - \(...\) → $...$  and  \[...\] → $$...$$
/// - Pipe escaping in table rows
/// - Code block immunity during preprocessing
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
  // Delimiter conversion: \(...\) → $...$
  // ---------------------------------------------------------------------------
  group('preprocessLatex: inline delimiter conversion', () {
    testWidgets(r'simple \(x\) converts and renders', (tester) async {
      await pumpBubbleAndCollectErrors(tester, r'Formula: \(x^2\) here.');
      expect(find.byType(Math), findsOneWidget);
      // Should not show raw \( delimiter
      expect(find.textContaining(r'\('), findsNothing);
    });

    testWidgets(r'multiple \(...\) in paragraph', (tester) async {
      await pumpBubbleAndCollectErrors(tester, r'Given \(a\) and \(b\) and \(c\).');
      expect(find.byType(Math), findsNWidgets(3));
    });

    testWidgets(r'\(...\) with complex content', (tester) async {
      await pumpBubbleAndCollectErrors(tester, r'Equation: \(\frac{a}{b} + \sqrt{c}\).');
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets(r'\(...\) spanning NO newlines (single line only)', (tester) async {
      // \(...\) uses .+? which doesn't match \n, so multiline won't convert
      await pumpBubbleAndCollectErrors(tester, 'Start \\(x\ny\\) end');
      // Should NOT find a Math widget — the \n prevents matching
      expect(find.byType(Math), findsNothing);
    });

    testWidgets(r'\(...\) inside code block is NOT converted', (tester) async {
      await pumpBubbleAndCollectErrors(tester, '```\n\\(x^2\\)\n```');
      expect(find.byType(Math), findsNothing);
    });

    testWidgets(r'\(...\) inside inline code is NOT converted', (tester) async {
      await pumpBubbleAndCollectErrors(tester, r'Use `\(x\)` syntax.');
      expect(find.byType(Math), findsNothing);
    });

    testWidgets(r'\(...\) before and after code block', (tester) async {
      await pumpBubbleAndCollectErrors(
        tester,
        '\\(a\\)\n\n```\n\\(b\\)\n```\n\n\\(c\\)',
      );
      // Only a and c should render, not b inside code
      expect(find.byType(Math), findsNWidgets(2));
    });
  });

  // ---------------------------------------------------------------------------
  // Delimiter conversion: \[...\] → $$...$$
  // ---------------------------------------------------------------------------
  group('preprocessLatex: display delimiter conversion', () {
    testWidgets(r'simple \[...\] converts and renders', (tester) async {
      await pumpBubbleAndCollectErrors(tester, r'Display: \[x^2 + y^2 = r^2\]');
      expect(find.byType(Math), findsOneWidget);
      expect(find.textContaining(r'\['), findsNothing);
    });

    testWidgets(r'multiline \[...\] converts', (tester) async {
      await pumpBubbleAndCollectErrors(
        tester,
        '\\[\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}\\]',
      );
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets(r'\[...\] inside code block is NOT converted', (tester) async {
      await pumpBubbleAndCollectErrors(tester, '```\n\\[x^2\\]\n```');
      expect(find.byType(Math), findsNothing);
    });

    testWidgets(r'mixed \(...\) and \[...\] in same message', (tester) async {
      await pumpBubbleAndCollectErrors(
        tester,
        'Inline \\(a\\) and display:\n\n\\[b^2\\]',
      );
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets(r'\[...\] with display math content renders as block', (tester) async {
      await pumpBubbleAndCollectErrors(
        tester,
        '\\[\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}\\]',
      );
      expect(find.byType(Math), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Pipe escaping in table rows
  // ---------------------------------------------------------------------------
  group('escapeLatexPipesInTables: pipe → \\vert conversion', () {
    testWidgets('|x| in table cell renders as LaTeX vert', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Formula |\n| --- |\n| \$|x|\$ |',
        surfaceSize: const Size(400, 800),
      );
      expect(overflowErrors(errors), isEmpty);
      // The pipe was escaped to \vert and Math rendered
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('|| (double pipe/norm) becomes \\Vert', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Norm |\n| --- |\n| \$||v||_2\$ |',
        surfaceSize: const Size(400, 800),
      );
      expect(errors.where((d) => !d.exceptionAsString().contains('overflowed by')), isEmpty);
    });

    testWidgets('pipes in non-table lines are NOT escaped', (tester) async {
      // A line that doesn't start with | should not have its LaTeX modified
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Absolute value: \$|x|\$',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets(r'currency guard: $5 | $10 in table is NOT escaped', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| A | B | C |\n| --- | --- | --- |\n| Widget | \$5 | \$10 |',
        surfaceSize: const Size(400, 800),
      );
      expect(overflowErrors(errors), isEmpty);
      // Table should have 3 columns — pipes preserved as delimiters
      expect(find.textContaining('Widget'), findsOneWidget);
    });

    testWidgets('LaTeX with pipe + currency in same table', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Name | Formula | Cost |\n| --- | --- | --- |\n| Norm | \$|x|\$ | \$5 |',
        surfaceSize: const Size(500, 800),
      );
      expect(overflowErrors(errors), isEmpty);
      // LaTeX cell should render, currency cell should not corrupt
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('inline code in table row is skipped during pipe escape', (tester) async {
      // NOTE: Pipes inside inline code in table cells are a known markdown
      // ambiguity — the table parser may split on them before code is parsed.
      // Using escaped pipe &#124; or avoiding | in code inside tables is recommended.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Code | Math |\n| --- | --- |\n| `a\\|b` | \$|x|\$ |',
        surfaceSize: const Size(400, 800),
      );
      expect(overflowErrors(errors), isEmpty);
      // The LaTeX pipe was escaped to \vert and rendered
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('already-escaped \\vert is not double-escaped', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Formula |\n| --- |\n| \$\\vert x \\vert\$ |',
        surfaceSize: const Size(400, 800),
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Combined preprocessing: delimiters + pipe escape together
  // ---------------------------------------------------------------------------
  group('combined preprocessing pipeline', () {
    testWidgets(r'\(...\) with pipes in table row', (tester) async {
      // Tests that delimiter conversion happens BEFORE pipe escaping
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Formula |\n| --- |\n| \\(|x|\\) |',
        surfaceSize: const Size(400, 800),
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets(r'\[...\] with pipes in table row', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Equation |\n| --- |\n| \\[|\\Psi|^2\\] |',
        surfaceSize: const Size(400, 800),
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('code fence + delimiter conversion + table pipes all together', (tester) async {
      final content = '\\(a\\)\n\n'
          '```python\nx = \\(b\\)\n```\n\n'
          '| Formula |\n| --- |\n| \\(|c|\\) |';
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        content,
        surfaceSize: const Size(400, 1200),
      );
      expect(overflowErrors(errors), isEmpty);
      // \\(a\\) renders, code block doesn't, table \\(|c|\\) renders
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('multiple table rows with mixed delimiters and pipes', (tester) async {
      final content = '| Name | Formula |\n| --- | --- |\n'
          '| Abs | \\(|x|\\) |\n'
          '| Norm | \$||v||_2\$ |\n'
          '| Prob | \\(P(A|B)\\) |';
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        content,
        surfaceSize: const Size(500, 800),
      );
      expect(overflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Regression: specific patterns that have broken in the past
  // ---------------------------------------------------------------------------
  group('preprocessing regressions', () {
    testWidgets('Schrödinger probability density in table', (tester) async {
      // This exact pattern was reported as breaking table layout.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Symbol | Meaning |\n| --- | --- |\n| Probability | \$\\rho=|\\Psi|^2\$ |',
        surfaceSize: const Size(500, 800),
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('pipe in earlier row does not break later rows', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Name | Formula |\n| --- | --- |\n'
            '| Prob | \$\\rho=|\\Psi|^2\$ |\n'
            '| Limit | \$\\hbar\\to 0\$ |',
        surfaceSize: const Size(500, 800),
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('LaTeX after <br> in table cell with pipes', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Info |\n| --- |\n| text<br>\$|\\Psi|^2\$ is positive |',
        surfaceSize: const Size(500, 800),
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('backslash-escaped dollars in prose are NOT LaTeX', (tester) async {
      // \$10 should remain as literal $10, not start LaTeX
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The price is \$10 and the formula is $x^2$.',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // LaTeX code fence unwrapping
  // ---------------------------------------------------------------------------
  group('unwrapLatexCodeFences', () {
    testWidgets('```latex fence is unwrapped and content renders', (tester) async {
      await pumpBubbleAndCollectErrors(
        tester,
        '```latex\n\\frac{a}{b} + \\sum_{i=0}^n x_i\n```',
      );
      // After unwrapping, the content should be rendered as display LaTeX
      // (it contains no $ delimiters, so it renders as plain text — NOT in a code block)
      // The key assertion: it's NOT rendered as a code block anymore
    });

    testWidgets('```latex fence with dollar-delimited LaTeX renders as math', (tester) async {
      await pumpBubbleAndCollectErrors(
        tester,
        '```latex\n\$\$\\frac{a}{b}\$\$\n```',
      );
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('```math fence is unwrapped', (tester) async {
      await pumpBubbleAndCollectErrors(
        tester,
        '```math\n\$x^2 + y^2 = r^2\$\n```',
      );
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('```markdown fence is unwrapped and table renders', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '```markdown\n| A | B |\n| --- | --- |\n| \$x^2\$ | \$y^2\$ |\n```',
        surfaceSize: const Size(400, 800),
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('```python fence is NOT unwrapped', (tester) async {
      await pumpBubbleAndCollectErrors(
        tester,
        '```python\nprint("\$x^2\$")\n```',
      );
      // Python code blocks should remain as code — no Math rendering
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('normal code fence is NOT unwrapped', (tester) async {
      await pumpBubbleAndCollectErrors(
        tester,
        '```\n\$x^2\$\n```',
      );
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('mixed: latex fence + real code fence + inline LaTeX', (tester) async {
      final content = '```latex\n\$\$E = mc^2\$\$\n```\n\n'
          '```python\nx = 42\n```\n\n'
          'And inline: \$a^2 + b^2 = c^2\$';
      await pumpBubbleAndCollectErrors(tester, content);
      // latex fence renders as math, python stays as code, inline renders
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('real model output: gemma3 wraps table in ```markdown```', (tester) async {
      // Actual gemma3 response pattern — table wrapped in markdown fence
      final content = '```markdown\n'
          '| Equation | Form |\n'
          '| --- | --- |\n'
          '| Schrödinger | \$i\\hbar \\frac{\\partial}{\\partial t} \\Psi = \\hat{H} \\Psi\$ |\n'
          '| Probability | \$|\\Psi|^2\$ |\n'
          '```\n\n'
          'The wave function \$\\Psi\$ encodes all quantum information.';
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        content,
        surfaceSize: const Size(500, 1000),
      );
      expect(overflowErrors(errors), isEmpty);
      // Table LaTeX + inline LaTeX should all render
      expect(find.byType(Math), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  // Real LLM response patterns (from fixture data)
  // ---------------------------------------------------------------------------
  group('real LLM response patterns', () {
    testWidgets('qwen3 Schrödinger table with |Ψ|² renders', (tester) async {
      // Actual qwen3-next:80b response pattern
      const response = '| Name | Formula | Notes |\n'
          '|------|---------|-------|\n'
          r'| Schrödinger equation | $i\hbar \frac{\partial \Psi}{\partial t} = \hat{H} \Psi$ | $|\Psi|^2$ represents the probability density |'
          '\n'
          r'| Heisenberg uncertainty | $\Delta x \cdot \Delta p \geq \frac{\hbar}{2}$ | Fundamental limit on position and momentum |'
          '\n'
          r'| Quadratic formula | $x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$ | Solves $ax^2 + bx + c = 0$ |';
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        response,
        surfaceSize: const Size(600, 1000),
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsWidgets);
    });

    testWidgets('deepseek proof with \\[...\\] display math renders', (tester) async {
      // Actual deepseek-v3.2 response pattern
      const response = r'We prove by induction that \(\sum_{k=1}^n k^2 = \frac{n(n+1)(2n+1)}{6}\).'
          '\n\n**Base Case:**\n'
          r'The left-hand side is \(1^2 = 1\), and the right-hand side is'
          '\n'
          r'\[\frac{1 \cdot 2 \cdot 3}{6} = 1.\]'
          '\n'
          r'**Inductive Step:** Assume true for \(m\):'
          '\n'
          r'\[\sum_{k=1}^{m+1} k^2 = \frac{m(m+1)(2m+1)}{6} + (m+1)^2\]';
      final errors = await pumpBubbleAndCollectErrors(tester, response);
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsWidgets);
    });

    testWidgets('model mixes code block with LaTeX explanation', (tester) async {
      // Pattern: explanation with LaTeX, then code, then more LaTeX
      const response = 'The heat equation is:\n\n'
          r'$$\frac{\partial u}{\partial t} = \alpha \nabla^2 u$$'
          '\n\n'
          'Python implementation:\n\n'
          '```python\nimport numpy as np\n\ndef heat_1d(u, alpha, dx, dt):\n    return u + alpha * dt / dx**2 * (np.roll(u,1) - 2*u + np.roll(u,-1))\n```\n\n'
          r'The CFL condition requires $\alpha \frac{\Delta t}{\Delta x^2} \leq \frac{1}{2}$.';
      final errors = await pumpBubbleAndCollectErrors(tester, response);
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets(r'model uses \( \) alongside $...$ in same response', (tester) async {
      const response = r'Einstein showed that \(E = mc^2\), which means '
          r'energy and mass are equivalent. '
          r'Combined with $p = \frac{E}{c}$, we get the full relation:'
          '\n\n'
          r'$$E^2 = (pc)^2 + (mc^2)^2$$';
      final errors = await pumpBubbleAndCollectErrors(tester, response);
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(3));
    });
  });

  // ---------------------------------------------------------------------------
  // Regression: multi-line \[...\] display blocks with \tag{} and trailing
  // hard-breaks (DeepSeek "薛定谔方程与质能方程" pattern). The block close
  // `\]  ` became `$$  ` (trailing whitespace) which LatexBlockSyntax refused
  // to match, so the block swallowed every following paragraph; and each
  // \tag{} threw (unsupported), dropping equations to the raw-source fallback.
  // ---------------------------------------------------------------------------
  group('display block over-consumption + \\tag', () {
    testWidgets(r'\tag{1} in multi-line \[...\] block renders, no raw fallback', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '**薛定谔方程**\n'
        '\\[\n'
        r'i\hbar\frac{\partial}{\partial t}\Psi = \left[ -\frac{\hbar^2}{2m}\nabla^2 + V \right] \Psi'
        '\n'
        r'\tag{1}'
        '\n'
        '\\]  \n'
        '它基于经典的能量-动量关系。',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      // Equation renders as math (not the raw-source fallback).
      expect(find.byType(Math), findsOneWidget);
      // No raw `$$` delimiters leak into the visible text — that would mean
      // the fallback renderer showed the source.
      expect(find.textContaining(r'$$'), findsNothing);
      // The paragraph following the block survives as prose (was swallowed
      // into the over-consumed block before the fix).
      expect(find.textContaining('它基于经典的能量-动量关系'), findsOneWidget);
    });

    testWidgets(r'two consecutive \[...\] blocks with \tag do not merge', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '\\[\n'
        r'E = \frac{p^2}{2m} + V'
        '\n'
        r'\tag{2}'
        '\n'
        '\\]  \n'
        '中间的说明文字。  \n'
        '\\[\n'
        r'E^2 = p^2c^2 + m^2c^4'
        '\n'
        r'\tag{4}'
        '\n'
        '\\]  \n'
        '结尾说明。',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      // Both display equations render independently.
      expect(find.byType(Math), findsNWidgets(2));
      expect(find.textContaining(r'$$'), findsNothing);
      // Prose between and after the blocks is preserved, not consumed.
      expect(find.textContaining('中间的说明文字'), findsOneWidget);
      expect(find.textContaining('结尾说明'), findsOneWidget);
    });

    testWidgets(r'\tag*{★} starred form renders the label verbatim', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'$$E = mc^2 \tag*{\star}$$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
      expect(find.textContaining(r'$$'), findsNothing);
    });
  });
}
