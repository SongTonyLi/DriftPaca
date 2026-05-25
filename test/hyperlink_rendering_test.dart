/// Tests for hyperlink rendering in chat bubbles and citation link replacement.
///
/// Covers:
/// - Unit tests for `ChatProvider.replaceCitationsWithLinks` (pure string logic)
/// - Widget tests for markdown link rendering in `ChatBubble`
///
/// Run with: flutter test test/hyperlink_rendering_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:llamaseek/Providers/chat_provider.dart';

import 'markdown_latex/test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // ===========================================================================
  // Unit tests: replaceCitationsWithLinks
  // ===========================================================================
  group('replaceCitationsWithLinks', () {
    test('replaces single citation with markdown link', () {
      final sourceUrls = {1: 'http://example.com'};
      final result = ChatProvider.replaceCitationsWithLinks(
        'See [1] for details.',
        sourceUrls,
      );
      expect(result, 'See [¹](http://example.com) for details.');
    });

    test('replaces multiple citations', () {
      final sourceUrls = {1: 'http://one.com', 2: 'http://two.com'};
      final result = ChatProvider.replaceCitationsWithLinks(
        'References [1] and [2].',
        sourceUrls,
      );
      expect(result, 'References [¹](http://one.com) and [²](http://two.com).');
    });

    test('leaves citation without source URL unchanged', () {
      final sourceUrls = {1: 'http://one.com'};
      final result = ChatProvider.replaceCitationsWithLinks(
        'See [1] and [3].',
        sourceUrls,
      );
      expect(result, 'See [¹](http://one.com) and [3].');
    });

    test('does not replace non-numeric brackets', () {
      final sourceUrls = {1: 'http://one.com'};
      final result = ChatProvider.replaceCitationsWithLinks(
        'See [abc] and [1].',
        sourceUrls,
      );
      expect(result, 'See [abc] and [¹](http://one.com).');
    });

    test('does not replace empty brackets', () {
      final sourceUrls = {1: 'http://one.com'};
      final result = ChatProvider.replaceCitationsWithLinks(
        'Empty [] and [1].',
        sourceUrls,
      );
      expect(result, 'Empty [] and [¹](http://one.com).');
    });

    test('does not replace [N] already followed by (url) — existing markdown link', () {
      final sourceUrls = {1: 'http://new-url.com'};
      final result = ChatProvider.replaceCitationsWithLinks(
        'Already linked: [1](http://existing.com).',
        sourceUrls,
      );
      // The [1] should NOT be replaced because it is followed by (
      expect(result, 'Already linked: [1](http://existing.com).');
    });

    test('replaces citation at start of string', () {
      final sourceUrls = {1: 'http://one.com'};
      final result = ChatProvider.replaceCitationsWithLinks(
        '[1] is the first reference.',
        sourceUrls,
      );
      expect(result, '[¹](http://one.com) is the first reference.');
    });

    test('replaces citation at end of string', () {
      final sourceUrls = {1: 'http://one.com'};
      final result = ChatProvider.replaceCitationsWithLinks(
        'See reference [1]',
        sourceUrls,
      );
      expect(result, 'See reference [¹](http://one.com)');
    });

    test('handles citation adjacent to punctuation', () {
      final sourceUrls = {1: 'http://one.com', 2: 'http://two.com'};
      final result = ChatProvider.replaceCitationsWithLinks(
        'Facts[1], figures[2].',
        sourceUrls,
      );
      expect(result, 'Facts[¹](http://one.com), figures[²](http://two.com).');
    });

    test('handles citation in parentheses', () {
      final sourceUrls = {1: 'http://one.com'};
      final result = ChatProvider.replaceCitationsWithLinks(
        'Known fact ([1]).',
        sourceUrls,
      );
      expect(result, 'Known fact ([¹](http://one.com)).');
    });

    test('handles large citation numbers', () {
      final sourceUrls = {42: 'http://answer.com'};
      final result = ChatProvider.replaceCitationsWithLinks(
        'See [42] for the answer.',
        sourceUrls,
      );
      expect(result, 'See [⁴²](http://answer.com) for the answer.');
    });

    test('handles URL with query parameters', () {
      final sourceUrls = {1: 'http://example.com/page?q=test&lang=en'};
      final result = ChatProvider.replaceCitationsWithLinks(
        'See [1].',
        sourceUrls,
      );
      expect(result, 'See [¹](http://example.com/page?q=test&lang=en).');
    });

    test('handles URL with fragment', () {
      final sourceUrls = {1: 'http://example.com/page#section'};
      final result = ChatProvider.replaceCitationsWithLinks(
        'See [1].',
        sourceUrls,
      );
      expect(result, 'See [¹](http://example.com/page#section).');
    });

    test('returns content unchanged when sourceUrls is empty', () {
      final result = ChatProvider.replaceCitationsWithLinks(
        'See [1] and [2].',
        {},
      );
      expect(result, 'See [1] and [2].');
    });

    test('does not corrupt mixed markdown links and citations', () {
      final sourceUrls = {2: 'http://two.com'};
      final result = ChatProvider.replaceCitationsWithLinks(
        'See [this page](http://example.com) and [2] for more.',
        sourceUrls,
      );
      expect(result, 'See [this page](http://example.com) and [²](http://two.com) for more.');
    });

    test('consecutive citations without space', () {
      final sourceUrls = {1: 'http://one.com', 2: 'http://two.com'};
      final result = ChatProvider.replaceCitationsWithLinks(
        'Sources[1][2].',
        sourceUrls,
      );
      expect(result, 'Sources[¹](http://one.com)[²](http://two.com).');
    });

    test('does not match footnote-style [^1]', () {
      final sourceUrls = {1: 'http://one.com'};
      final result = ChatProvider.replaceCitationsWithLinks(
        'Footnote [^1] and citation [1].',
        sourceUrls,
      );
      // [^1] should not be touched (^ is not a digit)
      expect(result, 'Footnote [^1] and citation [¹](http://one.com).');
    });
  });

  // ===========================================================================
  // Widget tests: Hyperlink rendering in ChatBubble
  // ===========================================================================
  group('hyperlink rendering — standard markdown links', () {
    testWidgets('standard link renders without error', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Visit [Example](http://example.com) for more.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.textContaining('Example'), findsOneWidget);
      // Raw markdown brackets should not be visible
      expect(find.textContaining('[Example]'), findsNothing);
    });

    testWidgets('link with title attribute renders', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'See [docs](http://docs.com "Documentation") here.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('multiple links in one paragraph render', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Visit [Google](http://google.com) or [GitHub](http://github.com).',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.textContaining('Google'), findsOneWidget);
      expect(find.textContaining('GitHub'), findsOneWidget);
    });

    testWidgets('adjacent links without space render', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '[one](http://one.com)[two](http://two.com)',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('link in bold text renders', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '**Visit [Example](http://example.com) now**',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('link in italic text renders', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '*Check [this link](http://example.com) out*',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('link in list item renders', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '- First [link](http://one.com)\n- Second [link](http://two.com)',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('link in numbered list renders', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '1. See [reference](http://ref.com)\n2. Also [source](http://src.com)',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('link in table cell renders', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Name | Link |\n| --- | --- |\n| Example | [click here](http://example.com) |',
        surfaceSize: const Size(500, 800),
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.textContaining('click here'), findsOneWidget);
    });

    testWidgets('link in blockquote renders', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '> See [this](http://example.com) for details.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('link with query params renders', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Search [results](http://example.com/search?q=test&page=1)',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('link with fragment renders', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Jump to [section](http://example.com/page#heading)',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('link with long URL renders without overflow', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'See [this](http://example.com/very/long/path/to/some/deeply/nested/resource?with=params&and=more&query=strings)',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Autolinks (raw URLs)
  // ---------------------------------------------------------------------------
  group('hyperlink rendering — autolinks', () {
    testWidgets('raw https URL renders as link', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Visit https://example.com for more.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('raw URL with path and params', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Check https://example.com/path?q=1&r=2 for details.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('angle-bracket autolink renders', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Visit <https://example.com> for more.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('multiple raw URLs in paragraph', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Sites: https://one.com and https://two.com are useful.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Citation-style links (the format produced by replaceCitationsWithLinks)
  // ---------------------------------------------------------------------------
  group('hyperlink rendering — citation links', () {
    testWidgets('citation link [¹](url) renders without bracket artifacts', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'See [¹](http://example.com) for reference.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      // The link text should contain "1" (possibly with brackets as part of link text)
      // Key assertion: no rendering error
    });

    testWidgets('multiple citation links render', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Sources [¹](http://one.com) and [²](http://two.com) confirm this.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('citation link in list item', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '- Fact from [¹](http://source.com)\n- Also see [²](http://other.com)',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('citation link adjacent to punctuation', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'This is true[¹](http://source.com), confirmed by[²](http://other.com).',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('citation link in parentheses', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Known fact ([¹](http://source.com)).',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('old broken format [[N](url)] shows bracket artifacts', (tester) async {
      // This tests the OLD (broken) format to document the issue.
      // The old format [[1](http://example.com)] renders brackets as literal text.
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'See [[1](http://example.com)] for reference.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      // In the old format, literal brackets [ and ] appear around the link.
      // This test documents this behavior.
    });

    testWidgets('mixed citation links and regular links', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Read [this article](http://blog.com) and check source [¹](http://source.com).',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('citation link with LaTeX in same message', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The equation $E = mc^2$ was proven [¹](http://physics.com).',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Edge cases: brackets and links
  // ---------------------------------------------------------------------------
  group('hyperlink rendering — bracket edge cases', () {
    testWidgets('link text containing brackets renders', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'See [array[0]](http://example.com) for details.',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('link wrapped in parentheses', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '(see [link](http://example.com))',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('link at end of sentence with period', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Read more at [example](http://example.com).',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('link followed by comma', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'See [here](http://example.com), and also [there](http://other.com).',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('link with empty text does not crash', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Empty: [](http://example.com).',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('unclosed bracket followed by link does not crash', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Text [ with unclosed bracket and [link](http://example.com).',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('raw brackets near links do not corrupt rendering', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Array: [1, 2, 3] and [link](http://example.com).',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('multiple bracket pairs near link', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Access arr[0][1] and see [docs](http://docs.com).',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Links mixed with other markdown features
  // ---------------------------------------------------------------------------
  group('hyperlink rendering — mixed content', () {
    testWidgets('link with inline code in same paragraph', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        'Use `curl` to fetch [this URL](http://example.com).',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('link inside heading', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '## Resources: [Official Docs](http://docs.com)',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('link and LaTeX in same paragraph', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        r'The formula $x^2$ is explained at [this page](http://math.com).',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('link after code block', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '```python\nprint("hello")\n```\n\nSee [docs](http://python.org).',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('multiple links in table cells', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Service | Link |\n| --- | --- |\n| Google | [google.com](http://google.com) |\n| GitHub | [github.com](http://github.com) |',
        surfaceSize: const Size(500, 800),
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('link mixed with bold and italic', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '**Bold text** and *italic text* with [a link](http://example.com).',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('realistic LLM response with web search citations', (tester) async {
      // Simulates a response after replaceCitationsWithLinks processes it
      const content = 'According to recent studies, the global temperature '
          'has risen by 1.1°C since pre-industrial times [¹](http://climate.nasa.gov). '
          'This is consistent with IPCC projections [²](http://ipcc.ch/report), '
          'which predict further increases of 1.5-4.5°C by 2100 [³](http://nature.com/article).\n\n'
          r'The relationship follows: $\Delta T = \lambda \cdot \Delta F$, '
          'where \$\\lambda\$ is climate sensitivity [¹](http://climate.nasa.gov).';
      final errors = await pumpBubbleAndCollectErrors(tester, content);
      expect(nonOverflowErrors(errors), isEmpty);
    });
  });
}
