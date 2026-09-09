/// Offline regression: an OpenRouter **HTTP 200 error frame** (`data: {"error":
/// {...}}`, which is how OpenRouter reports a provider or rate-limit failure
/// that happens *after* streaming has begun) is raised out of the transport as
/// an [OllamaException], exactly like the same failure arriving with a non-200
/// status — so the research loop can no longer present it as a finished run.
///
/// The hole this file was written for spanned two files and neither half was
/// enough on its own:
///
///   * `OpenRouterCodec.decodeSseJson` accepts any well-formed JSON `data:`
///     payload — its contract is unchanged — and `parseCompletion` reads only
///     `choices`, so a frame with none of them falls through to the empty-map
///     default and yields `OllamaMessage('', done: false, toolCalls: null)`.
///     Nothing in between read the top-level `error` key, so the failure text
///     was dropped, and `OllamaService._openRouterChatStream`'s status-code
///     guards could not help either: the HTTP status is 200.
///
///   * `SearchAgent.run` then saw a turn with no content and no tool calls.
///     The forced-answer branch needs non-empty `toolCalls`; the coverage gate
///     needs non-empty `content`; so both were skipped and
///     `_terminationReason(canSearch: true, ...)` returned `converged`. A dead
///     provider was reported to the user as a finished research run with a
///     blank answer (audit finding #12).
///
/// What is guaranteed now: [OpenRouterCodec.errorFrom] names the failure, the
/// transport raises it before the tool-call assembler or `parseCompletion`
/// ever see the frame, `SearchAgent.run` propagates it instead of returning a
/// termination reason, and `ChatProvider` records it as a chat error rather
/// than persisting a blank assistant bubble.
///
/// Deliberately unchanged: a model that legitimately streams nothing still
/// converges with empty content. That is now the ONLY way an empty converged
/// outcome can happen, which is what makes the two distinguishable.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_exception.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Services/ollama_service.dart';
import 'package:llamaseek/Services/openrouter_codec.dart';
import 'package:llamaseek/Services/search_agent.dart';
import 'package:llamaseek/Services/web_search_service.dart';

/// The exact shape OpenRouter emits when a provider fails mid-stream: HTTP
/// 200, one `data:` frame carrying only an `error` object, then `[DONE]`.
const _errorFrameBody = 'data: {"error":{"code":429,"message":"Provider '
    'returned error: rate limited","metadata":{"provider_name":"Together"}}}\n'
    '\n'
    'data: [DONE]\n\n';

OllamaService _serviceReturning(String body, {int status = 200}) =>
    OllamaService(
      client: MockClient((_) async => http.Response(
            body,
            status,
            headers: {'content-type': 'text/event-stream'},
          )),
    )
      ..isOpenRouterMode = true
      ..apiKey = 'or-key';

Stream<OllamaMessage> _turnOn(OllamaService service) => service.chatStream(
      [OllamaMessage('Hi', role: OllamaMessageRole.user)],
      chat: OllamaChat(model: 'openai/gpt-4o-mini'),
    );

/// A loop whose only model turn is [turn], with search stubbed out so any call
/// to it would be visible as a non-zero `searchCount`.
///
/// [turn] is handed to `streamTurn` as-is rather than pre-drained into a list:
/// a turn stream that ERRORS is the case under test, and draining it first
/// would move the failure out of the loop and into the test harness.
SearchAgent _agentOn(Stream<OllamaMessage> Function() turn) => SearchAgent(
      streamTurn: (_) => turn(),
      search: (_) async => <WebSearchResult>[],
    );

Future<SearchAgentOutcome> _runLoopOn(
  SearchAgent agent,
  List<SearchTerminationReason> reported,
) =>
    agent.run(
      history: [
        OllamaMessage(
          'Compare the 2024 revenue of Nvidia and AMD, with sources.',
          role: OllamaMessageRole.user,
        ),
      ],
      listener: SearchAgentListener(onResearchDone: reported.add),
    );

