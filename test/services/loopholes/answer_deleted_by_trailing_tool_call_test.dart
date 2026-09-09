/// Offline regression: on a turn where the search tool has already been
/// WITHDRAWN, `SearchAgent` keeps every token the model streams — even when
/// the model attaches a trailing `web_search` call the loop is guaranteed to
/// refuse.
///
/// Both of `_ingestChunk`'s content-discard rules are gated on
/// `_TurnAccum.toolsEnabled`, the flag that mirrors
/// `SearchAgentRequest.toolsEnabled` — which ChatProvider turns straight into
/// `tools:` / `tools: null` on the wire:
///
///     if (accum.toolsEnabled && accum.streamedContent) {
///       listener.onResetContent?.call();
///       accum.content = '';
///       ...
///     if (chunk.content.isNotEmpty &&
///         (!accum.toolsEnabled || accum.toolCalls.isEmpty)) {
///
/// Discarding prose is right only in the "preamble, then search" case, where
/// the tool is live, the search really is about to run, and the prose was
/// throat-clearing — run()'s `hasTools` path, pinned by the `preamble content
/// then tool_calls resets streamed content` test in search_agent_test.dart.
/// Once `_canSearch` is false the request carries no tools at all
/// (chat_provider.dart sends `tools: null`), `hasTools` refuses any call the
/// model still emits, and the turn was briefed with
/// `ResearchLedger.closedRule` ("Research is closed... Write the answer now").
/// The prose is then not a preamble to anything — it IS the answer, and it is
/// kept.
///
/// What the unconditional rule used to cost, and what the groups below now
/// pin shut, all inside run():
///   * `_ingestChunk` deleted the answer, so `turn.content` was empty and
///     `lastContent` never captured it either — the "never return less than
///     we already had" fallback had nothing to fall back on.
///   * The forced-answer branch then fired on an emptiness `_ingestChunk`
///     had manufactured, spending a whole model turn to tell a model that had
///     just answered that research was closed.
///   * That branch is one-shot, so a second such turn fell straight through
///     to a non-cancelled, EMPTY `hardCapReached` outcome. ChatProvider's
///     blank-bubble cleanup requires `outcome.cancelled`, so it was skipped
///     and the empty content was written into the bubble and persisted — the
///     blank assistant message commit dd4ed25 exists to prevent, reached this
///     time with the answer in hand.
///
/// The last group pins where the fix stops: a withdrawn turn that streams no
/// prose at all still gets dd4ed25's forced-answer rescue, and a tool call
/// after a preamble on a tools-LIVE turn still wipes the preamble.
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
const _preamble = 'Let me look that up.';
const _sourceUrl = 'https://example.com/vn-gdp';

/// Wording unique to the forced-answer branch's tool reply. It cannot be
/// matched on "Research is closed": ResearchLedger.closedRule opens with the
/// same words, and the rendered ledger is appended to a tool-role transcript
/// message on every withdrawn turn — so that phrase is present whether or not
/// the one-shot rescue ever fired.
const _forcedAnswerMarker = 'Answer now using the sources already provided';

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

  /// Whether any request's transcript carried the forced-answer branch's
  /// "Research is closed" tool reply — i.e. whether run()'s one-shot rescue
  /// was spent on this run.
  final bool forcedAnswerSpent;

  const _Run({
    required this.outcome,
    required this.toolsEnabled,
    required this.contentDeltas,
    required this.resets,
    required this.bubble,
    required this.turns,
    required this.forcedAnswerSpent,
  });
}

/// Every tools-withdrawn turn streams the answer unless a test says otherwise.
bool _always(int turn) => true;

/// Drives a real SearchAgent whose budget is one search.
///
/// Turn 1 is a `web_search` call — optionally preceded by [preambleOnTurn1],
/// which is a genuine preamble because the tool is still live on that turn —
/// and it spends the entire budget, so every later turn arrives with
/// `toolsEnabled: false`. Each of those later turns streams the complete
/// answer, unless [proseOnClosedTurn] says otherwise, and then — if
/// [trailingToolCallOnTurn] says so — one more `web_search` call.
Future<_Run> _drive({
  required bool Function(int turn) trailingToolCallOnTurn,
  bool Function(int turn) proseOnClosedTurn = _always,
  String preambleOnTurn1 = '',
}) async {
  final toolsEnabled = <bool>[];
  final contentDeltas = <String>[];
  var resets = 0;
  var bubble = '';
  var turn = 0;
  var forcedAnswerSpent = false;

  final agent = SearchAgent(
    maxSearches: 1,
    streamTurn: (request) async* {
      turn++;
      toolsEnabled.add(request.toolsEnabled);
      forcedAnswerSpent |= request.transcript.any((message) =>
          message.role == OllamaMessageRole.tool &&
          message.content.contains(_forcedAnswerMarker));
      if (turn == 1) {
        if (preambleOnTurn1.isNotEmpty) yield _prose(preambleOnTurn1);
        yield _toolCall('Vietnam GDP 2024');
        return;
      }
      if (proseOnClosedTurn(turn)) {
        // The answer, streamed in pieces exactly as a real stream delivers it.
        yield _prose('Vietnam GDP was ');
        yield _prose('476 billion USD in 2024 [1].');
      }
      if (trailingToolCallOnTurn(turn)) {
        yield _toolCall('Vietnam GDP 2024 confirmation');
      }
    },
    search: (request) async => [_hit(_sourceUrl)],
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
    forcedAnswerSpent: forcedAnswerSpent,
  );
}

