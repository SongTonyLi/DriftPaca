/// Offline regression: a research turn is **bounded and stoppable**. The
/// loop now ends a turn that has gone silent, and reads the stop button
/// whether or not chunks are arriving.
///
/// The hole this file was written for (audit finding #1) was a single line
/// — `await for (final chunk in streamTurn(request))` in
/// `SearchAgent._streamOneTurn` — which tied both liveness checks to chunk
/// arrival:
///
///   * There was no deadline of any kind. `search_agent.dart` did not even
///     import `dart:async`. A provider that opened a stream and then said
///     nothing left `run()` waiting forever.
///
///   * `isCancelled` was evaluated only in the loop body, i.e. only when a
///     chunk arrived — never on the exact streams the check exists to
///     escape. Pressing stop on a stalled run did nothing: it removed the
///     chat from `_activeChatStreams` while the run itself kept going,
///     ready to write into `_messages` alongside whatever the user sent
///     next.
///
/// No lower layer compensated. No chat or generate call in `OllamaService`
/// carries a timeout, and the one signal that would reach a transport-level
/// one — OpenRouter's `: OPENROUTER PROCESSING` keep-alive — is dropped by
/// `OpenRouterCodec.decodeSseJson` before it can become a chunk, so a socket
/// timeout sees a healthy stream while the loop sees silence. The turn loop
/// is the only layer that can tell "slow" from "stalled", which is why the
/// deadline belongs here and not on the HTTP request.
///
/// What is guaranteed now:
///
///   1. `run()` returns within [SearchAgent.turnIdleBudget] of the last
///      chunk any turn produced, for every stream `streamTurn` can hand it
///      — including one that never emits and never closes.
///   2. Once `isCancelled()` is true, `run()` returns within ~200ms whether
///      or not the turn is delivering anything.
///   3. Neither path throws, and both keep every completed round's searches
///      and sources plus any prose already streamed.
///   4. The abandoned subscription is always cancelled, and never awaited.
///   5. The budget measures SILENCE: a turn still emitting is never cut off,
///      however long it runs in total.
///   6. Stream errors still propagate to the caller unchanged.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_exception.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Services/search_agent.dart';
import 'package:llamaseek/Services/web_search_service.dart';

final _history = [
  OllamaMessage('What is Vietnam GDP?', role: OllamaMessageRole.user),
];

OllamaMessage _answer(String content) =>
    OllamaMessage(content, role: OllamaMessageRole.assistant);

OllamaMessage _search(String query) => OllamaMessage(
      '',
      role: OllamaMessageRole.assistant,
      toolCalls: [
        OllamaToolCall(name: 'web_search', arguments: {'query': query}),
      ],
    );

WebSearchResult _hit(String url) => WebSearchResult(
      title: 'T',
      snippet: 'S',
      url: url,
      pageContent: 'body',
    );

SearchAgent _agent({
  required Stream<OllamaMessage> Function(SearchAgentRequest) streamTurn,
  required Duration turnIdleBudget,
  Future<List<WebSearchResult>> Function(SearchAgentSearchRequest)? search,
}) =>
    SearchAgent(
      turnIdleBudget: turnIdleBudget,
      streamTurn: streamTurn,
      search: search ?? (req) async => [_hit('https://example.com/${req.query}')],
    );

/// The shape of the failure: a stream that is open, has no error, and will
/// never produce anything. Closed by the test's tearDown, never by the
/// loop — the loop is what has to walk away from it.
class _SilentTurn {
  final StreamController<OllamaMessage> controller;
  var cancelled = false;

  _SilentTurn._(this.controller);

  factory _SilentTurn() {
    late _SilentTurn self;
    final controller = StreamController<OllamaMessage>(
      onCancel: () => self.cancelled = true,
    );
    self = _SilentTurn._(controller);
    return self;
  }

  Stream<OllamaMessage> get stream => controller.stream;

  Future<void> dispose() => controller.close();
}

