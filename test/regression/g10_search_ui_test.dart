import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_think_block.dart';
import 'package:llamaseek/Widgets/search_card.dart';
import 'package:llamaseek/Widgets/search_detail_dialog.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('search source preview truncation', () {
    testWidgets('does not split a surrogate pair at the boundary',
        (tester) async {
      // 299 ASCII characters followed by an astral-plane emoji so that the
      // emoji straddles the 300th UTF-16 code unit.
      final content = '${'a' * 299}😀${'b' * 100}';
      final segment = SearchCardSegment(
        query: 'q',
        isComplete: true,
        resultCount: 1,
        sources: [
          SearchSource(
            url: 'https://example.com',
            domain: 'example.com',
            title: '',
            content: content,
          ),
        ],
      );

      await tester.pumpWidget(_host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => SearchDetailDialog.show(context, segment),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final preview = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .firstWhere((s) => s.startsWith('aaa'));

      expect(preview.runes.contains(0xFFFD), isFalse);
      expect(preview.codeUnits.any((u) => u >= 0xD800 && u <= 0xDBFF),
          isTrue,
          reason: 'the emoji should be kept intact, not split');
      expect(preview.endsWith('…'), isTrue);

      // Dismiss so the shared open-guard resets for later tests.
      Navigator.of(tester.element(find.text('open'))).pop();
      await tester.pumpAndSettle();
    });
  });

  group('SearchDetailDialog.show', () {
    testWidgets('two calls in one frame open only one bottom sheet',
        (tester) async {
      final segment = SearchCardSegment(
        query: 'flutter',
        isComplete: true,
        resultCount: 2,
      );

      await tester.pumpWidget(_host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () {
              SearchDetailDialog.show(context, segment);
              SearchDetailDialog.show(context, segment);
            },
            child: const Text('open'),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(SearchDetailDialog), findsOneWidget);

      Navigator.of(tester.element(find.text('open'))).pop();
      await tester.pumpAndSettle();
    });
  });

  group('ThinkBlockParser.tryParse', () {
    test('closes at the final </think>, not one mentioned in reasoning', () {
      const content =
          '<think>The user asked about the </think> tag in markup.</think>'
          'Here is the answer.';

      final parsed = ThinkBlockParser.tryParse(content);

      expect(parsed, isNotNull);
      expect(parsed!.isThinkingComplete, isTrue);
      expect(parsed.thinkContent,
          'The user asked about the </think> tag in markup.');
      expect(parsed.responseContent, 'Here is the answer.');
    });
  });

  group('SearchCard result count label', () {
    testWidgets('uses the singular for a single source', (tester) async {
      final segment = SearchCardSegment(
        query: 'q',
        isComplete: true,
        resultCount: 1,
      );
      await tester.pumpWidget(_host(SearchCard(segment: segment)));
      await tester.pumpAndSettle();

      expect(find.text('1 source'), findsOneWidget);
      expect(find.text('1 sources'), findsNothing);
    });

    testWidgets('uses the plural for multiple sources', (tester) async {
      final segment = SearchCardSegment(
        query: 'q',
        isComplete: true,
        resultCount: 3,
      );
      await tester.pumpWidget(_host(SearchCard(segment: segment)));
      await tester.pumpAndSettle();

      expect(find.text('3 sources'), findsOneWidget);
    });
  });
}
