import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Utils/research_goal.dart';

void main() {
  group('parseResearchGoal', () {
    test('reads the GOAL line and its bullets', () {
      final goal = parseResearchGoal('''
GOAL: Establish when TikTok typically opens new-grad offer negotiations
- TikTok new grad offer negotiation timing
- TikTok recruiter outreach schedule
''');

      expect(goal!.statement,
          'Establish when TikTok typically opens new-grad offer negotiations');
      expect(goal.subQuestions, [
        'TikTok new grad offer negotiation timing',
        'TikTok recruiter outreach schedule',
      ]);
    });

    test('accepts a bare statement with no GOAL prefix', () {
      // The prompt asks for the prefix but nothing enforces it, and
      // discarding an otherwise-usable brief over a missing label would
      // cost the run its goal for no reason. This is a FALLBACK for a reply
      // that never labels its goal, not a competitor to the label — see
      // 'a GOAL line outranks a prose preamble above it' below.
      final goal = parseResearchGoal('Find Vietnam\'s 2024 GDP\n* GDP 2024');

      expect(goal!.statement, "Find Vietnam's 2024 GDP");
      expect(goal.subQuestions, ['GDP 2024']);
    });

    test('reads a CLARIFY question and its checkbox options', () {
      final goal = parseResearchGoal('''
GOAL: Find the latest results for Mercury
- Mercury latest results
CLARIFY: Which Mercury do you mean?
[ ] The planet
[ ] Mercury Systems, the company
[ ] The Phoenix Mercury basketball team
''');

      expect(goal!.subQuestions, ['Mercury latest results']);
      expect(goal.clarification!.question, 'Which Mercury do you mean?');
      expect(goal.clarification!.options, [
        'The planet',
        'Mercury Systems, the company',
        'The Phoenix Mercury basketball team',
      ]);
    });

    test('bullets after CLARIFY are options, never sub-questions', () {
      // A model that writes its options as plain bullets has still written
      // options; reading them as checklist items would seed a search for
      // each reading of an ambiguous word.
      final goal = parseResearchGoal('''
GOAL: Find the current Jaguar lineup
CLARIFY: Which Jaguar?
- The car maker
- The animal
''');

      expect(goal!.subQuestions, isEmpty);
      expect(goal.clarification!.options, ['The car maker', 'The animal']);
    });

    test('drops a clarification with fewer than two options', () {
      // One option is not a choice, and a card with nothing to pick from
      // would only stall the run.
      final goal = parseResearchGoal('''
GOAL: Find X
CLARIFY: Did you mean Y?
[ ] Y
''');

      expect(goal!.clarification, isNull);
    });

    test('caps the options and keeps the goal parse otherwise intact', () {
      final goal = parseResearchGoal('''
GOAL: Find X
CLARIFY: Which?
[ ] a
[ ] b
[ ] c
[ ] d
[ ] e
[ ] f
''');

      expect(goal!.statement, 'Find X');
      expect(goal.clarification!.options, hasLength(maxClarificationOptions));
    });

    test('keeps a single-lookup question free of sub-questions', () {
      // Every bullet becomes an item the stopping rule then obliges the
      // model to close, so an empty list is the good outcome here, not a
      // degraded one.
      final goal = parseResearchGoal('GOAL: Find the current price of gold');

      expect(goal!.statement, 'Find the current price of gold');
      expect(goal.subQuestions, isEmpty);
    });

    test('ignores bullets written before any goal statement', () {
      final goal = parseResearchGoal('''
- some preamble the model invented
GOAL: Find the current price of gold
- gold spot price today
''');

      expect(goal!.statement, 'Find the current price of gold');
      expect(goal.subQuestions, ['gold spot price today']);
    });

    test('a GOAL line outranks a prose preamble above it', () {
      // The derivation prompt says "No preamble, no explanation, no closing
      // remarks", and a chatty model writes one anyway. Read first-match,
      // that courtesy line became the run's objective and the real goal was
      // discarded; the label now wins wherever it appears.
      final goal = parseResearchGoal('''
Sure! Here is the research brief:
GOAL: Find the current price of gold
- gold spot price today
''');

      expect(goal!.statement, 'Find the current price of gold');
      expect(goal.subQuestions, ['gold spot price today']);
    });

    test('bullets written under a preamble are dropped when a GOAL line '
        'follows', () {
      // A superseded statement takes its bullets with it, for the same
      // reason bullets before any statement are ignored: each one becomes a
      // checklist item the stopping rule obliges the model to close.
      final goal = parseResearchGoal('''
Here you go:
- a bullet the model invented
GOAL: Find the current price of gold
- gold spot price today
''');

      expect(goal!.statement, 'Find the current price of gold');
      expect(goal.subQuestions, ['gold spot price today']);
    });

    test('the bare-statement tolerance still wins when no GOAL line exists',
        () {
      // The tolerance was demoted to a fallback, not removed — and within
      // that fallback the FIRST bare line is still the statement, so a
      // qualifier written under it does not displace it.
      final goal = parseResearchGoal(
          'Find Vietnam\'s 2024 GDP\nnominal, in USD\n* GDP 2024');

      expect(goal!.statement, "Find Vietnam's 2024 GDP");
      expect(goal.subQuestions, ['GDP 2024']);
    });

    test('keeps the first GOAL line when the model restates itself', () {
      final goal = parseResearchGoal(
          'GOAL: first framing\nGOAL: second, worse framing');

      expect(goal!.statement, 'first framing');
    });

    test('a restated GOAL line does not discard the first goal\'s bullets',
        () {
      // Superseding a statement drops the bullets collected under it, which
      // is right for a preamble and wrong for a restatement: the second GOAL
      // line is not in force, so it must take nothing with it.
      final goal = parseResearchGoal('''
GOAL: first framing
- first sub-question
GOAL: second, worse framing
- second sub-question
''');

      expect(goal!.statement, 'first framing');
      expect(goal.subQuestions, ['first sub-question', 'second sub-question']);
    });

    test('strips wrapping quotes and tolerates a fullwidth colon', () {
      final goal = parseResearchGoal('GOAL：“查明 TikTok 何时开始谈 offer”');

      expect(goal!.statement, '查明 TikTok 何时开始谈 offer');
    });

    test('handles numbered sub-questions', () {
      final goal =
          parseResearchGoal('GOAL: two parts\n1. first part\n2) second part');

      expect(goal!.subQuestions, ['first part', 'second part']);
    });

    test('returns null when there is no usable statement', () {
      expect(parseResearchGoal(''), isNull);
      expect(parseResearchGoal('   \n\n  '), isNull);
      expect(parseResearchGoal('GOAL:'), isNull);
      // An empty label still claims the statement, even over a preamble it
      // came after: a run aimed at the user's own question (SearchAgent's
      // fallback for a null parse) beats one aimed at "Sure! Here you go:".
      expect(parseResearchGoal('Sure! Here you go:\nGOAL:'), isNull);
    });
  });
}
