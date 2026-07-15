import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'test_helpers.dart';

String _renderedText(WidgetTester tester) {
  final textWidgets = tester.widgetList<Text>(find.byType(Text)).map(
        (widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '',
      );
  final richTextWidgets = tester.widgetList<RichText>(find.byType(RichText)).map(
        (widget) => widget.text.toPlainText(),
      );
  return {...textWidgets, ...richTextWidgets}.where((value) => value.isNotEmpty).join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('unclosed display math keeps following prose readable', (
    tester,
  ) async {
    await pumpBubbleAndCollectErrors(
      tester,
      '\$\$\n'
      'x = 1\n'
      'Following explanation must remain readable.',
    );

    expect(
      _renderedText(tester),
      contains('Following explanation must remain readable.'),
    );
    expect(find.byType(Math), findsNothing);
  });

  testWidgets('unclosed display math cannot consume a later inline display', (
    tester,
  ) async {
    await pumpBubbleAndCollectErrors(
      tester,
      '\$\$\n'
      'unfinished\n'
      'Following explanation remains readable with \$\$x^2\$\$ inline.',
    );

    final rendered = _renderedText(tester);
    expect(rendered, contains(r'$$'));
    expect(
      rendered,
      contains('Following explanation remains readable with'),
    );
  });

  testWidgets('standalone dollar line remains literal', (tester) async {
    await pumpBubbleAndCollectErrors(
      tester,
      'Currency symbol:\n'
      '\$\n'
      'Following explanation must remain readable.',
    );

    final rendered = _renderedText(tester);
    expect(rendered, contains(r'$'));
    expect(rendered, contains('Following explanation must remain readable.'));
  });

  testWidgets('standalone dollar line cannot consume later inline math', (
    tester,
  ) async {
    await pumpBubbleAndCollectErrors(
      tester,
      'Currency symbol:\n'
      '\$\n'
      r'Following formula is $x^2$.',
    );

    final rendered = _renderedText(tester);
    expect(rendered, contains(r'$'));
    expect(rendered, contains('Following formula is'));
    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('currency before math preserves the formula', (tester) async {
    await pumpBubbleAndCollectErrors(
      tester,
      r'The plan costs $5 and formula is $x^2$.',
    );

    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('bare latex fence renders as math', (tester) async {
    await pumpBubbleAndCollectErrors(
      tester,
      '```latex\n'
      r'\frac{a}{b}'
      '\n```',
    );

    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('code fences keep literal Markdown and LaTeX source', (
    tester,
  ) async {
    await pumpBubbleAndCollectErrors(
      tester,
      '```text\n'
      r'$[ref](https://example.com)$'
      '\n'
      r'| $|x|$ |'
      '\n```',
    );

    final rendered = _renderedText(tester);
    expect(rendered, contains(r'$[ref](https://example.com)$'));
    expect(rendered, contains(r'| $|x|$ |'));
    expect(find.byType(Math), findsNothing);
  });

  testWidgets('balanced-parenthesis wrapped link remains clickable', (
    tester,
  ) async {
    final errors = await pumpBubbleAndCollectErrors(
      tester,
      r'$[reference](https://en.wikipedia.org/wiki/Foo_(bar))$',
    );

    expect(overflowErrors(errors), isEmpty);
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_LinkFavicon',
      ),
      findsOneWidget,
    );
    expect(find.byType(Math), findsNothing);
  });

  testWidgets('table without edge pipes preserves absolute-value math', (
    tester,
  ) async {
    await pumpBubbleAndCollectErrors(
      tester,
      'Formula | Meaning\n'
      '--- | ---\n'
      r'$|x|$ | absolute value',
    );

    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('blockquote table preserves absolute-value math', (
    tester,
  ) async {
    await pumpBubbleAndCollectErrors(
      tester,
      '> | Formula |\n'
      '> | --- |\n'
      r'> | $|x|$ |',
    );

    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(Math), findsOneWidget);
  });
}
