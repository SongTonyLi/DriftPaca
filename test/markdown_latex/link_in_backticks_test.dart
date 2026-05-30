/// Tests for citation links wrapped in inline-code backticks: `[¹](url)[⁵](url)`
///
/// Some models (observed in Chinese financial-comparison answers) emit their
/// citation markdown links wrapped in single backticks, e.g.:
///
///   报 **$971.00**，较前一交易日上涨 **+5.14%**（+$47.48）
///   `[¹](https://stockanalysis.com/stocks/mu/history/)[⁵](https://stockscan.io/stocks/MU/price-history)`。
///
/// BUG: The markdown parser sees the backticks first and renders the entire
/// contents as inline code (monospace literal text), so `[¹](url)[⁵](url)`
/// shows up character-for-character instead of as clickable favicons.
///
/// Fix mirrors `_unwrapDollarWrappedLinks`: detect a backtick run whose only
/// content is one or more contiguous markdown links and strip the backticks
/// before the parser runs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // ---------------------------------------------------------------------------
  // Widget-level: backtick-wrapped citation links render as links, not as
  // monospace literal `[N](url)` text.
  // ---------------------------------------------------------------------------
  group('widget: backtick-wrapped citation links', () {
    testWidgets('single backtick-wrapped citation renders as a link',
        (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '事实如此 `[¹](https://example.com/source)`。',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      // If the backticks survived preprocessing the link syntax leaks into
      // visible text via the inline-code path.
      expect(find.textContaining('](https://'), findsNothing,
          reason: 'backtick-wrapped citation must render as a link, '
              'not as monospace literal text');
    });

    testWidgets('chained backtick-wrapped citations [¹][⁵] render as links',
        (tester) async {
      // Verbatim shape from the Micron/SK-hynix report (two contiguous
      // superscript citations sharing one pair of backticks).
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '美光科技报 **\$971.00**，较前一交易日上涨 **+5.14%**（+\$47.48）'
        '`[¹](https://stockanalysis.com/stocks/mu/history/)'
        '[⁵](https://stockscan.io/stocks/MU/price-history)`。',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.textContaining('](https://'), findsNothing,
          reason: 'both citation links must render, not appear as raw text');
    });

    testWidgets('backtick-wrapped citation inside a list item renders',
        (tester) async {
      // Same pattern, but with the citations sitting at the end of a bullet —
      // this is how the user reported it (per-bullet "近期走势" list).
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '- 5月26日，美光股价暴涨 **+19.29%** '
        '`[¹](https://stockanalysis.com/stocks/mu/history/)'
        '[⁴](https://www.google.com/finance/beta/quote/MU:NASDAQ)`。\n'
        '- 随后几个交易日股价继续攀升 '
        '`[¹](https://stockanalysis.com/stocks/mu/history/)'
        '[⁵](https://stockscan.io/stocks/MU/price-history)`。',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.textContaining('](https://'), findsNothing);
    });

    testWidgets('real model excerpt (Micron Technology) — citation links '
        'render without raw markdown leaking', (tester) async {
      // Verbatim excerpt of the assistant output the user pasted as the bug
      // report. Note this prose ALSO contains a currency span
      // `$971.00 ... +$47.48` whose `+` between two dollars trips the
      // inline-LaTeX operator heuristic into producing a Math widget — that
      // is a pre-existing, unrelated currency-heuristic limitation that this
      // backtick fix does not address. So we assert only what this fix owns:
      // no link-syntax leakage and no overflow.
      const realOutput =
          '**最新股价**：截至2026年5月29日（周五）美股收盘，美光科技报 '
          '**\$971.00**，较前一交易日上涨 **+5.14%**（+\$47.48）'
          '`[¹](https://stockanalysis.com/stocks/mu/history/)'
          '[⁵](https://stockscan.io/stocks/MU/price-history)`。'
          '盘后交易小幅回落至 **\$961.88**（-0.94%）'
          '`[¹](https://stockanalysis.com/stocks/mu/history/)`。';
      final errors = await pumpBubbleAndCollectErrors(tester, realOutput);
      expect(overflowErrors(errors), isEmpty,
          reason: 'no run of the answer should overflow the bubble');
      expect(find.textContaining('](https://'), findsNothing,
          reason: 'citation links must render, not appear as raw text');
    });
  });

  // ---------------------------------------------------------------------------
  // Negative cases: legitimate inline code must NOT be unwrapped.
  // ---------------------------------------------------------------------------
  group('widget: inline code preserved', () {
    testWidgets('plain inline code stays as code', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Use `curl` to fetch the page.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      // The literal word "curl" must still render — we just don't want any
      // raw markdown link syntax visible (none in this input anyway).
      expect(find.textContaining('](https://'), findsNothing);
    });

    testWidgets('inline code with prose AND a link is NOT unwrapped',
        (tester) async {
      // A backtick span containing a link mixed with non-link text is
      // ambiguous (could be a real code example demonstrating markdown
      // syntax). The fix only strips backticks whose entire content is
      // contiguous links, so this stays as code.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Markdown syntax: `see [link](http://example.com) here` works.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      // The link syntax IS supposed to appear here — it's part of a code
      // span that we intentionally left alone. So we don't assert its
      // absence; we just check there's no rendering error.
    });
  });
}
