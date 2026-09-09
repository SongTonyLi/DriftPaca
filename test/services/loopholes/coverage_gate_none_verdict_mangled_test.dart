/// Regression: the completeness gate's NONE verdict survives the way a
/// model actually writes it.
///
/// `*` is simultaneously a bullet character and a markdown emphasis marker,
/// and `_bulletPrefix` (lib/Utils/coverage_gaps.dart) can only eat one of
/// them. A gate replying in bold, `**NONE**`, used to lose exactly one
/// asterisk before the verdict test ran; the residue `*NONE**` was not
/// NONE, so "the draft is complete" was reported to SearchAgent as a gap.
///
/// Three things now stand between that reply and a research gap, and the
/// third is what makes the guarantee general instead of incidental: the
/// bullet class declines a DOUBLED asterisk (a bullet is never `**`),
/// emphasis that wraps a whole line is unwrapped on both sides of the bullet
/// strip, and the verdict is then judged on a copy of the line with every
/// emphasis character removed. Without that last step the strip only ever
/// reaches a run sitting at a line's very edge, so `**NONE**.` — the full
/// stop written OUTSIDE the bold, which is where markdown normally puts it —
/// stranded `**` mid-string and failed exactly as `*NONE**` did, while
/// `**NONE.**`, one keystroke away, passed. Same for every bolded verdict
/// the model justified on the same line.
///
/// Bare `NONE`, bold `**NONE**` and bold-with-punctuation `**NONE**.` are
/// therefore pinned below as one behaviour, each driven through a full
/// offline SearchAgent run.
///
/// Two sibling holes in the same function are pinned here too: the verdict
/// test was anchored at both ends, so `NONE — every part is addressed` was
/// filed as a gap whose text was the verdict itself; and the scan used to
/// `break` at maxCoverageGaps, so a NONE arriving after three lines of the
/// model's own reasoning was never reached — contradicting the function's
/// doc ("A NONE anywhere in the reply wins outright"). The cap now bounds
/// only what is returned, never how far the reply is read.
///
/// Widening the verdict test is the dangerous direction, because it buys a
/// false "complete" that costs the user the research the gate exists to
/// trigger. The unit group therefore guards it: a line that merely BEGINS
/// with the word "none" is still a gap.
///
/// Why any of this reaches the user (search_agent.dart:567-630): the parsed
/// gaps are never checked for shape or meaning — `_assessGaps` only trims
/// them and drops blanks, and `ResearchLedger.openGap` only dedupes against
/// an existing sub-goal — so whatever the parser returns opens a ledger
/// sub-goal, fires `onResetContent` (which ChatProvider uses to blank the
/// streamed bubble, chat_provider.dart:1276-1281), is restated to the model
/// as a part of the question it omitted, and forces a corrective round
/// whose output replaces the accepted draft.
///
/// Each integration assertion below is paired with the identical run using
/// a bare `NONE`, so any difference is attributable to the markup and
/// nothing else in the harness. The pairings are positive as well as
/// negative — same ledger items, same brief, same number of turns — because
/// "no NONE anywhere in the ledger" would also pass on a harness that had
/// quietly stopped opening ledger items at all.
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

