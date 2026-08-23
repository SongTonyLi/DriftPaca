/// Live calibration check for the completeness gate's prompt — see
/// SearchAgent.assessCoverage and chat_provider's _coverageGateInstruction.
///
/// The gate's judgment is the tunable, regression-prone part of the
/// feature: too strict and it manufactures the over-searching `8e0b64b`
/// fixed, too lenient and it does nothing. Both directions are pinned here
/// against real drafted answers.
///
/// Issues no web searches — only model calls — so it is cheap and cannot
/// trip a search rate limit. It does hit the real API, so it is excluded
/// from the normal gate. Run it explicitly:
///
///   `OLLAMA_CLOUD_API_KEY=<key> flutter test test/integration/coverage_gate_live_test.dart`
///
/// The key is read from the environment and must never be committed.
@Timeout(Duration(minutes: 6))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Services/ollama_service.dart';
import 'package:llamaseek/Utils/coverage_gaps.dart';

final _apiKey = Platform.environment['OLLAMA_CLOUD_API_KEY'] ?? '';

/// Skipped rather than failed when unconfigured, so a plain `flutter test`
/// run stays a clean signal. Naming the variable means this can never be
/// mistaken for a pass.
const _skipReason = 'OLLAMA_CLOUD_API_KEY not set — run this file explicitly '
    'with the key to exercise the live gate';

const _gatePrompt = '''
You check whether a draft answer addresses everything the question asked.

List ONLY parts of the question the draft leaves genuinely unanswered — including any part the draft itself admits it could not establish. One per line, phrased as the missing thing, with no other commentary.

If the draft addresses every part, reply with exactly: NONE

Reply NONE unless a part is clearly missing. Do not list a part merely because it could be more detailed, better sourced, updated, or expanded. A draft that answers the question briefly is complete. A draft that explicitly says it could not determine something is NOT complete.''';

const _question =
    'Which team won the 2026 NBA Finals, who was named Finals MVP, '
    'and which college did that player attend?';

/// VERBATIM from the device, the run that motivated this whole feature.
/// One search, two hops resolved, third abandoned with budget remaining.
const _incompleteDraft = '''
The **New York Knicks** won the 2026 NBA Finals, defeating the San Antonio Spurs 4–1 [1][5][7]. **Jalen Brunson** was named NBA Finals MVP [1][2][8].

Regarding his college: the provided sources do not explicitly name Brunson's college, but they list his NCAA championship years as 2016 and 2018 [3]. Those championships are associated with Villanova, though the source text only explicitly mentions "two titles at Villanova" in reference to Donte DiVincenzo, not Brunson [3].''';

/// The same answer with the third hop actually resolved. Guards the other
/// direction: a gate that flags this is manufacturing work.
const _completeDraft = '''
The **New York Knicks** won the 2026 NBA Finals, defeating the San Antonio Spurs 4–1 [1][5][7]. **Jalen Brunson** was named NBA Finals MVP [1][2][8]. Brunson attended **Villanova University** [9].''';

/// A terse but complete answer to a simple question — the shape most at
/// risk of a gate inventing "gaps" that are really just elaborations.
const _terseQuestion = 'What is the current population of Vietnam?';
const _terseDraft = 'Vietnam\'s population is about 101 million [1].';

Future<List<String>> _judge(String question, String draft) async {
  final ollama = OllamaService()
    ..isCloudMode = true
    ..apiKey = _apiKey;
  final buffer = StringBuffer();
  await for (final chunk in ollama.chatStream(
    [
      OllamaMessage('Question:\n$question\n\nDraft answer:\n$draft',
          role: OllamaMessageRole.user)
    ],
    chat: OllamaChat(model: 'gpt-oss:120b', systemPrompt: _gatePrompt),
  )) {
    buffer.write(chunk.content);
  }
  // ignore: avoid_print
  print('  raw gate reply: ${buffer.toString().trim().replaceAll('\n', ' | ')}');
  return parseCoverageGaps(buffer.toString());
}

void main() {
  group('live gate judgment', () {
    test('flags the real device answer that abandoned hop 3', () async {
      // ignore: avoid_print
      print('\n--- INCOMPLETE (verbatim from device) ---');
      final gaps = await _judge(_question, _incompleteDraft);
      // ignore: avoid_print
      print('  parsed gaps: $gaps');
      expect(gaps, isNotEmpty,
          reason: 'the draft says outright it could not establish the college');
      expect(gaps.join(' ').toLowerCase(), contains('college'));
    }, skip: _apiKey.isEmpty ? _skipReason : null);

    test('passes the same answer once hop 3 is resolved', () async {
      // ignore: avoid_print
      print('\n--- COMPLETE ---');
      final gaps = await _judge(_question, _completeDraft);
      // ignore: avoid_print
      print('  parsed gaps: $gaps');
      expect(gaps, isEmpty, reason: 'every hop is answered');
    }, skip: _apiKey.isEmpty ? _skipReason : null);

    test('passes a terse answer to a simple question', () async {
      // ignore: avoid_print
      print('\n--- TERSE (over-search regression) ---');
      final gaps = await _judge(_terseQuestion, _terseDraft);
      // ignore: avoid_print
      print('  parsed gaps: $gaps');
      expect(gaps, isEmpty,
          reason: 'brief is not incomplete — flagging this manufactures '
              'the over-searching 8e0b64b fixed');
    }, skip: _apiKey.isEmpty ? _skipReason : null);
  });
}
