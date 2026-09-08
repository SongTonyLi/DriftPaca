/// Offline probe: an OpenRouter **HTTP 200 error frame** (`data: {"error":
/// {...}}`, which is how OpenRouter reports a provider/rate-limit failure
/// that happens *after* streaming has begun) is swallowed by the transport
/// and turned into an empty assistant turn — and that empty turn makes
/// SearchAgent end the run as [SearchTerminationReason.converged] with a
/// blank answer and zero searches.
///
/// The defect spans two files and neither half is enough on its own:
///
///   * `OpenRouterCodec.decodeSseJson` accepts any well-formed JSON `data:`
///     payload, and `parseCompletion` never looks at a top-level `error`
///     key — a frame with no `choices` falls through to
///     `const <String, dynamic>{}` and yields
///     `OllamaMessage('', done: false, toolCalls: null)`.
///     `OllamaService._openRouterChatStream`'s status-code guards cannot
///     help: the HTTP status is 200.
///
///   * `SearchAgent.run` then sees a turn with no content and no tool
///     calls. The forced-answer branch needs non-empty `toolCalls`; the
///     coverage gate needs non-empty `content`; so both are skipped and
///     `_terminationReason(canSearch: true, ...)` returns `converged`.
///
/// Net effect: a failed research run is indistinguishable — in every field
/// the UI and the persistence layer read — from a model that legitimately
/// had nothing to say. No `OllamaException` is raised, so
/// `ChatProvider._initializeChatStream`'s `on OllamaException` handler
/// never records an error, and the blank-bubble cleanup at
/// chat_provider.dart:1285 is gated on `outcome.cancelled`, which is false
/// here.
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

/// A run whose only model turn is [chunks], with search stubbed out so any
/// call to it would be visible as a non-zero `searchCount`.
Future<({SearchAgentOutcome outcome, List<SearchTerminationReason> reported})>
    _runLoopOn(List<OllamaMessage> chunks) async {
  final reported = <SearchTerminationReason>[];
  final agent = SearchAgent(
    streamTurn: (_) => Stream<OllamaMessage>.fromIterable(chunks),
    search: (_) async => <WebSearchResult>[],
  );
  final outcome = await agent.run(
    history: [
      OllamaMessage(
        'Compare the 2024 revenue of Nvidia and AMD, with sources.',
        role: OllamaMessageRole.user,
      ),
    ],
    listener: SearchAgentListener(onResearchDone: reported.add),
  );
  return (outcome: outcome, reported: reported);
}

