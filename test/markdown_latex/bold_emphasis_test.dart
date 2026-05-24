/// Tests for bold (**) emphasis rendering, focusing on CJK + punctuation
/// interactions that trigger CommonMark flanking delimiter misparsing.
///
/// ROOT CAUSE: CommonMark's left/right-flanking delimiter rules require that
/// when `**` is followed by Unicode punctuation (like `"`, `（`, `《`), the
/// character BEFORE `**` must be whitespace or punctuation. CJK characters
/// satisfy neither condition, so `CJK**"text"**CJK` fails — the `**` cannot
/// open/close emphasis, causing the parser to mispair `**` markers and bold
/// the wrong text.
///
/// FIX: _fixEmphasisFlanking inserts ZWSP (U+200B) between `*` runs and
/// adjacent punctuation so the flanking check passes via rule (2a).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;

import 'test_helpers.dart';

/// Parse markdown to HTML using the same extension set as the app
/// (gitHubFlavored) for direct assertion on parser output.
String parseToHtml(String input) {
  final doc = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
  final nodes = doc.parseLines(input.split('\n'));
  return md.renderToHtml(nodes);
}

/// Same, but applies the ZWSP flanking fix first (simulating the app pipeline).
String parseWithFix(String input) {
  // Reproduce the fix logic from _fixEmphasisFlanking / _insertFlankingZwsp.
  final afterStars = RegExp(r'(\*+)(?!\*)(?=\p{P})', unicode: true);
  final beforeStars = RegExp(r'(?<=\p{P})(?<!\*)(\*+)', unicode: true);
  var text = input;
  text = text.replaceAllMapped(afterStars, (m) => '${m[1]}\u200B');
  text = text.replaceAllMapped(beforeStars, (m) => '\u200B${m[1]}');
  return parseToHtml(text);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // ---------------------------------------------------------------------------
  // Core bug: CJK + punctuation breaks ** flanking rules (without fix)
  // ---------------------------------------------------------------------------
  group('CJK + punctuation flanking bug (raw parser, no fix)', () {
    test('CJK**"text"**CJK — smart quotes break bold without fix', () {
      final html = parseToHtml('这是**\u201C重要\u201D**的内容');
      expect(html, isNot(contains('<strong>')),
          reason: '** fails to open when followed by smart quote after CJK');
    });

    test('CJK**"text"**CJK — ASCII quotes also break bold without fix', () {
      final html = parseToHtml('这是**"重要"**的内容');
      expect(html, isNot(contains('<strong>')));
    });

    test('CJK**（text）**CJK — fullwidth parens break bold without fix', () {
      final html = parseToHtml('这是**（重要）**的内容');
      expect(html, isNot(contains('<strong>')));
    });

    test('CJK**《text》**CJK — angle brackets break bold without fix', () {
      final html = parseToHtml('这是**《重要》**的内容');
      expect(html, isNot(contains('<strong>')));
    });
  });

  // ---------------------------------------------------------------------------
  // ZWSP fix makes CJK + punctuation bold work
  // ---------------------------------------------------------------------------
  group('ZWSP flanking fix', () {
    test('CJK**"text"**CJK — smart quotes fixed', () {
      final html = parseWithFix('这是**\u201C重要\u201D**的内容');
      expect(html, contains('<strong>'));
    });

    test('CJK**"text"**CJK — ASCII quotes fixed', () {
      final html = parseWithFix('这是**"重要"**的内容');
      expect(html, contains('<strong>'));
    });

    test('CJK**（text）**CJK — fullwidth parens fixed', () {
      final html = parseWithFix('这是**（重要）**的内容');
      expect(html, contains('<strong>'));
    });

    test('CJK**《text》**CJK — angle brackets fixed', () {
      final html = parseWithFix('这是**《重要》**的内容');
      expect(html, contains('<strong>'));
    });

    test('CJK**(text)**CJK — ASCII parens fixed', () {
      final html = parseWithFix('这是**(重要)**的内容');
      expect(html, contains('<strong>'));
    });

    test('CJK**text**CJK — no quotes still works', () {
      final html = parseWithFix('这是**重要**的内容');
      expect(html, contains('<strong>重要</strong>'));
    });

    test('space **"text"** space — still works', () {
      final html = parseWithFix('这是 **\u201C重要\u201D** 的内容');
      expect(html, contains('<strong>'));
    });

    test('exact bug from test.txt — correct text is now bolded', () {
      final html = parseWithFix(
        '越南目前处于一种**\u201C极度渴望 AI 化\u201D**的状态。'
        '它虽然没有基础算法研究能力，但其**应用层**和**本土化**动作非常迅速。',
      );
      // With fix: all three bold sections render correctly
      expect(html, isNot(contains('<strong>的状态')),
          reason: 'Wrong text should no longer be bolded');
      expect(html, contains('<strong>应用层</strong>'));
      expect(html, contains('<strong>本土化</strong>'));
    });

    test('multiple CJK bold sections with quotes — all correct', () {
      final html = parseWithFix('**\u201C第一\u201D**和**第二**和**\u201C第三\u201D**结束');
      expect(html, contains('<strong>'));
      expect(html, contains('第二'));
    });

    test('CJK bold with quotes followed by plain CJK bold — no cascade', () {
      final html = parseWithFix('加拿大面临严重的**\u201C人才流失\u201D**。目前正试图**加强**转化。');
      expect(html, contains('<strong>加强</strong>'));
    });

    test('fix does not break bold in code blocks', () {
      final afterStars = RegExp(r'(\*+)(?!\*)(?=\p{P})', unicode: true);
      final beforeStars = RegExp(r'(?<=\p{P})(?<!\*)(\*+)', unicode: true);
      const input = '```python\nx = 2**3\n```\n\n**bold**';
      var text = input;
      text = text.replaceAllMapped(afterStars, (m) => '${m[1]}\u200B');
      text = text.replaceAllMapped(beforeStars, (m) => '\u200B${m[1]}');
      // The ** inside code block should not get ZWSP because _fixEmphasisFlanking
      // skips code blocks. Here we test the raw regex on full text (including code),
      // which WILL insert ZWSP — but the code block content is preserved by the
      // markdown parser regardless. The actual app skips code blocks.
      final html = parseToHtml(text);
      expect(html, contains('<strong>bold</strong>'));
    });

    test('fix is idempotent — double application does not add extra ZWSP', () {
      const input = '这是**\u201C重要\u201D**的内容';
      final once = parseWithFix(input);
      // Apply fix twice by running parseWithFix on already-fixed text
      final afterStars = RegExp(r'(\*+)(?!\*)(?=\p{P})', unicode: true);
      final beforeStars = RegExp(r'(?<=\p{P})(?<!\*)(\*+)', unicode: true);
      var text = input;
      // First pass
      text = text.replaceAllMapped(afterStars, (m) => '${m[1]}\u200B');
      text = text.replaceAllMapped(beforeStars, (m) => '\u200B${m[1]}');
      // Second pass
      text = text.replaceAllMapped(afterStars, (m) => '${m[1]}\u200B');
      text = text.replaceAllMapped(beforeStars, (m) => '\u200B${m[1]}');
      final twice = parseToHtml(text);
      expect(twice, equals(once));
    });

    test('fix does not affect non-emphasis asterisks', () {
      // x*y should not get ZWSP (no punct adjacent)
      final html = parseWithFix(r'compute x*y here');
      expect(html, contains('x*y'));
    });

    test('italic with CJK quotes also fixed', () {
      final html = parseWithFix('这是*\u201C重要\u201D*的内容');
      expect(html, contains('<em>'));
    });

    test('bold-italic with CJK quotes also fixed', () {
      final html = parseWithFix('这是***\u201C重要\u201D***的内容');
      expect(html, allOf(contains('<strong>'), contains('<em>')));
    });
  });

  // ---------------------------------------------------------------------------
  // ** flanking rule edge cases (non-CJK)
  // ---------------------------------------------------------------------------
  group('flanking rule edge cases', () {
    test('letter**"text"**letter — also fixed by ZWSP', () {
      final html = parseWithFix('word**"text"**word');
      expect(html, contains('<strong>'));
    });

    test('punct**text**punct — still works with fix', () {
      final html = parseWithFix('.**text**.');
      expect(html, contains('<strong>text</strong>'));
    });

    test('** text** — space after opening still prevents bold', () {
      final html = parseWithFix('** text**');
      expect(html, isNot(contains('<strong>')),
          reason: 'Space after ** means not left-flanking');
    });

    test('**text ** — space before closing still prevents bold', () {
      final html = parseWithFix('**text **');
      expect(html, isNot(contains('<strong>')),
          reason: 'Space before ** means not right-flanking');
    });

    test('adjacent **a****b** — parsed as one large bold', () {
      final html = parseWithFix('**a****b**');
      expect(html, contains('<strong>'));
    });
  });

  // ---------------------------------------------------------------------------
  // Basic bold sanity checks (should all pass)
  // ---------------------------------------------------------------------------
  group('basic bold parsing', () {
    test('simple bold', () {
      expect(parseToHtml('**hello**'), contains('<strong>hello</strong>'));
    });

    test('bold in sentence', () {
      final html = parseToHtml('some **bold** text');
      expect(html, contains('<strong>bold</strong>'));
    });

    test('multiple bold sections', () {
      final html = parseToHtml('**a** and **b** and **c**');
      expect(html, allOf(
        contains('<strong>a</strong>'),
        contains('<strong>b</strong>'),
        contains('<strong>c</strong>'),
      ));
    });

    test('bold with colon (common model pattern)', () {
      final html = parseToHtml('**Step 1:** Do something');
      expect(html, contains('<strong>Step 1:</strong>'));
    });

    test('bold across soft line break', () {
      final html = parseToHtml('**hello\nworld**');
      expect(html, contains('<strong>'));
    });

    test('bold with italic', () {
      final html = parseToHtml('**bold** and *italic*');
      expect(html, allOf(
        contains('<strong>bold</strong>'),
        contains('<em>italic</em>'),
      ));
    });

    test('bold-italic (triple star)', () {
      final html = parseToHtml('***both***');
      expect(html, allOf(contains('<strong>'), contains('<em>')));
    });
  });

  // ---------------------------------------------------------------------------
  // Streaming truncation — ** cut mid-closing
  // ---------------------------------------------------------------------------
  group('streaming truncation edge cases', () {
    test('unclosed ** shows literal markers', () {
      final html = parseToHtml('**hello');
      // No matching closer → literal **
      expect(html, isNot(contains('<strong>')));
      expect(html, contains('**hello'));
    });

    test('**text* (one star of closing pair) becomes italic (KNOWN BUG)', () {
      final html = parseToHtml('**bold*');
      // BUG: Parser interprets ** as * + *, matches the trailing *
      // as a closer for the second *, creating <em> instead of literal **
      expect(html, contains('<em>bold</em>'),
          reason: 'Streaming truncation at one * creates spurious italic');
      expect(html, contains('*'),
          reason: 'Stray * appears as literal text');
    });

    test('**first** and **sec* — second section becomes italic', () {
      final html = parseToHtml('**first** and **sec*');
      expect(html, contains('<strong>first</strong>'),
          reason: 'First bold section is correct');
      expect(html, contains('<em>sec</em>'),
          reason: 'Truncated second section becomes italic');
    });

    test('closed bold followed by unclosed ** is harmless', () {
      final html = parseToHtml('**first** and **open');
      expect(html, contains('<strong>first</strong>'));
      expect(html, contains('**open'),
          reason: 'Unclosed ** shown as literal');
    });
  });

  // ---------------------------------------------------------------------------
  // Widget-level rendering tests (no crash, correct error handling)
  // ---------------------------------------------------------------------------
  group('bold rendering widget tests', () {
    testWidgets('CJK bold with smart quotes renders without crash', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '越南目前处于一种**\u201C极度渴望 AI 化\u201D**的状态。'
        '它虽然没有基础算法研究能力，但其**应用层**和**本土化**动作非常迅速。',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('CJK bold with fullwidth parens renders without crash', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '这是**（重要内容）**的部分',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('CJK bold with angle brackets renders without crash', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '请参阅**《用户手册》**了解更多',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('multiple CJK bold sections with mixed quotes', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '加拿大面临严重的**\u201C人才流失\u201D**。由于缺乏风投资本，'
        '很多技术最终在硅谷被**商业化**。目前正试图通过**国家战略**加强转化。',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('real model output with bold labels and LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| 国家 | 角色定位 |\n| :--- | :--- |\n'
        '| **加拿大** | 理论灯塔 |\n'
        '| **越南** | 应用追随者 |\n',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('streaming truncation: bold cut at one star', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(tester, '**bold*');
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('sequential bold sections', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '**one** **two** **three**',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('bold wrapping LaTeX expression', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'**The formula $E = mc^2$ is key.**',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });
  });
}