void main() {
  group(
      'a trailing tool call on a tools-withdrawn turn no longer deletes the '
      'answer', () {
    late _Run run;

    setUpAll(() async {
      // Every tools-withdrawn turn ends with a trailing web_search call.
      run = await _drive(trailingToolCallOnTurn: (_) => true);
    });

    test('the tool really was withdrawn for turn 2', () {
      expect(run.toolsEnabled, [true, false],
          reason: 'maxSearches (1) was spent by turn 1, so _canSearch is '
              'false from turn 2 on and SearchAgentRequest.toolsEnabled is '
              'false — the request carries no web_search tool at all '
              '(chat_provider.dart sends `tools: null`), so the tool call '
              'turn 2 emits CANNOT be honoured. Its prose is the answer, not '
              'a preamble to a search that is about to run.');
      expect(run.turns, 2,
          reason: 'one search turn, then one tools-withdrawn turn that '
              'answered. The third turn this run used to take was the '
              'forced-answer retry, spent telling a model that had just '
              'answered that research was closed — unnecessary now that turn '
              '2\'s answer survives, so the run is a model turn cheaper.');
    });

    test('the model DID stream the complete answer on the closed turn', () {
      expect(run.contentDeltas.join(), _answer,
          reason: 'onContent delivered the full answer exactly once: the run '
              'had the finished answer in hand on turn 2, and no second '
              'closed turn was needed to produce it again. Nothing about '
              'this outcome is the model failing to answer.');
    });

    test('_ingestChunk keeps it, on screen and in the accumulator', () {
      expect(run.resets, 0,
          reason: 'onResetContent must never fire for a tool call that '
              'cannot run. In ChatProvider that callback sets '
              'streamingMessage!.content = \'\', which is the user watching '
              'a complete, cited answer render and then vanish.');
      expect(run.bubble, _answer,
          reason: 'replaying the deltas and the resets the way ChatProvider '
              'does leaves the finished answer in the bubble: nothing wiped '
              'it.');
    });

    test('the run returns the ANSWER, uncancelled, as hardCapReached', () {
      expect(run.outcome.content, _answer,
          reason: 'run() returns `turn.content.isNotEmpty ? turn.content : '
              'lastContent`, and turn.content now holds what the model '
              'streamed because _ingestChunk no longer clears it on a '
              'tools-withdrawn turn. The refused call is simply dropped.');
      expect(run.outcome.cancelled, isFalse,
          reason: 'not a cancellation — this is the loop\'s normal '
              'termination path.');
      expect(run.outcome.reason, SearchTerminationReason.hardCapReached,
          reason: 'the search budget genuinely is spent, so the reason code '
              'is not what the fix changes — only the content it ships '
              'with.');
      expect(run.outcome.searchCount, 1,
          reason: 'research really did happen, and the answer citing it is '
              'now returned alongside it');
      expect(run.outcome.sourceUrls.values, contains(_sourceUrl),
          reason: 'the [1] in the answer resolves to the source the single '
              'search found: the evidence and the answer survive together');
    });

    test('ChatProvider has no blank bubble to persist', () {
      // chat_provider.dart writes outcome.content into streamingMessage and
      // persists it; its blank-bubble cleanup above that is gated on
      // outcome.cancelled (and on the bubble having no thinking, which a
      // search round has already made false).
      expect(run.outcome.content, isNotEmpty,
          reason: 'a non-empty outcome is the whole difference between a '
              'saved answer and a saved blank assistant turn');
      expect(run.bubble, isNotEmpty,
          reason: 'the in-flight bubble is non-empty too, so the '
              'blank-bubble cleanup question never arises — avoiding the '
              'blank message no longer depends on that gate at all');
    });
  });

  group('control: the identical run without the trailing tool call', () {
    test('the run without the trailing tool call is now byte-identical',
        () async {
      // Byte-for-byte the same stream except that no closed turn appends a
      // web_search call. A refused call must make no observable difference.
      final withCall = await _drive(trailingToolCallOnTurn: (_) => true);
      final control = await _drive(trailingToolCallOnTurn: (_) => false);

      expect(control.toolsEnabled, withCall.toolsEnabled,
          reason: 'same shape: one search turn, then one tools-withdrawn '
              'turn');
      expect(control.turns, withCall.turns,
          reason: 'ISOLATION. The trailing call no longer buys the run an '
              'extra forced-answer turn.');
      expect(control.outcome.content, withCall.outcome.content,
          reason: 'ISOLATION. The same model prose, on the same closed turn '
              'of the same run, survives intact whether or not a refused '
              'web_search call is appended to it. The call — refused before '
              'it could ever run — is now invisible to the answer, which is '
              'the strongest form of the isolation this file used to state '
              'as a defect.');
      expect(control.outcome.reason, withCall.outcome.reason,
          reason: 'same termination reason either way');
      expect(control.resets, withCall.resets,
          reason: 'neither run blanks the bubble; a call that cannot run is '
              'not a reason to');
      expect(control.bubble, withCall.bubble,
          reason: 'and the UI is left holding the same text either way');
    });

    test('a single trailing tool call no longer needs the forced-answer guard',
        () async {
      // The forced-answer branch was written for a withdrawn turn with NO
      // prose (the next group covers that). A withdrawn turn that answered
      // and then asked to search must not consume the one-shot rescue.
      final once = await _drive(trailingToolCallOnTurn: (turn) => turn == 2);

      expect(once.outcome.content, _answer,
          reason: 'the answer is returned directly, not recovered a turn '
              'later at the cost of a bubble the user watched go blank');
      expect(once.turns, 2, reason: 'no forced-answer retry ran');
      expect(once.forcedAnswerSpent, isFalse,
          reason: 'no request ever carried the forced-answer branch\'s tool '
              'reply, so the one-shot guard is still unspent and available '
              'for the turn it was written for — a model that emits a tool '
              'call and no prose at all');
    });
  });

  group('the fix stops exactly where the discard is still right', () {
    test(
        'the forced-answer rescue still covers a genuinely blank withdrawn '
        'turn', () async {
      // dd4ed25's case, unchanged: turn 2 is withdrawn and emits ONLY a tool
      // call, so turn.content really is empty and the rescue must fire.
      final blank = await _drive(
        trailingToolCallOnTurn: (_) => true,
        proseOnClosedTurn: (turn) => turn != 2,
      );

      expect(blank.toolsEnabled, [true, false, false],
          reason: 'the forced-answer turn is a third model turn, also with '
              'the tool withdrawn');
      expect(blank.turns, 3,
          reason: 'gating the discard on toolsEnabled must not disarm the '
              'rescue: a withdrawn turn that produces no prose is still told '
              'research is closed and given one more turn to answer');
      expect(blank.forcedAnswerSpent, isTrue,
          reason: 'the "Research is closed" tool reply really was fed back, '
              'which is what keeps the dangling tool_call well-formed');
      expect(blank.outcome.content, _answer,
          reason: 'and turn 3 answers — the blank message dd4ed25 exists to '
              'prevent is still prevented');
    });

    test('a live tool call after a preamble still wipes the preamble',
        () async {
      // Turn 1 has the tool live, so its prose IS throat-clearing ahead of a
      // search that actually runs, and discarding it is still correct.
      final preambled = await _drive(
        trailingToolCallOnTurn: (_) => true,
        preambleOnTurn1: _preamble,
      );

      expect(preambled.resets, 1,
          reason: 'exactly one reset, and it belongs to turn 1: the '
              'tools-enabled preamble. Turn 2\'s refused call adds none.');
      expect(preambled.outcome.content, _answer,
          reason: 'the preamble is not part of the answer');
      expect(preambled.outcome.content, isNot(contains(_preamble)),
          reason: 'GUARDRAIL. Prose the model wrote ahead of a search that '
              'actually ran is throat-clearing, never part of the answer. If '
              'this starts containing "Let me look that up.", the '
              'toolsEnabled gate has been inverted and the discard is firing '
              'on exactly the wrong turns.');
      expect(preambled.bubble, _answer,
          reason: 'the UI shows the answer alone, exactly as before the fix');
    });
  });
}