void main() {
  group('OpenRouter 200-status error frame', () {
    test('the codec decodes it and parseCompletion invents an empty turn', () {
      const line = 'data: {"error":{"code":429,"message":"rate limited"}}';

      final decoded = OpenRouterCodec.decodeSseJson(line);
      expect(decoded, isNotNull,
          reason: 'decodeSseJson accepts the frame purely because it is '
              'well-formed JSON — it never asks whether the payload is a '
              'completion or an error report');
      expect(decoded!['error'], isNotNull,
          reason: 'the frame carries an error and no choices at all');

      final message = OpenRouterCodec.parseCompletion(decoded);
      expect(message.content, isEmpty,
          reason: 'parseCompletion falls back to const <String, dynamic>{} '
              'for the missing choices and returns (content ?? "") — the '
              'failure becomes an empty assistant message');
      expect(message.toolCalls, isNull);
      expect(message.done, isFalse,
          reason: 'no finish_reason, so the turn is not even marked done');
      expect(message.content, isNot(contains('rate limited')),
          reason: 'the provider error text is dropped on the floor; nothing '
              'downstream can recover what went wrong');
    });

    test('chatStream yields one empty message and throws nothing', () async {
      final service = _serviceReturning(_errorFrameBody);

      final messages = await service
          .chatStream(
            [OllamaMessage('Hi', role: OllamaMessageRole.user)],
            chat: OllamaChat(model: 'openai/gpt-4o-mini'),
          )
          .toList();

      expect(messages, hasLength(1),
          reason: 'the error frame is yielded as a normal assistant chunk');
      expect(messages.single.content, isEmpty);
      expect(messages.single.toolCalls, isNull);
      expect(messages.single.done, isFalse);
      expect(messages.map((m) => m.content).join(), isNot(contains('429')),
          reason: 'a caller draining chatStream has no signal of any kind '
              'that the upstream call failed');
    });

    test('a real HTTP 429 does throw — proving the 200 path is the hole',
        () async {
      final service = _serviceReturning(
        jsonEncode({
          'error': {'code': 429, 'message': 'rate limited'}
        }),
        status: 429,
      );

      await expectLater(
        service
            .chatStream(
              [OllamaMessage('Hi', role: OllamaMessageRole.user)],
              chat: OllamaChat(model: 'openai/gpt-4o-mini'),
            )
            .toList(),
        throwsA(isA<OllamaException>()),
        reason: 'the identical error body IS surfaced when it arrives with a '
            'non-200 status — the only thing that decides whether the user '
            'learns their run failed is which side of the stream start the '
            'provider failed on',
      );
    });

    test('the non-streaming path swallows it too', () async {
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

      final message = await service.generate(
        'Name this chat',
        chat: OllamaChat(model: 'openai/gpt-4o-mini'),
      );

      expect(message.content, isEmpty,
          reason: '_openRouterCompletionFromResponse hands a 200-status '
              'error body straight to parseCompletion, so titling and every '
              'other non-streamed call degrades silently the same way');
    });
  });

  group('what the research loop does with that empty turn', () {
    test('the run reports converged, blank, with zero searches', () async {
      // Not a hand-written OllamaMessage: these are the exact chunks the
      // transport produced from the error frame above, so the loop is being
      // fed the real thing.
      final service = _serviceReturning(_errorFrameBody);
      final chunks = await service
          .chatStream(
            [OllamaMessage('Hi', role: OllamaMessageRole.user)],
            chat: OllamaChat(model: 'openai/gpt-4o-mini'),
          )
          .toList();

      final result = await _runLoopOn(chunks);

      expect(result.outcome.reason, SearchTerminationReason.converged,
          reason: 'a run in which the provider errored out before a single '
              'search is reported as the model having converged on an '
              'answer; searchUnavailable exists for exactly this class of '
              'outcome and is never reached');
      expect(result.outcome.content, isEmpty,
          reason: 'the "converged" answer is a blank bubble');
      expect(result.outcome.searchCount, 0,
          reason: 'no research happened at all — the loop never even '
              'reached _executeToolCalls');
      expect(result.outcome.cancelled, isFalse,
          reason: 'so ChatProvider chat_provider.dart:1285 blank-bubble '
              'cleanup (guarded on outcome.cancelled) does not remove the '
              'empty message; it is kept and persisted');
      expect(result.reported, [SearchTerminationReason.converged],
          reason: 'the one termination signal the UI receives says the run '
              'finished normally');
    });

    test('it is byte-identical to a model that legitimately said nothing',
        () async {
      final service = _serviceReturning(_errorFrameBody);
      final errorChunks = await service
          .chatStream(
            [OllamaMessage('Hi', role: OllamaMessageRole.user)],
            chat: OllamaChat(model: 'openai/gpt-4o-mini'),
          )
          .toList();

      final failed = await _runLoopOn(errorChunks);
      final quiet = await _runLoopOn([
        OllamaMessage('', role: OllamaMessageRole.assistant, done: true),
      ]);

      expect(
        [
          failed.outcome.reason,
          failed.outcome.content,
          failed.outcome.searchCount,
          failed.outcome.cancelled,
          failed.outcome.thinking,
        ],
        [
          quiet.outcome.reason,
          quiet.outcome.content,
          quiet.outcome.searchCount,
          quiet.outcome.cancelled,
          quiet.outcome.thinking,
        ],
        reason: 'every field a caller could branch on is identical, so no '
            'code above SearchAgent can tell an upstream provider failure '
            'from an ordinary empty reply — there is nothing to retry on '
            'and nothing to show the user',
      );
    });

    test('a searchUnavailable run, by contrast, is correctly labelled',
        () async {
      // The loop DOES have a truthful reason for "research could not
      // happen". It is only reachable when the failure surfaces as an
      // exception the loop can see — which the 200 error frame never does.
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
          reason: 'when a failure is visible to the loop it is named '
              'honestly — which is the standard the 200 error frame misses');
    });
  });
}
