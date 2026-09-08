/// Offline probe: on a turn where the search tool has already been WITHDRAWN,
/// `SearchAgent._ingestChunk` still deletes the model's finished answer just
/// because a trailing `web_search` call arrived — and the one-shot
/// forced-answer guard can only rescue that once, so the second occurrence
/// returns an EMPTY answer as a non-cancelled `hardCapReached` outcome.
///
/// The reset at search_agent.dart:867-875 is unconditional on whether tools
/// were offered this turn:
///
///     if (chunk.toolCalls != null && chunk.toolCalls!.isNotEmpty) {
///       accum.toolCalls.addAll(chunk.toolCalls!);
///       if (accum.streamedContent) {
///         listener.onResetContent?.call();
///         accum.content = '';
///         ...
///
/// That is right for the documented "preamble, then search" case (run() line
/// 424-428, and the `preamble content then tool_calls resets streamed
/// content` test in search_agent_test.dart): the prose was throat-clearing
/// ahead of a search that is about to actually run, so discarding it is
/// correct. But once `_canSearch` is false the request carries NO tools
/// (chat_provider.dart:1177 sends `tools: null`), any tool call the model
/// still emits is guaranteed to be refused, and the streamed prose is not a
/// preamble — it IS the answer. _ingestChunk deletes it anyway.
///
/// The knock-on chain, all inside run():
///   * `turn.content` is empty, so `lastContent` (line 428) never captures
///     the answer either — the "never return less than we already had"
///     fallback at line 542 has nothing to fall back on.
///   * `hasTools` is false (line 435, `canSearch` is false), so the
///     forced-answer branch at line 444 fires on a condition — `turn.content
///     .isEmpty` — that _ingestChunk manufactured. A whole extra model turn
///     is spent telling a model that already answered that "Research is
///     closed".
///   * That branch is one-shot (`!forcedAnswer`). A model that attaches a
///     trailing tool call to its answer a SECOND time falls straight through
///     to `return _outcome(turn.content.isNotEmpty ? turn.content :
///     lastContent, ...)` with both empty.
///   * The outcome is not cancelled, so ChatProvider's blank-bubble cleanup
///     (chat_provider.dart:1286, which requires `outcome.cancelled`) is
///     skipped and `streamingMessage!.content` is overwritten with '' and
///     persisted — the exact blank assistant message the forced-answer path
///     exists to prevent, reached this time with the answer in hand.
///
/// Every test below drives a real SearchAgent with fake `streamTurn` /
/// `search` callbacks. No network, no model.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Services/search_agent.dart';
import 'package:llamaseek/Services/web_search_service.dart';

const _question = 'What was Vietnam\'s GDP in 2024?';
const _answer = 'Vietnam GDP was 476 billion USD in 2024 [1].';

final _history = [
  OllamaMessage(_question, role: OllamaMessageRole.user),
];

OllamaMessage _prose(String content) =>
    OllamaMessage(content, role: OllamaMessageRole.assistant);

/// A tool-call chunk with no content of its own — the shape a real stream
/// produces, since OpenRouterCodec.parseCompletion emits `tool_calls` deltas
/// as their own chunks AFTER the content deltas that preceded them.
OllamaMessage _toolCall(String query) => OllamaMessage(
      '',
      role: OllamaMessageRole.assistant,
      toolCalls: [
        OllamaToolCall(name: 'web_search', arguments: {'query': query}),
      ],
    );

WebSearchResult _hit(String url) => WebSearchResult(
      title: 'Vietnam GDP',
      snippet: 'Vietnam GDP 2024',
      url: url,
      pageContent: 'Vietnam GDP reached 476 billion USD in 2024.',
    );

/// What one run observed, from the loop and from the UI's point of view.
class _Run {
  final SearchAgentOutcome outcome;

  /// `SearchAgentRequest.toolsEnabled` for each model turn, in order.
  final List<bool> toolsEnabled;

