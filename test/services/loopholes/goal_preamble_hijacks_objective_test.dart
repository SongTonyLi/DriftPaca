/// Regression: an explicit `GOAL:` line is the run's objective, whatever
/// courtesy prose the model wrote above it.
///
/// `parseResearchGoal` (lib/Utils/research_goal.dart) walks the reply line by
/// line, and its bare-sentence tolerance — the documented "a reply that never
/// labels its goal is still usable" fallback, pinned by
/// test/utils/research_goal_test.dart — used to fill the SAME single
/// `statement` slot as the `GOAL:` branch. With one slot filled by whichever
/// candidate came first, a courtesy preamble ("Sure! Here is the research
/// brief:") always claimed it, and the real `GOAL:` line below was discarded
/// by a `statement ??=` that had become a no-op. The parser defended against a
/// BULLET preamble (bullets before any statement are ignored) but nothing
/// defended against a prose one — an asymmetry, not a trade-off.
///
/// The parser now keeps two slots, the first labelled `GOAL:` line and the
/// tolerated bare line, and resolves them by authority once the whole reply is
/// read: the label wins wherever it appears, in the same spirit as a bare
/// `NONE` winning outright in `parseCoverageGaps`. Bullets collected under a
/// bare statement are discarded when a `GOAL:` line supersedes it — they were
/// the preamble's checklist, not the brief's — while a model merely restating
/// its own `GOAL:` line keeps the first goal and its bullets.
///
/// Why the parse is the last line of defence (nothing downstream re-checks
/// it): `SearchAgent._deriveGoal` (search_agent.dart:730) falls back to the
/// user's question only when the statement is EMPTY, so a non-empty preamble
/// sailed through into `ResearchLedger.objective` (search_agent.dart:369-372).
/// `renderBrief()` writes that as `Goal: <objective>`
/// (research_ledger.dart:390-393) directly above stoppingRule's "Stop
/// searching and write the answer as soon as your sources cover the goal
/// above", and ChatProvider concatenates the whole brief onto the SYSTEM
/// prompt of every turn (chat_provider.dart:1159-1166) — so the run's written
/// finish line was one the model could satisfy without researching anything.
/// The same objective is what `onLedgerUpdate` hands the UI as the user's
/// research goal.
///
/// Each integration assertion below is paired with the identical run minus the
/// preamble, so any difference is attributable to that one prose line and
/// nothing else in the harness.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Services/search_agent.dart';
import 'package:llamaseek/Services/web_search_service.dart';
import 'package:llamaseek/Utils/research_goal.dart';

/// A derivation reply in the exact shape a chatty model produces: one
/// courtesy line, then the requested brief.
const _replyWithPreamble = '''
Sure! Here is the research brief:
GOAL: Establish Vietnam's 2024 nominal GDP in USD
- Vietnam 2024 nominal GDP
''';

const _realGoal = "Establish Vietnam's 2024 nominal GDP in USD";
const _preamble = 'Sure! Here is the research brief:';
const _userQuestion = "What was Vietnam's GDP in 2024?";

