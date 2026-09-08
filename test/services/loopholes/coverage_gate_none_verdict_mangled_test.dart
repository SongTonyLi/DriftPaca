/// Probe: `parseCoverageGaps`' bullet-stripper destroys the completeness
/// gate's NONE verdict.
///
/// `_bulletPrefix` (lib/Utils/coverage_gaps.dart:9) is
/// `^\s*(?:[-*•]|\d+[.)])\s*` — `*` is one of the bullet characters — and it
/// is applied to EVERY line (line 23) before the `^none[.!]?$` test on line
/// 25. So a gate that replies in markdown bold, `**NONE**`, has its first
/// asterisk eaten, the residue `*NONE**` fails the exact-match NONE test,
/// and "the draft is complete" is reported to SearchAgent as a gap.
///
/// The same exact-match-only test also rejects `NONE — every part is
/// addressed`, and the `break` at maxCoverageGaps (line 27) means a NONE
/// that arrives after three lines of the model's own reasoning is never
/// reached — contradicting the function's own doc on lines 18-19 ("A NONE
/// anywhere in the reply wins outright").
///
/// Downstream (search_agent.dart:483-523) a non-empty gap list is not
/// sanity-checked: it opens a ledger sub-goal, fires `onResetContent`
/// (which ChatProvider uses to blank the streamed bubble,
/// chat_provider.dart:1253-1258), tells the model it omitted `*NONE**`, and
/// forces a corrective round whose output replaces the accepted draft.
///
/// Each integration assertion below is paired with the identical run using a
/// bare `NONE`, so the difference is attributable to the two `*` characters
/// and nothing else in the harness.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Services/search_agent.dart';
import 'package:llamaseek/Services/web_search_service.dart';
import 'package:llamaseek/Utils/coverage_gaps.dart';

/// Everything one offline SearchAgent run exposes to the UI layer.
class _RunTrace {
  final String finalContent;
  final int resetContentCount;
  final List<SubGoal> lastLedgerSnapshot;
  final List<String> briefs;
  final List<String> userMessagesInTranscript;

  _RunTrace({
    required this.finalContent,
    required this.resetContentCount,
    required this.lastLedgerSnapshot,
    required this.briefs,
    required this.userMessagesInTranscript,
  });
}

const _draftAnswer =
    'Mount Everest is 8,849 m tall, as remeasured jointly by Nepal and '
    'China in 2020 [1].';
const _correctiveAnswer =
    'Mount Everest is 8,849 m tall [1]. I could not establish *NONE**.';

/// Drives a real SearchAgent, fully offline: turn 1 emits one web_search
/// tool call, turn 2 emits a complete draft answer, and any later turn
/// emits the corrective answer. The completeness gate is whatever
/// [gateReply] parses to.
Future<_RunTrace> _runWithGateReply(String gateReply) async {
  var turn = 0;
  var resets = 0;
  final briefs = <String>[];
  final userMessages = <String>[];
  var snapshot = <SubGoal>[];

  final agent = SearchAgent(
    streamTurn: (request) async* {
      briefs.add(request.researchBrief);
      for (final m in request.transcript) {
        if (m.role == OllamaMessageRole.user) userMessages.add(m.content);
      }
      if (turn++ == 0) {
        yield OllamaMessage('',
            role: OllamaMessageRole.assistant,
            toolCalls: const [
              OllamaToolCall(
                  name: 'web_search',
                  arguments: {'query': 'height of Mount Everest'}),
            ]);
      } else if (turn == 2) {
        yield OllamaMessage(_draftAnswer, role: OllamaMessageRole.assistant);
      } else {
        yield OllamaMessage(_correctiveAnswer,
            role: OllamaMessageRole.assistant);
      }
    },
    search: (_) async => [
      WebSearchResult(
        title: 'Mount Everest',
        snippet: 'Mount Everest is 8,849 m above sea level.',
        url: 'https://example.invalid/everest',
        chunks: const ['Mount Everest is 8,849 m above sea level.'],
      ),
    ],
    // Exactly what ChatProvider does with the gate's raw reply — see
    // chat_provider.dart:1149.
    assessCoverage: (_) async => parseCoverageGaps(gateReply),
  );

  final outcome = await agent.run(
    history: [
      OllamaMessage('How tall is Mount Everest?', role: OllamaMessageRole.user)
    ],
    listener: SearchAgentListener(
      onResetContent: () => resets++,
      onLedgerUpdate: (_, s) => snapshot = s,
    ),
  );

  return _RunTrace(
    finalContent: outcome.content,
    resetContentCount: resets,
    lastLedgerSnapshot: snapshot,
    briefs: briefs,
    userMessagesInTranscript: userMessages,
  );
}