void main() {
  group('a stalled research turn', () {
    test('a turn that never delivers a chunk ends the run instead of hanging',
        () async {
      final turn = _SilentTurn();
      addTearDown(turn.dispose);
      final reported = <SearchTerminationReason>[];

      final outcome = await _agent(
        streamTurn: (_) => turn.stream,
        turnIdleBudget: const Duration(milliseconds: 50),
      )
          .run(
            history: _history,
            listener: SearchAgentListener(onResearchDone: reported.add),
          )
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => fail('run() never returned — the turn is still '
                'unbounded, which is the whole finding'),
          );

      expect(outcome.reason, SearchTerminationReason.stalled,
          reason: 'the provider went quiet; no cap tripped and nobody '
              'pressed stop, so neither of those may be reported instead');
      expect(outcome.cancelled, isTrue,
          reason: 'ChatProvider reads `cancelled` as "this run did not '
              'finish normally, do not keep an empty bubble" — a stall needs '
              'exactly that cleanup, and `reason` carries the honest why');
      expect(reported, [SearchTerminationReason.stalled],
          reason: 'the run still reports a termination reason, so the '
              'research panel closes instead of spinning forever');
    });

    test('everything the run already established survives the stall',
        () async {
      final silence = _SilentTurn();
      addTearDown(silence.dispose);
      var turns = 0;

      final outcome = await _agent(
        streamTurn: (_) {
          turns++;
          if (turns == 1) {
            return Stream.fromIterable([_search('Vietnam GDP')]);
          }
          return silence.stream;
        },
        turnIdleBudget: const Duration(milliseconds: 50),
        search: (req) async => [_hit('https://example.com/vn')],
      ).run(history: _history, listener: const SearchAgentListener()).timeout(
            const Duration(seconds: 2),
            onTimeout: () => fail('run() never returned from the silent turn'),
          );

      expect(outcome.searchCount, 1,
          reason: 'the search in round 1 really ran and its results were '
              'really shown; a later turn going quiet cannot un-run it');
      expect(outcome.sourceUrls[1], 'https://example.com/vn',
          reason: 'the sweep reported zero searches for a stalled cell only '
              'because it abandoned the run and never got an outcome at all '
              '— given an outcome, the accounting was always right');
    });

    test('a partial answer streamed before the silence is kept', () async {
      final controller = StreamController<OllamaMessage>();
      addTearDown(controller.close);
      controller.add(_answer('Vietnam GDP was '));

      final outcome = await _agent(
        streamTurn: (_) => controller.stream,
        turnIdleBudget: const Duration(milliseconds: 50),
      ).run(history: _history, listener: const SearchAgentListener()).timeout(
            const Duration(seconds: 2),
            onTimeout: () => fail('run() never returned from the silent turn'),
          );

      expect(outcome.content, 'Vietnam GDP was ',
          reason: 'the same take-what-we-have rule a cancelled run follows: '
              'half an answer the user can already read beats blanking the '
              'bubble because the rest never came');
      expect(outcome.reason, SearchTerminationReason.stalled,
          reason: 'prose arriving before the silence does not make the turn '
              'a normal one — the idle timer is re-armed by a chunk, not '
              'disarmed');
    });

    test('a slow turn that is still emitting is not cut off', () async {
      // The budget measures SILENCE. This turn runs for twice the budget in
      // total but never goes quiet for more than a fraction of it, which is
      // what a reasoning model working through a long answer looks like.
      const gap = Duration(milliseconds: 25);
      const chunks = 20;

      final outcome = await _agent(
        streamTurn: (_) async* {
          for (var i = 0; i < chunks; i++) {
            await Future<void>.delayed(gap);
            yield _answer('$i ');
          }
        },
        turnIdleBudget: const Duration(milliseconds: 250),
      ).run(history: _history, listener: const SearchAgentListener());

      expect(outcome.reason, SearchTerminationReason.converged,
          reason: 'a total-time cap would have killed this turn at chunk 10; '
              'an idle deadline must not, or every long answer becomes a '
              'stall');
      expect(outcome.content, [for (var i = 0; i < chunks; i++) '$i '].join(),
          reason: 'and not one delta may be dropped on the way');
    });

    test('the abandoned request is cancelled, not left running', () async {
      final turn = _SilentTurn();
      addTearDown(turn.dispose);

      await _agent(
        streamTurn: (_) => turn.stream,
        turnIdleBudget: const Duration(milliseconds: 50),
      ).run(history: _history, listener: const SearchAgentListener()).timeout(
            const Duration(seconds: 2),
            onTimeout: () => fail('run() never returned from the silent turn'),
          );
      await Future<void>.delayed(Duration.zero);

      expect(turn.cancelled, isTrue,
          reason: 'walking away from the wait without cancelling the request '
              'would leave the model busy — on a local server, busy with the '
              'very model the next turn needs');
    });

    test('a provider error still reaches the caller', () async {
      final controller = StreamController<OllamaMessage>();
      addTearDown(controller.close);
      controller.addError(OllamaException('rate limited'));

      await expectLater(
        _agent(
          streamTurn: (_) => controller.stream,
          turnIdleBudget: const Duration(seconds: 30),
        ).run(history: _history, listener: const SearchAgentListener()),
        throwsA(isA<OllamaException>()),
        reason: 'await for propagated stream errors for free; the listen '
            'rewrite has to route them through the completer explicitly, or '
            'a 401 stops reaching the chat\'s error banner and the run '
            'silently waits out its idle budget instead',
      );
    });
  });

  group('stopping a research turn', () {
    test('the stop button ends a run whose turn has gone silent', () async {
      // The half the deadline cannot cover: the user should not have to wait
      // out a three-minute budget for work they have already walked away
      // from. Before the fix this never returned at all.
      final turn = _SilentTurn();
      addTearDown(turn.dispose);
      var cancelled = false;
      Timer(const Duration(milliseconds: 50), () => cancelled = true);

      final started = DateTime.now();
      final outcome = await _agent(
        streamTurn: (_) => turn.stream,
        turnIdleBudget: const Duration(seconds: 30),
      )
          .run(
            history: _history,
            listener: const SearchAgentListener(),
            isCancelled: () => cancelled,
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => fail('pressing stop did not reach a turn that '
                'was delivering nothing'),
          );
      final elapsed = DateTime.now().difference(started);

      expect(outcome.reason, SearchTerminationReason.cancelled,
          reason: 'the user stopped this run; reporting the provider stalled '
              'would blame the wrong party');
      expect(outcome.cancelled, isTrue);
      expect(elapsed, lessThan(const Duration(seconds: 2)),
          reason: 'the 200ms poll, not the 30s budget, is what ended it — a '
              'run that merely waited out its deadline would take 30s here');
    });

    test('the abandoned request is cancelled on the stopped path too',
        () async {
      final turn = _SilentTurn();
      addTearDown(turn.dispose);
      var cancelled = false;
      Timer(const Duration(milliseconds: 50), () => cancelled = true);

      await _agent(
        streamTurn: (_) => turn.stream,
        turnIdleBudget: const Duration(seconds: 30),
      )
          .run(
            history: _history,
            listener: const SearchAgentListener(),
            isCancelled: () => cancelled,
          )
          .timeout(const Duration(seconds: 5),
              onTimeout: () => fail('pressing stop did not reach the turn'));
      await Future<void>.delayed(Duration.zero);

      expect(turn.cancelled, isTrue,
          reason: 'a stopped run that leaves its request in flight is the '
              'zombie case: cancelCurrentStreaming() only clears the chat id, '
              'so the run itself keeps writing into the same message list');
    });
  });
}