void main() {
  group('parseResearchGoal: an explicit GOAL line outranks a prose preamble',
      () {
    test('the GOAL line becomes the statement and the preamble is dropped',
        () {
      final goal = parseResearchGoal(_replyWithPreamble);

      expect(goal, isNotNull,
          reason: 'the reply parses — the fix ranks the two candidates, it '
              'does not reject replies that have a preamble');
      expect(goal!.statement, _realGoal,
          reason: 'the labelled GOAL line wins wherever it appears, so the '
              'run is aimed at what the model actually derived');
      expect(goal.statement, isNot(contains('Sure!')),
          reason: 'the courtesy line is not the objective, not even '
              'prepended to it — it is discarded outright');
      expect(goal.subQuestions, ['Vietnam 2024 nominal GDP'],
          reason: 'the bullet follows the GOAL line, so it is still the '
              'brief\'s checklist — outranking the preamble must not cost '
              'the run its sub-questions');
    });

    test('the same reply WITHOUT the preamble parses correctly', () {
      // Kept as a duplicate-by-design control: the preamble is now inert
      // rather than causal, and this is what proves it. If ranking ever
      // regresses to first-match, only the test above fails and this one
      // still passes — the pair localises the failure.
      final goal = parseResearchGoal(_replyWithPreamble
          .split('\n')
          .where((l) => l.trim() != _preamble)
          .join('\n'));

      expect(goal!.statement, _realGoal,
          reason: 'the reply with and without the preamble parse '
              'identically; one extra prose line changes nothing');
    });

    test('a bullet preamble and a prose preamble are both defended against',
        () {
      // The bullet guard (bullets before any statement are ignored) always
      // existed; the prose one did not, and that asymmetry was the bug.
      final bulletPreamble =
          parseResearchGoal('- $_preamble\nGOAL: $_realGoal\n- Vietnam 2024 '
              'nominal GDP');
      final prosePreamble =
          parseResearchGoal('$_preamble\nGOAL: $_realGoal\n- Vietnam 2024 '
              'nominal GDP');

      expect(bulletPreamble!.statement, _realGoal,
          reason: 'the bullet form was always handled');
      expect(prosePreamble!.statement, _realGoal,
          reason: 'and the prose form now is too — the same lead-in cannot '
              'take the goal just because the model did not bullet it');
    });

    test('bullets under the preamble do not join the real goal\'s checklist',
        () {
      // Every sub-question becomes a checklist item the stopping rule then
      // obliges the model to close, so a bullet the preamble invented is a
      // search the run would feel bound to run.
      final goal = parseResearchGoal(
          '$_preamble\n- a bullet belonging to the preamble\n'
          'GOAL: $_realGoal\n- Vietnam 2024 nominal GDP');

      expect(goal!.statement, _realGoal);
      expect(goal.subQuestions, ['Vietnam 2024 nominal GDP'],
          reason: 'the superseded statement takes its bullets with it; the '
              'checklist belongs to the goal in force, not to the prose the '
              'GOAL line replaced');
    });
  });

  group('the real goal reaches the ledger, the system prompt and the UI', () {
    /// Drives a real SearchAgent with a stubbed derivation (no network, no
    /// model) and returns the research briefs handed to each turn plus every
    /// objective published to the UI via onLedgerUpdate.
    Future<({List<String> briefs, List<String> published})> runWith(
        String derivationReply) async {
      final briefs = <String>[];
      final published = <String>[];
      var turn = 0;
      final agent = SearchAgent(
        deriveGoal: (_) async => parseResearchGoal(derivationReply),
        streamTurn: (request) async* {
          briefs.add(request.researchBrief);
          if (turn++ == 0) {
            yield OllamaMessage('',
                role: OllamaMessageRole.assistant,
                toolCalls: const [
                  OllamaToolCall(
                      name: 'web_search',
                      arguments: {'query': 'Vietnam 2024 nominal GDP'}),
                ]);
          } else {
            yield OllamaMessage('Vietnam\'s 2024 nominal GDP was about \$465B.',
                role: OllamaMessageRole.assistant);
          }
        },
        search: (_) async => [
          WebSearchResult(
            title: 'Vietnam GDP',
            url: 'https://example.org/vn-gdp',
            snippet: 'Vietnam nominal GDP 2024 was about 465 billion USD.',
            pageContent: 'Vietnam nominal GDP 2024 was about 465 billion USD.',
          ),
        ],
      );

      await agent.run(
        history: [OllamaMessage(_userQuestion, role: OllamaMessageRole.user)],
        listener: SearchAgentListener(
          onLedgerUpdate: (objective, _) => published.add(objective),
        ),
      );
      return (briefs: briefs, published: published);
    }

    test('every turn\'s brief says `Goal: <real goal>`, never the preamble',
        () async {
      final run = await runWith(_replyWithPreamble);

      expect(run.briefs, isNotEmpty);
      for (final brief in run.briefs) {
        expect(brief, contains('Goal: $_realGoal'),
            reason: 'ResearchLedger.renderBrief writes the objective as the '
                'run\'s goal, and ChatProvider appends this whole block to '
                'the SYSTEM prompt of every turn');
        expect(brief, isNot(contains(_preamble)),
            reason: 'the courtesy line never reaches the model\'s context, '
                'on the first turn or any later one');
        expect(brief, contains(ResearchLedger.stoppingRule),
            reason: 'and the stopping rule still sits directly below it, '
                'telling the model to stop "as soon as your sources cover '
                'the goal above" — which is what makes the Goal line '
                'load-bearing rather than decorative');
      }
    });

    test('control: the identical run minus the preamble carries the real goal',
        () async {
      // Proves the assertions above are not vacuous — the same fake stream,
      // the same fake search, one prose line fewer, same outcome.
      final run = await runWith('GOAL: $_realGoal\n- Vietnam 2024 nominal GDP');

      expect(run.briefs.first, contains('Goal: $_realGoal'),
          reason: 'the brief carries the real goal with or without a '
              'preamble above the GOAL line');
      expect(run.published.last, _realGoal,
          reason: 'and so does the UI');
    });

    test('the UI is handed the real goal, never the preamble', () async {
      final run = await runWith(_replyWithPreamble);

      expect(run.published, isNotEmpty);
      expect(run.published.last, _realGoal,
          reason: 'onLedgerUpdate publishes ledger.objective, so the '
              'research panel shows the user the goal their question was '
              'turned into');
      expect(run.published, isNot(contains(_preamble)),
          reason: 'the preamble is published at no point in the run, not '
              'even before the first ledger update replaces it');
    });

    test('the fallback to the user\'s question engages only on an empty '
        'statement', () async {
      // _deriveGoal falls back to the user's question when the derived
      // statement is EMPTY. It correctly stays out of the way here because a
      // usable goal was recovered — not because a preamble slipped past it.
      final withPreamble = await runWith(_replyWithPreamble);
      expect(withPreamble.published.last, _realGoal,
          reason: 'the derived goal was usable, so nothing degraded');
      expect(withPreamble.published.last, isNot(_preamble),
          reason: 'and what survived is the goal, not the courtesy line');
      expect(withPreamble.published.last, isNot(_userQuestion),
          reason: 'the safety net did not have to fire — recovering the real '
              'goal is strictly better than degrading to the raw question');

      final blank = await runWith('GOAL:\n');
      expect(blank.published.last, _userQuestion,
          reason: 'an empty GOAL label still claims the statement slot and '
              'still yields a null parse, so the fallback fires — ranking '
              'the label first must not open a path from an empty label to '
              'some later line of the reply');
    });
  });
}