void main() {
  group('parseCoverageGaps eats the asterisk off a bold NONE', () {
    test('**NONE** is parsed as a gap named "*NONE**"', () {
      expect(parseCoverageGaps('NONE'), isEmpty,
          reason: 'control: the bare verdict the gate prompt asks for is '
              'read correctly, so any difference below comes from the '
              'markdown emphasis alone');
      expect(parseCoverageGaps('**NONE**'), ['*NONE**'],
          reason: '_bulletPrefix treats the leading `*` as a bullet and '
              'strips exactly one of them, so the residue no longer matches '
              '_nonePattern (`^none[.!]?\$`) and "complete" is reported as a '
              'gap whose text is the mangled verdict itself');
      expect(parseCoverageGaps('* NONE'), isEmpty,
          reason: 'second control: a SINGLE leading asterisk is handled — '
              'the strip leaves a bare NONE that still matches. The defect '
              'is specific to the second asterisk of `**`, which the '
              'single-character bullet class cannot consume and which then '
              'poisons the exact-match test');
    });

    test('a NONE stated with a reason is emitted as a gap verbatim', () {
      expect(parseCoverageGaps('NONE - the draft covers every part'),
          ['NONE - the draft covers every part'],
          reason: '_nonePattern is anchored at both ends, so a verdict the '
              'model justified on the same line is filed as a missing part '
              'of the question');
    });

    test('a NONE after three reasoning lines is never reached', () {
      const reply = 'The question asks for the height of Everest.\n'
          'The draft gives 8,849 m with a citation.\n'
          'That is the whole question.\n'
          'NONE';
      expect(
        parseCoverageGaps(reply),
        [
          'The question asks for the height of Everest.',
          'The draft gives 8,849 m with a citation.',
          'That is the whole question.',
        ],
        reason: 'the `break` at maxCoverageGaps (3) returns before the NONE '
            'line is read, so the function\'s own doc — "A NONE anywhere in '
            'the reply wins outright" — does not hold, and three lines of '
            'the model AGREEING the draft is complete become three gaps',
      );
    });
  });

  group('the mangled verdict drives a full corrective round', () {
    late _RunTrace bold;
    late _RunTrace bare;

    setUpAll(() async {
      bold = await _runWithGateReply('**NONE**');
      bare = await _runWithGateReply('NONE');
    });

    test('the accepted draft is wiped from the screen and replaced', () {
      expect(bare.resetContentCount, 0,
          reason: 'control: a bare NONE accepts the draft, so nothing the '
              'user has already read is cleared');
      expect(bare.finalContent, _draftAnswer,
          reason: 'control: the delivered answer is the draft the model '
              'streamed');

      expect(bold.resetContentCount, 1,
          reason: 'onResetContent fired — ChatProvider blanks '
              'streamingMessage.content there (chat_provider.dart:1253), so '
              'the complete answer already on the user\'s screen is erased '
              'purely because the gate wrote NONE in bold');
      expect(bold.finalContent, _correctiveAnswer,
          reason: 'and the answer actually delivered is the forced '
              'corrective round\'s output, not the draft the gate was '
              'trying to approve');
    });

    test('"*NONE**" becomes an open checklist item in the ledger', () {
      expect(bare.lastLedgerSnapshot.map((g) => g.query), isNot(contains('*NONE**')));

      final opened = bold.lastLedgerSnapshot
          .where((g) => g.query == '*NONE**' && g.status == SubGoalStatus.open)
          .toList();
      expect(opened, hasLength(1),
          reason: 'SearchAgent.run calls ledger.openGap(gap) with no '
              'validation (search_agent.dart:486), so the research panel '
              'shows the user an unresolved research item literally called '
              '"*NONE**"');
      expect(bold.briefs.last, contains('- [ ] "*NONE**"'),
          reason: 'and the same item is rendered into the research brief '
              'handed to the corrective turn, where the stopping rule tells '
              'the model to keep searching while a [ ] is open');
    });

    test('the model is told it omitted "*NONE**"', () {
      expect(
        bold.userMessagesInTranscript.where((m) => m.contains('- *NONE**')),
        isNotEmpty,
        reason: '_gapNotice injects a user-role message claiming the draft '
            '"did not address these parts of my question: - *NONE**" — the '
            'gate\'s verdict of completeness, restated to the model as the '
            'thing it failed to answer',
      );
      expect(bare.userMessagesInTranscript.where((m) => m.contains('NONE')),
          isEmpty,
          reason: 'control: no such message exists when the verdict parses');
    });
  });
}