/// The answer a corrective round would deliver. Nothing should ever see it:
/// it is the sentinel that proves no corrective round ran.
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
  group('parseCoverageGaps reads a bold NONE as the verdict it is', () {
    test('**NONE** is read as the complete verdict', () {
      expect(parseCoverageGaps('NONE'), isEmpty,
          reason: 'control: the bare verdict the gate prompt asks for is '
              'read correctly, so any difference below comes from the '
              'markdown emphasis alone');
      expect(parseCoverageGaps('**NONE**'), isEmpty,
          reason: 'emphasis is stripped on both sides of the bullet strip, '
              'so the second asterisk the single-character bullet class '
              'cannot consume no longer survives into the verdict test — '
              'the gate\'s report of completeness is not filed as a gap '
              'named after itself');
      expect(parseCoverageGaps('* NONE'), isEmpty,
          reason: 'second control: a SINGLE leading asterisk was always '
              'handled, and still is — widening the strip must not cost the '
              'bullet case');
      expect(parseCoverageGaps('* **NONE**'), isEmpty,
          reason: 'a bulleted bold verdict needs the strip on BOTH sides of '
              'the bullet strip: the leading `*` is a bullet, the `**` '
              'around the word is emphasis');
      expect(parseCoverageGaps('__NONE__'), isEmpty,
          reason: 'underscore emphasis reaches the same verdict as asterisk '
              'emphasis');
      expect(parseCoverageGaps('`NONE`'), isEmpty,
          reason: 'a model that code-quotes the literal token the prompt '
              'asked for is still reporting completeness');

      // Guards. The strip and the verdict test were both widened by this
      // fix, and the direction that costs the user research is a real gap
      // read as "complete" — so pin the boundary here, in the same test
      // that widened it.
      expect(parseCoverageGaps('none of the sources give the 2027 winner'),
          ['none of the sources give the 2027 winner'],
          reason: 'a genuine gap that merely BEGINS with the word "none" is '
              'still a gap: without a punctuation separator after the word '
              'this is prose, not a verdict');
      expect(parseCoverageGaps('nonetheless the college is missing'),
          hasLength(1),
          reason: 'and the verdict test still matches the whole word, not a '
              'prefix of one');
    });

    test('a bold verdict survives punctuation written outside the bold', () {
      expect(parseCoverageGaps('**NONE.**'), isEmpty,
          reason: 'control: the full stop INSIDE the emphasis leaves the run '
              'at the line\'s edge, where a strip anchored to that edge can '
              'reach it');
      expect(parseCoverageGaps('**NONE**.'), isEmpty,
          reason: 'and moving that one full stop outside the bold — the '
              'ordinary markdown spelling — must not change the verdict: it '
              'strands `**` mid-string, out of reach of any edge-anchored '
              'strip, which is why the verdict is judged with emphasis '
              'removed rather than merely unwrapped');
      expect(parseCoverageGaps('`NONE`.'), isEmpty,
          reason: 'the marker is irrelevant; a code-quoted verdict punctuates '
              'the same way');
      expect(parseCoverageGaps('- **NONE**!'), isEmpty,
          reason: 'and a bullet in front of it does not resurrect the hole');
    });

    test('an emphasised verdict may also carry its justification', () {
      // The two tolerances compose or neither is worth much: a model that
      // bolds its verdict is exactly the model that also explains itself.
      expect(parseCoverageGaps('**NONE** — every part is addressed'), isEmpty,
          reason: 'the strip cannot reach the closing `**` here either — the '
              'justification follows it — so this is the same defect wearing '
              'a different tail');
      expect(parseCoverageGaps('**NONE** - the draft covers every part'),
          isEmpty);
      expect(parseCoverageGaps('_NONE_: the draft covers it'), isEmpty);
      expect(
        parseCoverageGaps(
            'Assessment:\n\n**NONE** - the draft answers the whole question.'),
        isEmpty,
        reason: 'and inside a multi-line reply the mangled verdict took the '
            'model\'s own preamble down with it: two gaps, one of them the '
            'word "Assessment:"',
      );
    });

    test('a NONE stated with a reason is still the complete verdict', () {
      expect(parseCoverageGaps('NONE - the draft covers every part'), isEmpty,
          reason: 'the verdict test is no longer anchored at both ends, so a '
              'verdict the model justified on the same line is read as '
              'completeness rather than filed as a missing part of the '
              'question');
      expect(parseCoverageGaps('NONE — every part is addressed'), isEmpty,
          reason: 'an em dash separator is the shape models reach for most');
      expect(parseCoverageGaps('NONE: the draft covers it'), isEmpty,
          reason: 'as is a colon');
      expect(parseCoverageGaps('NONE. The draft covers everything.'), isEmpty,
          reason: 'and a full stop followed by the explanation — the shape a '
              'model falls into when it cannot resist a sentence');
    });

    test('a NONE after three reasoning lines still wins', () {
      const reply = 'The question asks for the height of Everest.\n'
          'The draft gives 8,849 m with a citation.\n'
          'That is the whole question.\n'
          'NONE';
      expect(
        parseCoverageGaps(reply),
        isEmpty,
        reason: 'maxCoverageGaps (3) now bounds only what is RETURNED, not '
            'how far the reply is scanned, so the function\'s own doc — "A '
            'NONE anywhere in the reply wins outright" — holds, and three '
            'lines of the model AGREEING the draft is complete are no '
            'longer three gaps',
      );
    });
  });

  group('a bold verdict is treated exactly like a bare one', () {
    late _RunTrace bold;
    late _RunTrace bare;

    /// `**NONE**.` — the same bold verdict with the full stop where markdown
    /// normally puts it, outside the emphasis. One character away from the
    /// `**NONE**` run above, and the last shape of this defect to be closed.
    late _RunTrace punctuated;

    setUpAll(() async {
      bold = await _runWithGateReply('**NONE**');
      bare = await _runWithGateReply('NONE');
      punctuated = await _runWithGateReply('**NONE**.');
    });

    test('the accepted draft survives a bold verdict', () {
      expect(bare.resetContentCount, 0,
          reason: 'control: a bare NONE accepts the draft, so nothing the '
              'user has already read is cleared');
      expect(bare.finalContent, _draftAnswer,
          reason: 'control: the delivered answer is the draft the model '
              'streamed');

      expect(bold.resetContentCount, 0,
          reason: 'onResetContent must not fire — ChatProvider blanks '
              'streamingMessage.content there (chat_provider.dart:1253), so '
              'firing it would erase a complete answer already on the '
              'user\'s screen purely because the gate wrote NONE in bold');
      expect(bold.finalContent, _draftAnswer,
          reason: 'and the answer delivered is the draft the gate was '
              'approving');
      expect(bold.finalContent, isNot(_correctiveAnswer),
          reason: 'not the output of a corrective round — the harness still '
              'has one waiting on turn 3, so this is a live sentinel');
      expect(bold.briefs.length, bare.briefs.length,
          reason: 'and the bold run spends exactly the turns the bare run '
              'does: no extra round was billed to the user');

      expect(punctuated.resetContentCount, 0,
          reason: 'moving the full stop outside the bold is the shape a '
              'model reaches for most, and it took the same path: openGap, '
              'onResetContent, a gap notice, a corrective round');
      expect(punctuated.finalContent, _draftAnswer);
      expect(punctuated.finalContent, isNot(_correctiveAnswer));
      expect(punctuated.briefs.length, bare.briefs.length);
    });

    test('no checklist item is opened for the verdict', () {
      expect(bare.lastLedgerSnapshot.map((g) => g.query),
          isNot(contains('*NONE**')));

      expect(bold.lastLedgerSnapshot, isNotEmpty,
          reason: 'the negative assertions below only mean something while '
              'the harness is still opening ledger items at all — this is '
              'what stops them passing vacuously');
      expect(bold.lastLedgerSnapshot.map((g) => g.query),
          bare.lastLedgerSnapshot.map((g) => g.query),
          reason: 'the bold run\'s checklist is the bare run\'s checklist, '
              'item for item: the search sub-goal, and nothing the gate '
              'added');

      expect(bold.lastLedgerSnapshot.map((g) => g.query),
          isNot(contains('*NONE**')),
          reason: 'SearchAgent.run opens whatever gap it is handed with no '
              'validation (search_agent.dart:587), so the parser is the only '
              'thing standing between a mangled verdict and a research item '
              'the user sees in the panel');
      expect(bold.lastLedgerSnapshot.map((g) => g.query),
          isNot(anyElement(contains('NONE'))),
          reason: 'and no other mangling of the verdict reaches the ledger '
              'either — the check is on the token, not on one residue');
      expect(bold.briefs.last, bare.briefs.last,
          reason: 'so the brief the model is handed is byte-identical to the '
              'bare run\'s, where an open [ ] would otherwise tell it to keep '
              'searching for the gate\'s own verdict');

      expect(punctuated.lastLedgerSnapshot.map((g) => g.query),
          bare.lastLedgerSnapshot.map((g) => g.query),
          reason: 'and `**NONE**.` opens no checklist item either — the '
              'residue there was `NONE**.`, a different mangling of the same '
              'verdict');
      expect(punctuated.briefs.last, bare.briefs.last);
    });

    test('the model is never told it omitted the verdict', () {
      expect(
        bold.userMessagesInTranscript.where((m) => m.contains('NONE')),
        isEmpty,
        reason: '_gapNotice would inject a user-role message claiming the '
            'draft "did not address these parts of my question" — restating '
            'the gate\'s verdict of completeness to the model as the thing '
            'it failed to answer',
      );
      expect(
        punctuated.userMessagesInTranscript.where((m) => m.contains('NONE')),
        isEmpty,
        reason: 'nor is it told it omitted `NONE**.`',
      );
      expect(bare.userMessagesInTranscript.where((m) => m.contains('NONE')),
          isEmpty,
          reason: 'control: identical to the bare run, which is the point — '
              'the markup changes nothing');
      expect(bold.userMessagesInTranscript, bare.userMessagesInTranscript,
          reason: 'and identical in full, not merely free of the token: a '
              'weaker assertion would still pass if the gate had injected '
              'some other notice');
    });
  });
}
