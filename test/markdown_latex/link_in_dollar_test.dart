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
}
