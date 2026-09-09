import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Widgets/clarification_card.dart';

void main() {
  Widget host(ClarificationSegment segment,
          {void Function(List<String>)? onAnswer}) =>
      MaterialApp(
        home: Scaffold(
          body: ClarificationCard(segment: segment, onAnswer: onAnswer),
        ),
      );

  ClarificationSegment open() => ClarificationSegment(
        question: 'Which Mercury?',
        options: const ['The planet', 'The company', 'The team'],
      );

  testWidgets('Continue is disabled until something is picked, then hands back the picks in option order',
      (tester) async {
    List<String>? answer;
    await tester.pumpWidget(host(open(), onAnswer: (s) => answer = s));

    final continueButton = find.widgetWithText(FilledButton, 'Continue');
    expect(tester.widget<FilledButton>(continueButton).enabled, isFalse);

    // Picked in reverse order on purpose.
    await tester.tap(find.text('The team'));
    await tester.pump();
    await tester.tap(find.text('The planet'));
    await tester.pump();
    expect(tester.widget<FilledButton>(continueButton).enabled, isTrue);

    await tester.tap(continueButton);
    await tester.pump();

    expect(answer, ['The planet', 'The team']);
  });

  testWidgets('a checkbox tapped twice is unpicked again', (tester) async {
    List<String>? answer;
    await tester.pumpWidget(host(open(), onAnswer: (s) => answer = s));

    await tester.tap(find.text('The company'));
    await tester.pump();
    await tester.tap(find.text('The company'));
    await tester.pump();

    expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue')).enabled,
        isFalse);
    expect(answer, isNull);
  });

  testWidgets('Skip answers with nothing picked', (tester) async {
    List<String>? answer;
    await tester.pumpWidget(host(open(), onAnswer: (s) => answer = s));

    await tester.tap(find.text('The planet'));
    await tester.pump();
    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(answer, isEmpty, reason: 'a skip discards any half-made picks');
  });

  testWidgets('an answered card is a record: picks shown, no form controls',
      (tester) async {
    final segment = ClarificationSegment(
      question: 'Which Mercury?',
      options: const ['The planet', 'The team'],
      selected: const ['The team'],
    );
    await tester.pumpWidget(host(segment, onAnswer: (_) => fail('read-only')));

    expect(find.text('Clarified'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Skip'), findsNothing);
    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(boxes.map((b) => b.value), [false, true]);
    expect(boxes.every((b) => b.onChanged == null), isTrue);

    // Tapping does nothing — no run to resume.
    await tester.tap(find.text('The planet'));
    await tester.pump();
  });

  group('typing an answer of your own', () {
    testWidgets('typed text enables Continue on its own and travels as the answer',
        (tester) async {
      List<String>? answer;
      await tester.pumpWidget(host(open(), onAnswer: (s) => answer = s));
      final continueButton = find.widgetWithText(FilledButton, 'Continue');
      expect(tester.widget<FilledButton>(continueButton).enabled, isFalse);

      await tester.enterText(find.byType(TextField), '  the Freddie one  ');
      await tester.pump();
      expect(tester.widget<FilledButton>(continueButton).enabled, isTrue,
          reason: 'an answer in the user\'s own words is an answer');

      await tester.tap(continueButton);
      await tester.pump();
      expect(answer, ['the Freddie one'], reason: 'trimmed, and nothing else');
    });

    testWidgets('typed text follows the ticked options, in option order',
        (tester) async {
      List<String>? answer;
      await tester.pumpWidget(host(open(), onAnswer: (s) => answer = s));

      await tester.enterText(find.byType(TextField), 'also the ship');
      await tester.tap(find.text('The team'));
      await tester.tap(find.text('The planet'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pump();

      expect(answer, ['The planet', 'The team', 'also the ship']);
    });

    testWidgets('whitespace alone is not an answer', (tester) async {
      List<String>? answer;
      await tester.pumpWidget(host(open(), onAnswer: (s) => answer = s));

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
              .enabled,
          isFalse);
      // Submitting from the keyboard is guarded the same way.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(answer, isNull);
    });

    testWidgets('the keyboard\'s done action submits like Continue', (tester) async {
      List<String>? answer;
      await tester.pumpWidget(host(open(), onAnswer: (s) => answer = s));

      await tester.enterText(find.byType(TextField), 'the element');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(answer, ['the element']);
    });

    testWidgets('an answered card shows the typed answer as part of the record',
        (tester) async {
      // A reloaded card has one list of strings; the typed answer is the
      // entry that is not one of the options.
      final segment = ClarificationSegment(
        question: 'Which Mercury?',
        options: const ['The planet', 'The team'],
        selected: const ['The team', 'the Freddie one'],
      );
      await tester.pumpWidget(host(segment, onAnswer: (_) => fail('read-only')));

      expect(find.text('Clarified'), findsOneWidget);
      expect(find.text('the Freddie one'), findsOneWidget);
      expect(find.byType(TextField), findsNothing,
          reason: 'no field to type into once the run has moved on');
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
      final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
      expect(boxes.map((b) => b.value), [false, true]);
    });

    test('typedAnswers is whatever the answer holds beyond the options', () {
      expect(
          ClarificationCard.typedAnswers(
              const ['The team', 'the Freddie one'], const ['The planet', 'The team']),
          ['the Freddie one']);
      expect(ClarificationCard.typedAnswers(const ['The team'], const ['The team']),
          isEmpty);
      expect(ClarificationCard.typedAnswers(const [], const ['The team']), isEmpty);
    });
  });

  testWidgets('a card with no run to resume waits instead of offering a form',
      (tester) async {
    await tester.pumpWidget(host(open()));

    expect(find.text('Continue'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Waiting'), findsOneWidget);
  });
}