  /// Every `onContent` delta the UI was handed, in order.
  final List<String> contentDeltas;

  /// How many times the UI was told to blank the in-flight bubble.
  final int resets;

  /// The bubble text a ChatProvider-shaped consumer would be left holding:
  /// deltas appended, wiped to '' on every onResetContent.
  final String bubble;

  final int turns;

  const _Run({
    required this.outcome,
    required this.toolsEnabled,
    required this.contentDeltas,
    required this.resets,
    required this.bubble,
    required this.turns,
  });
}

/// Drives a real SearchAgent whose budget is one search.
///
/// Turn 1 is a bare `web_search` call, which spends the entire budget, so
/// every later turn arrives with `toolsEnabled: false`. Each of those later
/// turns streams the complete answer and then — if [trailingToolCallOnTurn]
/// says so — one more `web_search` call.
Future<_Run> _drive({
  required bool Function(int turn) trailingToolCallOnTurn,
}) async {
  final toolsEnabled = <bool>[];
  final contentDeltas = <String>[];
  var resets = 0;
  var bubble = '';
  var turn = 0;

  final agent = SearchAgent(
    maxSearches: 1,
    streamTurn: (request) async* {
      turn++;
      toolsEnabled.add(request.toolsEnabled);
      if (turn == 1) {
        yield _toolCall('Vietnam GDP 2024');
        return;
      }
      // The answer, streamed in pieces exactly as a real stream delivers it.
      yield _prose('Vietnam GDP was ');
      yield _prose('476 billion USD in 2024 [1].');
      if (trailingToolCallOnTurn(turn)) {
        yield _toolCall('Vietnam GDP 2024 confirmation');
      }
    },
    search: (request) async => [_hit('https://example.com/vn-gdp')],
  );

  final outcome = await agent.run(
    history: _history,
    listener: SearchAgentListener(
      onContent: (delta) {
        contentDeltas.add(delta);
        bubble += delta;
      },
      onResetContent: () {
        resets++;
        bubble = '';
      },
    ),
  );

  return _Run(
    outcome: outcome,
    toolsEnabled: toolsEnabled,
    contentDeltas: contentDeltas,
    resets: resets,
    bubble: bubble,
    turns: turn,
  );
}

