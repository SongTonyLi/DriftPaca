import 'package:llamaseek/Models/research_ledger.dart';

final _bulletPrefix = RegExp(r'^\s*(?:[-*•]|\d+[.)])\s*');
final _goalPrefix = RegExp(r'^\s*goal\s*[:：]\s*', caseSensitive: false);
final _wrappingQuotes = RegExp(r'''^["'“”‘’]+|["'“”‘’]+$''');
final _clarifyPrefix = RegExp(r'^\s*clarify\s*[:：]\s*', caseSensitive: false);
final _optionPrefix =
    RegExp(r'^\s*(?:[-*•]\s*)?\[\s*[xX]?\s*\]\s*|^\s*(?:[-*•]|\d+[.)])\s*');

/// Fewest options a clarification is worth asking with — one option is
/// not a choice — and the most the card will show.
const minClarificationOptions = 2;
const maxClarificationOptions = 4;

/// Parses the goal-derivation reply into a [ResearchGoal]. Returns null when
/// there is no usable goal statement — SearchAgent then falls back to the
/// user's message verbatim, which is exactly the behavior this replaces.
///
/// Tolerant of the shapes a model actually emits, in the same spirit as
/// [parseCoverageGaps]: the prompt asks for a `GOAL:` line followed by
/// bullets, but nothing enforces it. A reply that opens with a bare
/// sentence and then bullets is read the same way, since that is the only
/// other shape the instruction can plausibly produce and discarding it
/// would cost the run its goal over a missing prefix.
///
/// Bullets appearing BEFORE any goal statement are ignored rather than
/// treated as sub-questions: they belong to something the model wrote on
/// its own, and the checklist is the one output here that directly causes
/// searches to run.
///
/// A `CLARIFY:` line switches every later bullet or `[ ]` line from
/// sub-question to answer option. The clarification is kept only with at
/// least [minClarificationOptions] options — a question with nothing to
/// pick from is not one the card can ask — and at most
/// [maxClarificationOptions], for the same reason the checklist is capped.
ResearchGoal? parseResearchGoal(String raw) {
  String? statement;
  final subQuestions = <String>[];
  String? clarifyQuestion;
  final options = <String>[];

  for (final line in raw.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    final goalMatch = _goalPrefix.firstMatch(trimmed);
    if (goalMatch != null) {
      // A second GOAL line is the model restating itself; the first wins.
      statement ??= _clean(trimmed.substring(goalMatch.end));
      continue;
    }

    final clarifyMatch = _clarifyPrefix.firstMatch(trimmed);
    if (clarifyMatch != null) {
      clarifyQuestion ??= _clean(trimmed.substring(clarifyMatch.end));
      continue;
    }

    if (clarifyQuestion != null) {
      final optionMatch = _optionPrefix.firstMatch(trimmed);
      if (optionMatch != null) {
        final option = _clean(trimmed.substring(optionMatch.end));
        if (option.isNotEmpty) options.add(option);
      }
      // Prose after the question is the model explaining itself; nothing
      // there is an option or a sub-question.
      continue;
    }

    final isBullet = _bulletPrefix.hasMatch(trimmed);
    if (isBullet) {
      if (statement == null) continue;
      final question = _clean(trimmed.replaceFirst(_bulletPrefix, ''));
      if (question.isNotEmpty) subQuestions.add(question);
      continue;
    }

    statement ??= _clean(trimmed);
  }

  if (statement == null || statement.isEmpty) return null;
  final clarification = clarifyQuestion != null &&
          clarifyQuestion.isNotEmpty &&
          options.length >= minClarificationOptions
      ? ResearchClarification(
          question: clarifyQuestion,
          options: options.take(maxClarificationOptions).toList(),
        )
      : null;
  return ResearchGoal(
    statement: statement,
    subQuestions: subQuestions,
    clarification: clarification,
  );
}

String _clean(String value) =>
    value.trim().replaceAll(_wrappingQuotes, '').trim();
