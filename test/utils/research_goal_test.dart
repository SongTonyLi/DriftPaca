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
      // cost the run its goal for no reason.
      final goal = parseResearchGoal('Find Vietnam\'s 2024 GDP\n* GDP 2024');

      expect(goal!.statement, "Find Vietnam's 2024 GDP");
      expect(goal.subQuestions, ['GDP 2024']);
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

    test('keeps the first GOAL line when the model restates itself', () {
      final goal = parseResearchGoal(
          'GOAL: first framing\nGOAL: second, worse framing');

      expect(goal!.statement, 'first framing');
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
    });
  });
}
