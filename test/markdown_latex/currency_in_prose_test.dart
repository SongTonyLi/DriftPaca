/// Tests for the prose-currency heuristic — distinguishes a `$...$` span
/// that is currency-inside-prose (must NOT render as math) from a `$...$`
/// span that is real LaTeX (must render as math).
///
/// The existing heuristic rejects any `$...$` containing LaTeX operators
/// (`+`, `=`, `^`, etc.) as "math, not currency". That fails for financial
/// prose with deltas — `**$971.00**, up **+5.14%** ( +$47.48 )` — where
/// the `+` is a sign indicator, not a math operator, and the whole span is
/// Chinese prose with currency figures.
///
/// The new prose-currency heuristic is an ADDITIONAL escape hatch: if a
/// `$...$` span starts with a digit, contains natural-language punctuation
/// (commas/semicolons/colons, ASCII or CJK), contains natural-language text
/// (CJK characters or multi-letter Latin words), AND does NOT contain the
/// LaTeX `\text` command, treat it as currency prose and escape the dollars.
///
/// `\text` is the explicit "embed prose in math mode" command — if present,
/// the span IS real LaTeX (with embedded prose) and must not be escaped.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:google_fonts/google_fonts.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // ---------------------------------------------------------------------------
  // The new heuristic FIRES — currency prose must NOT render as math.
  // ---------------------------------------------------------------------------
  group('prose-currency heuristic: Chinese prose with currency deltas', () {
    testWidgets('Chinese prose with +%-delta between two dollar amounts '
        'renders as text, not math', (tester) async {
      // Exact shape from the user's Micron report — `+5.14%` and `+$47.48`
      // between two currency dollars previously fooled the operator check.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '美光科技报 **\$971.00**，较前一交易日上涨 '
        '**+5.14%**（+\$47.48）。',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing,
          reason: 'currency-prose with `+` delta must not become LaTeX math');
    });

    testWidgets('Chinese list item with currency + percent delta',
        (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '- 5月26日，美光股价暴涨 **+19.29%**，盘中最高触及 **\$916.80**。\n'
        '- 5月29日，盘后回落至 **\$961.88**（-0.94%）。',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing,
          reason: 'list items with bold currency + delta must not become math');
    });

    testWidgets('verbatim Micron Technology excerpt — no math widgets',
        (tester) async {
      // Same paste as link_in_backticks_test, but here we ALSO assert no
      // Math widget. This is the previously-out-of-scope half of that bug.
      const realOutput =
          '**最新股价**：截至2026年5月29日（周五）美股收盘，美光科技报 '
          '**\$971.00**，较前一交易日上涨 **+5.14%**（+\$47.48）'
          '`[¹](https://stockanalysis.com/stocks/mu/history/)'
          '[⁵](https://stockscan.io/stocks/MU/price-history)`。'
          '盘后交易小幅回落至 **\$961.88**（-0.94%）'
          '`[¹](https://stockanalysis.com/stocks/mu/history/)`。';
      final errors = await pumpBubbleAndCollectErrors(tester, realOutput);
      expect(overflowErrors(errors), isEmpty,
          reason: 'currency prose must wrap, not render as non-wrapping math');
      expect(find.byType(Math), findsNothing,
          reason: 'no \$ run in this Chinese-prose answer is real LaTeX');
      expect(find.textContaining('](https://'), findsNothing,
          reason: 'citation links must render, not appear as raw text');
    });

    testWidgets('Chinese prose with currency RANGE separated by dash',
        (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '当日股价波动区间为 \$916.80，最高触及 \$981.00，涨幅显著。',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('Chinese prose with currency and colon (key-value)',
        (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '关键数据：开盘 \$925.50；收盘 \$971.00；涨幅 +5.14%。',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing);
    });
  });

  group('prose-currency heuristic: English prose with currency commas/words',
      () {
    testWidgets('English prose with comma + multi-letter word between '
        'dollars stays as text', (tester) async {
      // `$5,000 cap, the limit is $10,000` — starts with digit, has `,`,
      // has multi-letter word "cap"/"the"/"limit". Without the new check
      // the operator pattern wouldn't fire (no `+=^_`), so this case was
      // already handled — but we want explicit coverage that it stays so.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Budget cap is $5,000, the limit is $10,000 for the quarter.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('English currency prose with + delta between dollars',
        (tester) async {
      // The new check is the only thing rescuing this — `+` is in the span.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Stock opened at $971.00, up +5.14% on the day, gaining +$47.48.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing,
          reason: 'English currency prose with + must not become math');
    });
  });

  // ---------------------------------------------------------------------------
  // The new heuristic must NOT fire — real LaTeX must still render as math.
  // ---------------------------------------------------------------------------
  group('real LaTeX still renders as math', () {
    testWidgets(r'$E = mc^2$ renders as math', (tester) async {
      await pumpBubbleAndCollectErrors(tester, r'Einstein: $E = mc^2$.');
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets(r'$x^2 + y^2 = r^2$ renders as math', (tester) async {
      await pumpBubbleAndCollectErrors(tester, r'Circle: $x^2 + y^2 = r^2$.');
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets(r'$\frac{a}{b} + \sqrt{c}$ renders as math', (tester) async {
      await pumpBubbleAndCollectErrors(
        tester,
        r'Formula: $\frac{a}{b} + \sqrt{c}$ shown.',
      );
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets(r'$\sum_{i=1}^n i$ renders as math', (tester) async {
      await pumpBubbleAndCollectErrors(
        tester,
        r'Sum: $\sum_{i=1}^n i = \frac{n(n+1)}{2}$.',
      );
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets(r'algebra with commas but no prose text — $x+1, y-2$ stays '
        'math', (tester) async {
      // Has `,` (punctuation) but no CJK and no multi-letter Latin word —
      // only single-letter variables. The new heuristic must NOT fire.
      await pumpBubbleAndCollectErrors(tester, r'Pairs: $x+1, y-2$ given.');
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets(r'algebra starting with digit but no prose text — $1+1=2$ '
        'stays math', (tester) async {
      // Starts with digit, has operator. No punctuation, no text. Existing
      // behavior says math; new heuristic must NOT override.
      await pumpBubbleAndCollectErrors(tester, r'Trivially: $1+1=2$ holds.');
      expect(find.byType(Math), findsOneWidget);
    });
  });

  group('real LaTeX with embedded \\text prose is preserved as math', () {
    testWidgets(r'$\text{cost} = 500$ renders as math (the \text exclusion)',
        (tester) async {
      // `\text` is the explicit "embed prose in math" command. Even though
      // this span starts with a `\` (not a digit) so the heuristic would
      // skip anyway, this test pins the exclusion contract.
      await pumpBubbleAndCollectErrors(
        tester,
        r'Total: $\text{cost} = 500$ USD.',
      );
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets(r'$5 \text{ apples}, 10 \text{ oranges}$ stays math',
        (tester) async {
      // Starts with digit, has comma, has multi-letter words — meets every
      // other criterion. But \text inside makes this REAL LaTeX. The
      // exclusion must keep it as math.
      await pumpBubbleAndCollectErrors(
        tester,
        r'Inventory: $5 \text{ apples}, 10 \text{ oranges}$ in stock.',
      );
      expect(find.byType(Math), findsOneWidget,
          reason: r'\text means real LaTeX — heuristic must skip');
    });

    testWidgets(r'$5 \textbf{bold}, 10 \textit{italic}$ stays math',
        (tester) async {
      // `\text` substring check catches `\textbf` / `\textit` too — these
      // are LaTeX text-formatting commands, so the span IS real math.
      await pumpBubbleAndCollectErrors(
        tester,
        r'Styled: $5 \textbf{bold}, 10 \textit{italic}$ here.',
      );
      expect(find.byType(Math), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Regression: existing currency paths must continue to work.
  // ---------------------------------------------------------------------------
  group('existing currency paths unchanged', () {
    testWidgets(r'plain currency $5 and $10 stays as text', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Total: $5 and $10 are due today.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('currency with link between dollars — existing link path',
        (tester) async {
      // `$X [link](url) $Y` — the link inside the span triggers the existing
      // link-aware escape route. Pre-existing behavior, regression-only.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Worth $852B [³](https://example.com/source-a), low $500B.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing);
      expect(find.textContaining('](https://'), findsNothing,
          reason: 'citation link inside the currency span must render');
    });

    testWidgets(r'currency with bold $4.6 trillion stays text',
        (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Valued at **$4.6 trillion** in recent reports.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing);
    });
  });
}
