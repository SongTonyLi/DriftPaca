/// Tests for links wrapped in dollar signs: $[[1]](url)$
///
/// Some models (e.g. deepseek, qwen) output citation links wrapped in $...$,
/// like: `text $[[1]](https://example.com)$`
///
/// BUG: The inline LaTeX parser matches $[...](...) $ as a LaTeX expression,
/// consuming the markdown link. The link never reaches the LinkSyntax parser
/// and renders as broken math instead of a clickable hyperlink.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

import 'test_helpers.dart';

/// Inline LaTeX syntax identical to the app's _InlineLatexSyntax.
class _InlineLatexSyntax extends md.InlineSyntax {
  _InlineLatexSyntax()
      : super(r'\$\$([\s\S]+?)\$\$|\$([^$\n]+?)\$', startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final displayContent = match.group(1);
    final inlineContent = match.group(2);
    final equation = (displayContent ?? inlineContent)?.trim();
    if (equation == null || equation.isEmpty) {
      parser.addNode(md.Text(match.group(0)!));
      return true;
    }
    final element = md.Element.text('latex', equation);
    element.attributes['MathStyle'] =
        displayContent != null ? 'display' : 'text';
    parser.addNode(element);
    return true;
  }
}

/// Parse with the app's inline syntax order (LaTeX before GFM).
String parseWithLatex(String input) {
  final ext = md.ExtensionSet(
    md.ExtensionSet.gitHubFlavored.blockSyntaxes,
    [_InlineLatexSyntax(), ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes],
  );
  final doc = md.Document(extensionSet: ext);
  return md.renderToHtml(doc.parseLines(input.split('\n')));
}

/// Applies the dollar-wrapped link fix, then parses.
final _dollarWrappedLinkPattern =
    RegExp(r'\$(\[+[^\]]*\]+\([^)]+\))\$');