void main() {
  group('OpenRouter 200-status error frame', () {
    test('the codec reports the frame as a provider error, not a completion',
        () {
      const line = 'data: {"error":{"code":429,"message":"rate limited"}}';

      final decoded = OpenRouterCodec.decodeSseJson(line);
      expect(decoded, isNotNull,
          reason: 'decodeSseJson accepts the frame purely because it is '
              'well-formed JSON — its contract is deliberately unchanged, so '
              'the frame still has to be recognized one layer up');
      expect(decoded!['error'], isNotNull,
          reason: 'the frame carries an error and no choices at all');

      final error = OpenRouterCodec.errorFrom(decoded);
      expect(error, isNotNull,
          reason: 'the top-level error key is the only signal there is that '
              'this 200 response is a failure');
      expect(error!.code, 429,
          reason: 'the numeric code is kept so the failure can be formatted '
              'exactly like the same code arriving as an HTTP status');
      expect(error.message, contains('rate limited'),
          reason: 'the provider text used to be dropped on the floor; it is '
              'what tells the user what actually went wrong');

      expect(
        OpenRouterCodec.errorFrom(
          OpenRouterCodec.decodeSseJson(
              'data: {"choices":[{"delta":{"content":"Hi"}}]}')!,
        ),
        isNull,
        reason: 'an ordinary content delta is not a failure',
      );
      expect(
        OpenRouterCodec.errorFrom(
          OpenRouterCodec.decodeSseJson(
              'data: {"error":null,"choices":[{"delta":{"content":"Hi"}}]}')!,
        ),
        isNull,
        reason: 'OpenAI-compatible providers put a null error key on healthy '
            'chunks — treating that as a failure would kill every working '
            'stream, which is the false positive this check must not have',
      );
    });

    test('chatStream throws instead of yielding an empty message', () async {
      final service = _serviceReturning(_errorFrameBody);

      await expectLater(
        _turnOn(service).toList(),
        throwsA(isA<OllamaException>().having(
          (e) => e.message,
          'message',
          allOf(contains('429'), contains('rate limited')),
        )),
        reason: 'a caller draining chatStream now gets the same signal a '
            'non-200 failure gives it, carrying the provider text the old '
            'code silently discarded',
      );
    });

    test('content already streamed is kept, and the error still ends the run',
        () async {
      final service = _serviceReturning(
        'data: {"choices":[{"delta":{"content":"Half an "}}]}\n\n'
        'data: {"choices":[{"delta":{"content":"answer"}}]}\n\n'
        '$_errorFrameBody',
      );

      final streamed = <String>[];
      Object? thrown;
      try {
        await for (final chunk in _turnOn(service)) {
          streamed.add(chunk.content);
        }
      } catch (error) {
        thrown = error;
      }

      expect(streamed, ['Half an ', 'answer'],
          reason: 'the check rejects the error frame only — nothing that '
              'already reached the caller is withheld or rewritten');
      expect(thrown, isA<OllamaException>(),
          reason: 'and a successful start does not mask the failure that '
              'followed it: the stream ends in an error, not in silence');
    });

    test('a real HTTP 429 and a 200 error frame throw the same way', () async {
      final byStatus = _serviceReturning(
        jsonEncode({
          'error': {'code': 429, 'message': 'rate limited'}
        }),
        status: 429,
      );
      final byFrame = _serviceReturning(_errorFrameBody);

      final fromStatus = await _turnOn(byStatus)
          .toList()
          .then<Object?>((_) => null, onError: (Object e) => e);
      final fromFrame = await _turnOn(byFrame)
          .toList()
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(fromStatus, isA<OllamaException>());
      expect(fromFrame, isA<OllamaException>());
      expect(
        [
          (fromStatus! as OllamaException).message,
          (fromFrame! as OllamaException).message,
        ],
        everyElement(contains('Too many requests')),
        reason: 'both go through HttpErrorFormatter, so which side of the '
            'stream start the provider failed on no longer decides whether '
            'the user learns their run failed — or how it is worded',
      );
    });

    test('the non-streaming path throws too', () async {
      final service = OllamaService(
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'error': {'code': 429, 'message': 'rate limited'}
              }),
              200,
            )),
      )
        ..isOpenRouterMode = true
        ..apiKey = 'or-key';

      await expectLater(
        service.generate(
          'Name this chat',
          chat: OllamaChat(model: 'openai/gpt-4o-mini'),
        ),
        throwsA(isA<OllamaException>().having(
          (e) => e.message,
          'message',
          contains('rate limited'),
        )),
        reason: '_openRouterCompletionFromResponse rejects a 200-status error '
            'body before parseCompletion sees it, so titling and every other '
            'non-streamed call fails loudly instead of degrading silently',
      );
    });
  });

  group('what the research loop does with the error frame', () {
    test(
        'the run raises the provider error instead of reporting a converged '
        'blank answer', () async {
      // Not a hand-written OllamaMessage: the turn is the real transport
      // reading the real frame, so the loop is being fed the production path.
      final service = _serviceReturning(_errorFrameBody);
      final reported = <SearchTerminationReason>[];

      await expectLater(
        _runLoopOn(_agentOn(() => _turnOn(service)), reported),
        throwsA(isA<OllamaException>()),
        reason: 'a run whose provider died before a single search has no '
            'answer to report; it fails the way every other transport '
            'failure already does instead of inventing a successful stop',
      );
      expect(reported, isEmpty,
          reason: 'no SearchTerminationReason reaches the UI at all — and '
              'specifically not converged, which is what the research panel '
              'used to be told. There is no outcome to read a searchCount '
              'from either: the run produced none.');
    });

    test('a provider failure is no longer indistinguishable from a model that '
        'said nothing', () async {
      final service = _serviceReturning(_errorFrameBody);
      final failedReported = <SearchTerminationReason>[];
      final quietReported = <SearchTerminationReason>[];

      final quiet = await _runLoopOn(
        _agentOn(() => Stream<OllamaMessage>.value(
              OllamaMessage('', role: OllamaMessageRole.assistant, done: true),
            )),
        quietReported,
      );

      expect(quiet.reason, SearchTerminationReason.converged,
          reason: 'a model that genuinely had nothing to say still converges '
              'with empty content — the deliberate residual, and now the '
              'only way an empty converged outcome can occur');
      expect(quiet.content, isEmpty);
      expect(quietReported, [SearchTerminationReason.converged]);

      await expectLater(
        _runLoopOn(_agentOn(() => _turnOn(service)), failedReported),
        throwsA(isA<OllamaException>()),
        reason: 'the failing run takes a different exit entirely, so code '
            'above SearchAgent can tell an upstream provider failure from an '
            'ordinary empty reply — there is something to retry on and '
            'something to show the user',
      );
      expect(failedReported, isNot(quietReported),
          reason: 'the two used to be byte-identical in every field a caller '
              'could branch on; the honest one now has no termination reason '
              'at all, because there was no run to terminate normally');
    });

    test('a searchUnavailable run, by contrast, is correctly labelled',
        () async {
      // searchUnavailable is for a run whose SEARCH failed while the model
      // itself kept answering — the loop still has an answer to hand back, so
      // it names why the research is thin. A provider error frame kills the
      // model turn instead, leaving nothing to label, which is why it aborts
      // the run rather than joining this enum. Both are now honest; they are
      // honest about different failures.
      final reported = <SearchTerminationReason>[];
      var turns = 0;
      final agent = SearchAgent(
        streamTurn: (_) => Stream<OllamaMessage>.value(
          turns++ == 0
              ? OllamaMessage(
                  '',
                  role: OllamaMessageRole.assistant,
                  toolCalls: [
                    OllamaToolCall(
                      name: 'web_search',
                      arguments: const {'query': 'nvidia 2024 revenue'},
                    ),
                  ],
                  done: true,
                )
              : OllamaMessage('Partial answer.',
                  role: OllamaMessageRole.assistant, done: true),
        ),
        search: (_) async => throw WebSearchUnavailableException('throttled'),
      );

      final outcome = await agent.run(
        history: [
          OllamaMessage('Compare the 2024 revenue of Nvidia and AMD.',
              role: OllamaMessageRole.user),
        ],
        listener: SearchAgentListener(onResearchDone: reported.add),
      );

      expect(outcome.reason, SearchTerminationReason.searchUnavailable,
          reason: 'a failure the loop can see is named honestly, and the run '
              'still returns the answer it managed to write');
    });
  });
}
