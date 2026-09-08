/// Offline probe: a prose preamble line before the `GOAL:` line becomes the
/// run's objective, and the model's real GOAL line is silently discarded.
///
/// `parseResearchGoal` (lib/Utils/research_goal.dart) walks the reply line by
/// line. Its last statement is `statement ??= _clean(trimmed)` — the
/// deliberate "bare sentence with no GOAL prefix" tolerance documented at
/// lines 19-24 and pinned by test/utils/research_goal_test.dart:21. Because
/// it fires on the FIRST non-empty, non-bullet, non-GOAL, non-CLARIFY line, a
/// courtesy preamble ("Sure! Here is the research brief:") claims the
/// statement slot; the real `GOAL:` line that follows hits `statement ??=` at
/// line 49, which is then a no-op.
///
/// The parser explicitly defends against a BULLET preamble (line 72,
/// `if (statement == null) continue;`, pinned by research_goal_test.dart:103)
/// but nothing defends against a prose one — the asymmetry these tests pin.
///
/// Nothing downstream recovers: SearchAgent._deriveGoal only falls back to the
/// user's question when the statement is EMPTY, so the preamble becomes
/// ResearchLedger.objective, which renderBrief() writes as `Goal: <preamble>`
/// into every turn's system prompt (ChatProvider concatenates the brief onto
/// the system prompt) directly above stoppingRule's "Stop searching and write
/// the answer as soon as your sources cover the goal above" — and is also what
/// onLedgerUpdate hands the UI as the run's research goal.
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
  group('parseResearchGoal: a prose preamble outranks the real GOAL line', () {
    test('the preamble becomes the statement and the GOAL text is dropped',
        () {
      final goal = parseResearchGoal(_replyWithPreamble);

      expect(goal, isNotNull,
          reason: 'the reply parsed fine — this is not a rejection path, so '
              'no caller ever learns the goal was mangled');
      expect(goal!.statement, _preamble,
          reason: 'research_goal.dart:78 claimed the statement slot for the '
              'courtesy line, so research_goal.dart:49 (`statement ??=`) was '
              'a no-op when the real GOAL line arrived');
      expect(goal.statement, isNot(contains('Vietnam')),
          reason: 'the model\'s actual objective is gone from the statement '
              'entirely — not truncated, not appended, discarded');
      expect(goal.subQuestions, ['Vietnam 2024 nominal GDP'],
          reason: 'the bullets after the GOAL line were still accepted, so '
              'the run gets a real checklist under a meaningless goal — the '
              'reply was parsed, not rejected');
    });

    test('the same reply WITHOUT the preamble parses correctly', () {
      // The control: nothing about the GOAL line, the bullet, or the
      // trailing newline is at fault. One extra prose line is the whole
      // difference.
      final goal = parseResearchGoal(_replyWithPreamble
          .split('\n')
          .where((l) => l.trim() != _preamble)
          .join('\n'));

      expect(goal!.statement, _realGoal,
          reason: 'removing only the preamble recovers the correct goal, '
              'isolating the preamble line as the cause');
    });

    test('a BULLET preamble is defended against, prose is not', () {
      // research_goal.dart:72 skips bullets seen before any statement, so
      // the identical reply with the preamble written as a bullet keeps the
      // real goal. That guard exists; its prose twin does not.
      final bulletPreamble =
          parseResearchGoal('- $_preamble\nGOAL: $_realGoal\n- Vietnam 2024 '
              'nominal GDP');

      expect(bulletPreamble!.statement, _realGoal,
          reason: 'the bullet form is handled, which shows the prose form '
              'losing the goal is an unintended asymmetry rather than a '
              'documented trade-off');
    });
  });

  group('the preamble reaches the ledger, the system prompt and the UI', () {
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

    test('every turn\'s brief says `Goal: <preamble>`, never the real goal',
        () async {
      final run = await runWith(_replyWithPreamble);

      expect(run.briefs, isNotEmpty);
      for (final brief in run.briefs) {
        expect(brief, contains('Goal: $_preamble'),
            reason: 'ResearchLedger.renderBrief wrote the preamble as the '
                'run\'s goal; ChatProvider appends this whole block to the '
                'SYSTEM prompt of the turn');
        expect(brief, isNot(contains(_realGoal)),
            reason: 'the model\'s real objective appears nowhere in the '
                'brief — the written finish line the ResearchGoal feature '
                'exists to provide has been replaced by meaningless prose');
        expect(brief, contains(ResearchLedger.stoppingRule),
            reason: 'and the stopping rule sits directly below it, telling '
                'the model to stop "as soon as your sources cover the goal '
                'above" — pointing at the preamble');
      }
    });

    test('control: the identical run minus the preamble carries the real goal',
        () async {
      // Proves the two assertions above are not vacuous — the same fake
      // stream, the same fake search, one prose line fewer, and both the
      // system-prompt brief and the UI objective are correct.
      final run = await runWith('GOAL: $_realGoal\n- Vietnam 2024 nominal GDP');

      expect(run.briefs.first, contains('Goal: $_realGoal'),
          reason: 'the brief CAN carry the real goal; the preamble is what '
              'stops it');
      expect(run.published.last, _realGoal,
          reason: 'and the UI CAN show the real goal');
    });

    test('the UI is handed the preamble as the run\'s research goal',
        () async {
      final run = await runWith(_replyWithPreamble);

      expect(run.published, isNotEmpty);
      expect(run.published.last, _preamble,
          reason: 'onLedgerUpdate published ledger.objective, so the '
              'research panel shows the user "$_preamble" where their '
              'research goal belongs');
      expect(run.published, isNot(contains(_realGoal)),
          reason: 'the real goal was never published at any point in the run');
    });

    test('SearchAgent\'s fallback-to-the-user\'s-question never engages',
        () async {
      // _deriveGoal (search_agent.dart:730) only falls back when the derived
      // statement is EMPTY. A non-empty preamble sails straight through, so
      // the safety net built for exactly this situation does not fire.
      final withPreamble = await runWith(_replyWithPreamble);
      expect(withPreamble.published.last, isNot(_userQuestion),
          reason: 'the run did not degrade to the user\'s own question, '
              'which would have been a correct objective — it adopted the '
              'preamble instead');

      final blank = await runWith('GOAL:\n');
      expect(blank.published.last, _userQuestion,
          reason: 'the fallback demonstrably works when the statement is '
              'empty, so it is the non-empty preamble specifically that '
              'slips past it');
    });
  });
}