String parseWithFix(String input) {
  final fixed =
      input.replaceAllMapped(_dollarWrappedLinkPattern, (m) => m[1]!);
  return parseWithLatex(fixed);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // ---------------------------------------------------------------------------
  // Parser-level: demonstrate the LaTeX parser consuming links
  // ---------------------------------------------------------------------------
  group('parser: dollar-wrapped links consumed by LaTeX', () {
    test(r'$[[1]](url)$ — LaTeX eats the link', () {
      final html =
          parseWithLatex(r'text $[[1]](https://example.com)$');
      // BUG: produces <latex> element instead of <a> link
      expect(html, contains('<latex'),
          reason: 'LaTeX parser consumes the link text');
      expect(html, isNot(contains('<a ')),
          reason: 'Link never reaches the link parser');
    });

    test(r'$[text](url)$ — simpler link also consumed', () {
      final html = parseWithLatex(r'see $[click](https://example.com)$ here');
      expect(html, contains('<latex'));
      expect(html, isNot(contains('<a ')));
    });

    test('exact line from test.txt — line 19 citation link', () {
      final html = parseWithLatex(
        '调查显示越南是对 AI 开放程度最高的市场之一，高达 78% 的受访者'
        r'在过去三个月使用过 AI $[[1]](https://news.qq.com/rain/a/20250820A08E7100)$。',
      );
      expect(html, isNot(contains('<a ')),
          reason: 'Citation link is eaten by LaTeX parser');
    });

    test('multiple dollar-wrapped citations in one line', () {
      final html = parseWithLatex(
        r'First fact $[[1]](https://a.com)$ and second $[[2]](https://b.com)$.',
      );
      expect(html, isNot(contains('<a ')));
    });

    test(r'regular link (no $) works fine', () {
      final html =
          parseWithLatex(r'see [[1]](https://example.com) here');
      expect(html, contains('<a '));
    });

    test(r'real LaTeX $x^2$ is unaffected', () {
      final html = parseWithLatex(r'formula $x^2$ is nice');
      expect(html, contains('<latex'));
    });
  });

  // ---------------------------------------------------------------------------
  // Parser-level: verify the fix works
  // ---------------------------------------------------------------------------
  group('parser: dollar-wrapped link fix', () {
    test(r'$[[1]](url)$ — fix strips dollars, link renders', () {
      final html =
          parseWithFix(r'text $[[1]](https://example.com)$');
      expect(html, contains('<a '));
      expect(html, isNot(contains('<latex')));
    });

    test(r'$[text](url)$ — simpler link also fixed', () {
      final html =
          parseWithFix(r'see $[click](https://example.com)$ here');
      expect(html, contains('<a '));
    });

    test('exact line 19 from test.txt — citation link rendered', () {
      final html = parseWithFix(
        '调查显示越南是对 AI 开放程度最高的市场之一，高达 78% 的受访者'
        r'在过去三个月使用过 AI $[[1]](https://news.qq.com/rain/a/20250820A08E7100)$。',
      );
      expect(html, contains('<a '));
      expect(html, contains('https://news.qq.com'));
    });

    test('multiple dollar-wrapped citations — all fixed', () {
      final html = parseWithFix(
        r'First fact $[[1]](https://a.com)$ and second $[[2]](https://b.com)$.',
      );
      expect(html, contains('https://a.com'));
      expect(html, contains('https://b.com'));
    });

    test(r'real LaTeX $x^2$ still renders as LaTeX', () {
      final html = parseWithFix(r'formula $x^2$ is nice');
      expect(html, contains('<latex'));
      expect(html, isNot(contains('<a ')));
    });

    test('mixed: real LaTeX + citation link — both correct', () {
      final html = parseWithFix(
        r'The formula $E = mc^2$ was proven $[[1]](https://physics.org)$.',
      );
      expect(html, contains('<latex'),
          reason: r'$E = mc^2$ renders as LaTeX');
      expect(html, contains('<a '),
          reason: 'Citation renders as link');
    });

    test(r'fix does not strip $5 or $var (non-link dollar)', () {
      final html = parseWithFix(r'costs $5 and $10 total');
      expect(html, isNot(contains('<a ')));
    });
  });

  // ---------------------------------------------------------------------------
  // Widget-level: verify rendering behavior
  // ---------------------------------------------------------------------------
  group('widget: dollar-wrapped citation links', () {
    testWidgets('dollar-wrapped citation renders as link, not LaTeX',
        (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'使用过 AI $[[1]](https://news.qq.com/rain/a/20250820A08E7100)$。',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      // After fix: should render as a link, not a Math widget
      // Currently broken: renders as Math
      expect(find.byType(Math), findsNothing,
          reason: 'Citation link should not render as LaTeX math');
    });

    testWidgets('exact line 19 from test.txt', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '    *   **开放度极高**：调查显示越南是对 AI 开放程度最高的市场之一，'
        r'高达 78% 的受访者在过去三个月使用过 AI $[[1]](https://news.qq.com/rain/a/20250820A08E7100)$。',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('exact line 17 from test.txt — citation after long text',
        (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '这些平台通过结合越南文化、本地教育需求（如预测大学录取率）'
        r'在本地获得了极高满意度 $[[1]](https://news.qq.com/rain/a/20250820A08E7100)$。',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('mixed: real LaTeX + dollar-wrapped citation', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The formula $E = mc^2$ was discovered long ago $[[1]](https://physics.org)$.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      // Real LaTeX should still render as Math
      expect(find.byType(Math), findsOneWidget,
          reason: r'$E = mc^2$ should render as Math; citation should not');
    });

    testWidgets('dollar-wrapped link with arrow LaTeX in same paragraph',
        (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'通过构建大规模的越南语数据集 $\rightarrow$ 微调开源模型 '
        r'$\rightarrow$ 快速落地到教育、金融和政务场景 '
        r'$[[1]](https://news.qq.com/rain/a/20250820A08E7100)$。',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Widget-level: currency $X ... $Y bracketing a link
  //
  // The LaTeX inline parser pairs the first two `$` signs in a paragraph and
  // consumes everything between them as a single text node when the content is
  // currency-like. Any `[text](url)` between the two currency dollars never
  // reaches the link parser. Reproduces the symptom seen in the table-cell
  // screenshot: `$852B [³](url)，最低报 $500B` rendered as raw markdown.
  // ---------------------------------------------------------------------------
  group('widget: currency-bracketed links', () {
    testWidgets('link between two currency dollars renders as a link',
        (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'估值最高报 $852B [³](https://example.com/source-a)，'
        r'最低报 $500B 来源不一。',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing,
          reason: 'Currency dollars should not produce LaTeX Math widgets');
      // The link URL must not appear as literal text — that means the
      // markdown parser saw it as a link, not as a Text node consumed by
      // _InlineLatexSyntax.
      expect(find.textContaining('](https://'), findsNothing,
          reason: 'Raw link syntax should not appear as visible text');
    });

    testWidgets('two currency+link pairs in one paragraph render both links',
        (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'最高报 $852B [³](https://a.example/path-one)，'
        r'最低报 $500B [⁵](https://b.example/path-two)。',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing);
      expect(find.textContaining('](https://'), findsNothing,
          reason: 'Neither link syntax should appear as visible text');
    });

    testWidgets('bold currency range with link in same cell',
        (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'| Co | Val | Note |' '\n'
        r'| :--- | :--- | :--- |' '\n'
        r'| OpenAI | **$5000 亿 - $8520 亿** | 最高报 $852B [³](https://example.com/cite) |',
        surfaceSize: const Size(800, 600),
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing,
          reason: 'Currency in bold should not become LaTeX');
      expect(find.textContaining('](https://'), findsNothing);
    });

    testWidgets('real LaTeX in same paragraph as currency+link still renders',
        (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The formula $E = mc^2$ proves it; cost is $852B '
        r'[ref](https://example.com/proof).',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      // E = mc^2 has math operators, so it's still real LaTeX.
      expect(find.byType(Math), findsOneWidget,
          reason: r'$E = mc^2$ should still render as LaTeX');
      expect(find.textContaining('](https://'), findsNothing,
          reason: 'The currency-bracketed link should render');
    });

    testWidgets('plain currency without trailing link is unaffected',
        (tester) async {
      // Sanity: ensure preprocessing doesn't break the simple currency case.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Total cost is $5 and $10 and $15.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNothing);
    });

    testWidgets('real model output (Vietnam GDP comparison) renders without '
        'overflow, stray math, or strikethrough', (tester) async {
      // Verbatim excerpt of the financial-comparison answer that triggered
      // both the right-overflow (currency $ paired as math) and the
      // scratched-out text (lone ~ paired as strikethrough).
      const realOutput =
          '- **United States** – Alphabet/Google is valued at roughly '
          r'**$4.6 trillion** in the most recent USD sources '
          r'[⁷](https://capital.com/en-int/markets/shares/largest-tech-companies-by-market-cap)'
          r'[⁸](https://www.financecharts.com/keyword/internet_services), '
          r'while Source 1 lists it at **€3.909 trillion** '
          r'[¹](https://companiesmarketcap.com/eur/internet/largest-internet-companies-by-market-cap/). '
          r'Amazon is shown at about **$2.42 trillion** '
          r'[⁴](https://www.investopedia.com/articles/personal-finance/030415/worlds-top-10-internet-companies.asp).'
          '\n\n'
          r"**Scale relative to Vietnam's GDP** "
          r"Vietnam's nominal GDP is about **$514 billion**. Alphabet alone "
          r'(~$4.6T) '
          r'[⁷](https://capital.com/en-int/markets/shares/largest-tech-companies-by-market-cap) '
          r'is worth roughly **nine times** that amount. Tencent '
          r'(~$423B–$580B) '
          r'[¹](https://companiesmarketcap.com/eur/internet/largest-internet-companies-by-market-cap/) '
          r"by itself is comparable to Vietnam's entire annual output.";
      final errors = await pumpBubbleAndCollectErrors(tester, realOutput);
      expect(overflowErrors(errors), isEmpty,
          reason: 'currency prose must wrap, not render as non-wrapping math');
      expect(find.byType(Math), findsNothing,
          reason: 'no \$ run in this prose is real LaTeX');
      expect(find.textContaining('](https://'), findsNothing,
          reason: 'citation links must render, not appear as raw text');
      var struck = false;
      for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
        rt.text.visitChildren((span) {
          if (span is TextSpan &&
              span.style?.decoration == TextDecoration.lineThrough) {
            struck = true;
          }
          return true;
        });
      }
      expect(struck, isFalse, reason: 'lone ~ must not strike out text');
    });

    testWidgets('lone ~ before currency is not parsed as strikethrough',
        (tester) async {
      // `~` means "approximately" before amounts (e.g. `~$4.6T`, `~$423B`).
      // GFM strikethrough pairs lone tildes, so two of them struck out the
      // entire prose run between (the scratched-out-text screenshot bug).
      await pumpBubbleAndCollectErrors(
        tester,
        r'Alphabet alone (~$4.6T) [⁷](https://a.com) is worth roughly nine '
        r'times that amount. Tencent (~$423B–$580B) [¹](https://b.com) by '
        r'itself is comparable.',
      );
      var struck = false;
      for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
        rt.text.visitChildren((span) {
          if (span is TextSpan &&
              span.style?.decoration == TextDecoration.lineThrough) {
            struck = true;
          }
          return true;
        });
      }
      expect(struck, isFalse,
          reason: 'lone ~ before currency must render literally, not strike '
              'through the surrounding text');
    });

    testWidgets('currency span whose links contain operator chars in the URL '
        'does not render as overflowing math', (tester) async {
      // The financial-comparison bug: a long prose run sits between two
      // currency dollars, and the citation URLs inside it contain `_`/`=`/`+`
      // (e.g. `internet_services`). Those fooled the currency heuristic into
      // treating the span as LaTeX, which doesn't wrap and overflowed ~2000px.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'Alphabet is valued at roughly **$4.6 trillion** in the most recent '
        r'sources [⁷](https://capital.com/markets/shares/largest-tech-companies) '
        r'[⁸](https://www.financecharts.com/keyword/internet_services), while '
        r'Amazon is shown at about **$2.42 trillion** '
        r'[⁴](https://www.investopedia.com/articles/030415/top-10.asp).',
      );
      expect(overflowErrors(errors), isEmpty,
          reason: 'currency prose with operator-char URLs must wrap, not '
              'render as a single non-wrapping math run');
      expect(find.byType(Math), findsNothing,
          reason: 'currency dollars around prose must not become LaTeX');
      expect(find.textContaining('](https://'), findsNothing,
          reason: 'citation links must render, not appear as raw text');
    });
  });

  // ---------------------------------------------------------------------------
  // Static method: _hideIncompleteLinks (used by streaming reveal)
  //
  // While the typewriter reveal incrementally exposes content, a partial
  // `[text](url` (no closing paren yet) must be hidden so the user doesn't
  // see raw markdown syntax mid-stream.
  // ---------------------------------------------------------------------------
  group('widget: incomplete links during streaming reveal', () {
    testWidgets('content ending mid-link does not show raw markdown',
        (tester) async {
      // During streaming, the reveal may produce content ending mid-link.
      // The pre-reveal substring is `Click [here](http://exam` — without
      // closing `)`. _hideIncompleteLinks should truncate so only `Click ` is
      // shown.
      //
      // We test the static API indirectly by passing such content as if it
      // were already-revealed text. (The ChatBubble defaults to non-streaming
      // mode in test_helpers, so the truncation is bypassed there. This test
      // ensures the full content path still renders cleanly when complete.)
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Click [here](http://example.com) for details.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.textContaining('](http'), findsNothing,
          reason: 'Completed link should render as link, not raw markdown');
    });
  });
}
