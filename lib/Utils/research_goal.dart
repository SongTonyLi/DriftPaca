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
/// That tolerance is a FALLBACK, never a competitor: a labelled `GOAL:`
/// line wins outright wherever in the reply it appears, exactly as a bare
/// `NONE` wins outright in [parseCoverageGaps]. Resolved by first match
/// instead, the courtesy preamble the derivation prompt forbids and a
/// chatty model writes anyway ("Sure! Here is the research brief:") claimed
/// the statement slot and the real `GOAL:` line below it was discarded —
/// putting the preamble in `ResearchLedger.objective`, which `renderBrief`
/// writes as the `Goal:` line of every turn's system prompt directly above
/// "stop as soon as your sources cover the goal above", and which the
/// research panel shows the user as their own research goal.
///
/// A reply with a preamble and NO `GOAL:` line anywhere still adopts the
/// preamble: no signal separates a lead-in from a goal that simply ends in
/// a colon ("Find the current population figure for each of the following
/// cities:" is a real derivation), so there is nothing safe to rank it
/// against.
///
/// Bullets appearing BEFORE any goal statement are ignored rather than
/// treated as sub-questions: they belong to something the model wrote on
/// its own, and the checklist is the one output here that directly causes
/// searches to run. For the same reason, bullets collected under a bare
/// statement are dropped when a `GOAL:` line later supersedes it — they
/// were the preamble's checklist, not the brief's.
///
/// A `CLARIFY:` line switches every later bullet or `[ ]` line from
/// sub-question to answer option. The clarification is kept only with at
/// least [minClarificationOptions] options — a question with nothing to
/// pick from is not one the card can ask — and at most
/// [maxClarificationOptions], for the same reason the checklist is capped.
ResearchGoal? parseResearchGoal(String raw) {
  // Two slots, resolved by authority after the whole reply is read, rather
  // than one slot resolved by whichever candidate appears first.
  String? labelled;
  String? bare;
  final subQuestions = <String>[];
  String? clarifyQuestion;
  final options = <String>[];

  for (final line in raw.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    final goalMatch = _goalPrefix.firstMatch(trimmed);
    if (goalMatch != null) {
      // A second GOAL line is the model restating itself; the first wins.
      // The guard covers the clear as well as the assignment: a restatement
      // is not the goal in force, so it must not take the first goal's
      // bullets with it.
      if (labelled == null) {
        labelled = _clean(trimmed.substring(goalMatch.end));
        // Whatever stood above the label was preamble, and so was anything
        // bulleted under it.
        subQuestions.clear();
      }
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
      if (labelled == null && bare == null) continue;
      final question = _clean(trimmed.replaceFirst(_bulletPrefix, ''));
      if (question.isNotEmpty) subQuestions.add(question);
      continue;
    }

    // Prose below a labelled goal is the model explaining itself; only a
    // bare line seen before any label is a candidate statement. An empty
    // `_clean` still claims the slot, so a reply whose first bare line is
    // nothing but quotes stays unusable instead of promoting the line
    // after it.
    if (labelled == null) bare ??= _clean(trimmed);
  }

  final statement = labelled ?? bare;
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