void main() {
  group('a trailing tool call on a tools-withdrawn turn deletes the answer',
      () {
    late _Run run;

    setUpAll(() async {
      // Every tools-withdrawn turn ends with a trailing web_search call.
      run = await _drive(trailingToolCallOnTurn: (_) => true);
    });

    test('the tool really was withdrawn for turns 2 and 3', () {
      expect(run.toolsEnabled, [true, false, false],
          reason: 'maxSearches (1) was spent by turn 1, so _canSearch is '
              'false from turn 2 on and SearchAgentRequest.toolsEnabled is '
              'false — the request carries no web_search tool at all '
              '(chat_provider.dart sends `tools: null`), so the tool calls '
              'turns 2 and 3 emit CANNOT be honoured. Their prose is the '
              'answer, not a preamble to a search that is about to run.');
      expect(run.turns, 3,
          reason: 'the run took three model turns: one search, then two '
              'tools-withdrawn turns that each produced a complete answer');
    });

    test('the model DID stream the complete answer on both closed turns', () {
      expect(run.contentDeltas.join(), '$_answer$_answer',
          reason: 'onContent delivered the full answer twice — the run had '
              'the finished answer in hand on turn 2 AND on turn 3. Nothing '
              'about this outcome is the model failing to answer.');
    });

    test('_ingestChunk blanked it both times, on screen and in the accumulator',
        () {
      expect(run.resets, 2,
          reason: 'onResetContent fired once per closed turn. In ChatProvider '
              'that callback sets streamingMessage!.content = \'\', so the '
              'user watched the complete answer render and then vanish, '
              'twice.');
      expect(run.bubble, isEmpty,
          reason: 'replaying the deltas and the resets the way ChatProvider '
              'does leaves the bubble empty: the last thing that happened to '
              'it was a wipe, not a token.');
    });

    test('the run returns an EMPTY answer, uncancelled, as hardCapReached', () {
      expect(run.outcome.content, isEmpty,
          reason: 'THE DEFECT. run() returned `turn.content.isNotEmpty ? '
              'turn.content : lastContent` and both are empty — turn.content '
              'because _ingestChunk cleared it, lastContent because line 428 '
              'only captures a turn whose content is non-empty and so never '
              'saw the answer either. The one-shot forced-answer guard '
              '(!forcedAnswer) was already spent on turn 2, so turn 3 had no '
              'second rescue.');
      expect(run.outcome.cancelled, isFalse,
          reason: 'not a cancellation — this is the loop\'s normal '
              'termination path.');
      expect(run.outcome.reason, SearchTerminationReason.hardCapReached,
          reason: 'reported to the user as "search budget reached", which '
              'says nothing about an answer having been produced and thrown '
              'away.');
      expect(run.outcome.searchCount, 1,
          reason: 'research really did happen and really did find the '
              'source — the evidence is dropped on the floor with the '
              'answer that cited it');
    });

    test('ChatProvider would persist the blank bubble rather than remove it',
        () {
      // chat_provider.dart:1286 removes a blank in-flight bubble only when
      // `outcome.cancelled` is true; then line 1311 overwrites
      // streamingMessage!.content with outcome.content unconditionally.
      final cleanupFires = run.outcome.cancelled &&
          run.outcome.content.isEmpty &&
          run.bubble.isEmpty;
      expect(cleanupFires, isFalse,
          reason: 'the blank-bubble cleanup is gated on outcome.cancelled, '
              'which is false here, so it does NOT fire — and the assignment '
              'below it writes outcome.content (\'\') into the message that '
              'then gets persisted. The user is left with a saved, blank '
              'assistant turn: exactly the failure the forced-answer path '
              'and commit dd4ed25 exist to prevent.');
    });
  });

  group('control: the identical run without the trailing tool call', () {
    test('turn 3 omitting the tool call returns the very same prose', () async {
      // Byte-for-byte the same stream except turn 3 stops after its prose.
      // Turn 2 still ends with a trailing tool call, so the forced-answer
      // guard is still spent — the ONLY difference is that final tool call.
      final control = await _drive(trailingToolCallOnTurn: (turn) => turn == 2);

      expect(control.toolsEnabled, [true, false, false],
          reason: 'same shape as the failing run: three turns, tools '
              'withdrawn after the first');
      expect(control.outcome.content, _answer,
          reason: 'ISOLATION. The same model prose, on the same closed turn, '
              'of the same run, survives intact when the trailing '
              'web_search call is removed. The tool call — refused before it '
              'could ever run — is the entire cause of the empty answer '
              'above.');
      expect(control.outcome.reason, SearchTerminationReason.hardCapReached,
          reason: 'same termination reason, so the reason code is not what '
              'differs between the two runs');
      expect(control.bubble, _answer,
          reason: 'the UI bubble survives too: one reset (turn 2\'s trailing '
              'call) and then the answer streams again uninterrupted');
      expect(control.resets, 1,
          reason: 'only turn 2 blanked the bubble in the control; the '
              'failing run blanked it twice');
    });

    test('a single trailing tool call is survivable — the guard covers it',
        () async {
      // Turn 2 only. This is the case the forced-answer branch was written
      // for, and it works: proof that the defect is specifically the guard's
      // one-shot-ness meeting a repeatable model habit, not tool calls after
      // withdrawal per se.
      final once = await _drive(trailingToolCallOnTurn: (turn) => turn == 2);
      expect(once.outcome.content, isNotEmpty,
          reason: 'the FIRST trailing tool call is recovered by the '
              'forced-answer branch — at the cost of a wasted model turn and '
              'a bubble the user watched go blank. The second one is not '
              'recovered at all.');
    });
  });
}
