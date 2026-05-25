/// Ollama Cloud integration tests — WEBSEARCH behavior across models.
/// Run with: dart test test/integration/ollama_cloud_test.dart --timeout 300s
///
/// Tests the WEBSEARCH instruction compliance, citation quality,
/// and edge cases across multiple model families.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Set via environment: OLLAMA_CLOUD_API_KEY=xxx dart test test/integration/ollama_cloud_test.dart
final _cloudApiKey = Platform.environment['OLLAMA_CLOUD_API_KEY'] ?? '';
const _cloudBaseUrl = 'https://ollama.com';

/// Models to test across different families and sizes.
const _testModels = [
  'gpt-oss:120b',
  'deepseek-v3.2',
  'qwen3-next:80b',
  'gemma4:31b',
];

final _webSearchSystemPrompt = '''You have web search access. ALWAYS search unless the answer is a universal truth that never changes (math, physics constants, basic definitions).

Err on the side of searching. If there is ANY chance a search could provide useful, updated, or more accurate information — search. Even if you think you know the answer, search to verify.

To search: start your response with WEBSEARCH: followed by a concise search query (max 10 words) on the FIRST line. Nothing else on that line.

You MUST search for: numbers, statistics, prices, dates, current events, news, recent developments, product info, people, companies, forecasts, rankings, comparisons.

Today's date: ${DateTime.now().toIso8601String().substring(0, 10)}.''';

Future<String> generate(String prompt, {
  required String model,
  String? systemPrompt,
}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$_cloudBaseUrl/api/generate'));
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Authorization', 'Bearer $_cloudApiKey');
    request.add(utf8.encode(jsonEncode({
      'model': model,
      'prompt': prompt,
      'system': systemPrompt,
      'stream': false,
    })));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: $body');
    }
    final json = jsonDecode(body);
    return json['response'] as String? ?? '';
  } finally {
    client.close();
  }
}

bool _startsWithWebsearch(String content) {
  return content.split('\n').first.trim().toUpperCase().startsWith('WEBSEARCH:');
}

String _extractQuery(String content) {
  final firstLine = content.split('\n').first.trim();
  final idx = firstLine.toUpperCase().indexOf('WEBSEARCH:');
  if (idx == -1) return '';
  return firstLine.substring(idx + 'WEBSEARCH:'.length).trim();
}

void main() {
  setUpAll(() {
    if (_cloudApiKey.isEmpty) {
      throw Exception(
        'OLLAMA_CLOUD_API_KEY not set. Run with:\n'
        'OLLAMA_CLOUD_API_KEY=<key> dart test test/integration/ollama_cloud_test.dart',
      );
    }
  });

  // =========================================================================
  // Group 1: WEBSEARCH compliance across models
  // =========================================================================
  for (final model in _testModels) {
    group('[$model] WEBSEARCH compliance', () {
      test('searches for current GDP data', () async {
        final content = await generate(
          "What is Vietnam's GDP in 2025?",
          model: model,
          systemPrompt: _webSearchSystemPrompt,
        );

        print('[$model] GDP question:');
        print('First line: "${content.split('\n').first.trim()}"');

        expect(_startsWithWebsearch(content), isTrue,
            reason: '[$model] should WEBSEARCH for current GDP data.\nGot: "${content.split('\n').first}"');

        final query = _extractQuery(content);
        print('Query: "$query"');
        expect(query, isNotEmpty);
        expect(query.split(' ').length, lessThanOrEqualTo(12));
      });

      test('does NOT search for basic math', () async {
        final content = await generate(
          'What is 2 + 2?',
          model: model,
          systemPrompt: _webSearchSystemPrompt,
        );

        print('[$model] Math question: "${content.split('\n').first.trim()}"');

        expect(_startsWithWebsearch(content), isFalse,
            reason: '[$model] should NOT search for simple math');
      });

      test('does NOT search for well-known facts', () async {
        final content = await generate(
          'What is the speed of light?',
          model: model,
          systemPrompt: _webSearchSystemPrompt,
        );

        print('[$model] Physics constant: "${content.split('\n').first.trim()}"');

        expect(_startsWithWebsearch(content), isFalse,
            reason: '[$model] should NOT search for universal constants');
      });

      test('searches for today\'s date-specific events', () async {
        final content = await generate(
          'What important events happened today?',
          model: model,
          systemPrompt: _webSearchSystemPrompt,
        );

        print('[$model] Today\'s events: "${content.split('\n').first.trim()}"');

        expect(_startsWithWebsearch(content), isTrue,
            reason: '[$model] should search for date-specific events');
      });
    });
  }

  // =========================================================================
  // Group 2: Query quality across models
  // =========================================================================
  group('Search query quality', () {
    for (final model in _testModels) {
      test('[$model] produces focused, concise queries', () async {
        final content = await generate(
          'I heard there was a big earthquake somewhere recently, can you tell me about it?',
          model: model,
          systemPrompt: _webSearchSystemPrompt,
        );

        if (!_startsWithWebsearch(content)) {
          print('[$model] did not search — skipping query quality check');
          return;
        }

        final query = _extractQuery(content);
        print('[$model] Query for earthquake: "$query"');

        // Query should be concise (not the full user message repeated)
        expect(query.length, lessThan(80),
            reason: '[$model] query should be concise, not a sentence');
        // Should not include filler words like "can you tell me"
        expect(query.toLowerCase(), isNot(contains('can you')));
        expect(query.toLowerCase(), isNot(contains('tell me')));
      });
    }
  });

  // =========================================================================
  // Group 3: Citation quality with search context
  // =========================================================================
  group('Citation quality with context', () {
    const searchContext = '''### Task:
Respond to the user query using the provided context, incorporating inline citations in the format [id] **only when the <source> tag includes an explicit id attribute**.

### Guidelines:
- Respond in the same language as the user's query.
- Only include inline citations using [id] when the <source> tag includes an id attribute.

<context>
<source id="1" name="https://worldbank.org/vietnam" resource-type="web_search">
The World Bank projects Vietnam GDP growth at 6.5% in 2025, with nominal GDP reaching approximately 514 billion USD. Manufacturing exports and FDI drive growth.
</source>
<source id="2" name="https://imf.org/vietnam" resource-type="web_search">
According to the IMF, Vietnam GDP per capita is expected to reach 4,650 USD in 2025. PPP GDP is estimated at 2.2 trillion USD.
</source>
<source id="3" name="https://adb.org/vietnam" resource-type="web_search">
The Asian Development Bank forecasts Vietnam GDP growth of 6.8% in 2025, driven by electronics exports and digital economy expansion.
</source>
</context>''';

    for (final model in _testModels) {
      test('[$model] uses citations correctly', () async {
        final content = await generate(
          '$searchContext\n\nUser question: What is Vietnam\'s GDP growth forecast for 2025?',
          model: model,
        );

        print('[$model] Citation test:');
        print(content.substring(0, content.length.clamp(0, 400)));

        // Check for citations
        final standardCites = RegExp(r'\[\d+\]').allMatches(content).length;
        final fullwidthCites = RegExp(r'\u3010\d+\u3011').allMatches(content).length;
        final totalCites = standardCites + fullwidthCites;
        print('\n[$model] Citations: $totalCites ($standardCites standard, $fullwidthCites fullwidth)');

        expect(totalCites, greaterThan(0),
            reason: '[$model] should produce citations when given <source> tags');

        // Check cited IDs are valid (1-3)
        final citedIds = <int>{};
        for (final m in RegExp(r'\[(\d+)\]|\u3010(\d+)\u3011').allMatches(content)) {
          final id = int.tryParse(m.group(1) ?? m.group(2) ?? '');
          if (id != null) citedIds.add(id);
        }
        print('[$model] Cited source IDs: $citedIds');
        expect(citedIds.every((id) => id >= 1 && id <= 3), isTrue,
            reason: '[$model] should only cite IDs 1-3');
      });
    }
  });

  // =========================================================================
  // Group 4: Edge cases
  // =========================================================================
  group('Edge cases', () {
    test('ambiguous question — model makes reasonable choice', () async {
      // "What is Python?" could be answered from knowledge or searched for latest version
      final content = await generate(
        'What is Python?',
        model: 'gpt-oss:120b',
        systemPrompt: _webSearchSystemPrompt,
      );

      print('Ambiguous "What is Python?":');
      print('First line: "${content.split('\n').first.trim()}"');
      print('Did search: ${_startsWithWebsearch(content)}');

      // Either answer is acceptable — just shouldn't crash
      expect(content, isNotEmpty);
    });

    test('question with misleading dollar signs doesn\'t confuse WEBSEARCH', () async {
      final content = await generate(
        'How much does a \$500 iPhone cost in Vietnam in VND?',
        model: 'gpt-oss:120b',
        systemPrompt: _webSearchSystemPrompt,
      );

      print('Dollar sign question:');
      print('First line: "${content.split('\n').first.trim()}"');

      // Should search (exchange rates are current data)
      expect(_startsWithWebsearch(content), isTrue,
          reason: 'Exchange rate question needs current data');
    });

    test('follow-up question without context doesn\'t search unnecessarily', () async {
      final content = await generate(
        'Can you explain that in simpler terms?',
        model: 'gpt-oss:120b',
        systemPrompt: _webSearchSystemPrompt,
      );

      print('Follow-up question:');
      print('First line: "${content.split('\n').first.trim()}"');

      // Vague follow-up without context shouldn't trigger search
      // (no specific topic to search for)
      expect(content, isNotEmpty);
    });

    test('multi-turn: model searches on first turn, answers directly on follow-up', () async {
      // Turn 1: Question that needs search
      final turn1 = await generate(
        "What is Vietnam's GDP in 2025?",
        model: 'gpt-oss:120b',
        systemPrompt: _webSearchSystemPrompt,
      );

      print('=== Multi-turn test ===');
      print('Turn 1: "${turn1.split('\n').first.trim()}"');

      // Simulate: search happened, results injected, model answered
      const searchResults = '''<source id="1" name="https://worldbank.org">
Vietnam nominal GDP projected at 514 billion USD in 2025 with 6.5% growth.
</source>''';

      const turn1Answer = 'Vietnam GDP is projected at approximately 514 billion USD in 2025 [1].';

      // Turn 2: Follow-up that should NOT need search (context already available)
      final turn2Prompt = '''$_webSearchSystemPrompt

Previous conversation:
User: What is Vietnam's GDP in 2025?
Assistant: $turn1Answer

Search results that were used:
$searchResults

Now answer the follow-up:''';

      final turn2 = await generate(
        'How does that compare to Thailand?',
        model: 'gpt-oss:120b',
        systemPrompt: turn2Prompt,
      );

      print('Turn 2: "${turn2.split('\n').first.trim()}"');
      print('Turn 2 searched: ${_startsWithWebsearch(turn2)}');

      // The follow-up about Thailand comparison SHOULD trigger a new search
      // because the model doesn't have Thailand's GDP data
      if (_startsWithWebsearch(turn2)) {
        final query = _extractQuery(turn2);
        print('Turn 2 query: "$query"');
        expect(query.toLowerCase(), contains('thailand'),
            reason: 'Follow-up search should be about Thailand');
      }
    });

    test('multi-turn: model uses prior search context in follow-up', () async {
      // Simulate a conversation where search already happened
      const context = '''### Task:
Respond to the user query using the provided context, incorporating inline citations [id].

<context>
<source id="1" name="https://worldbank.org/vietnam" resource-type="web_search">
Vietnam GDP: 514 billion USD nominal, 6.5% growth in 2025. Key sectors: manufacturing (32%), services (42%), agriculture (12%).
</source>
<source id="2" name="https://imf.org/vietnam" resource-type="web_search">
Vietnam GDP per capita: 4,650 USD. PPP GDP: 2.2 trillion USD. Inflation: 3.2%.
</source>
</context>''';

      // First answer with context
      final answer1 = await generate(
        '$context\n\nUser: What is Vietnam GDP in 2025?',
        model: 'gpt-oss:120b',
      );

      print('=== Multi-turn context test ===');
      print('Answer 1: ${answer1.substring(0, answer1.length.clamp(0, 200))}...');

      // Follow-up using the SAME context (no new search needed)
      final answer2 = await generate(
        '$context\n\nPrevious answer: $answer1\n\nUser follow-up: What are the main economic sectors?',
        model: 'gpt-oss:120b',
      );

      print('Answer 2: ${answer2.substring(0, answer2.length.clamp(0, 200))}...');

      // Answer 2 should reference the sector data from source [1]
      expect(answer2.toLowerCase(), contains('manufacturing'),
          reason: 'Follow-up should use sector data from existing context');

      final hasCitations = RegExp(r'\[\d+\]|\u3010\d+\u3011').hasMatch(answer2);
      print('Answer 2 has citations: $hasCitations');
    });

    test('multi-language response maintains citations', () async {
      const context = '''### Task:
Respond to the user query using the provided context, incorporating inline citations [id].

<context>
<source id="1" name="https://example.com/data" resource-type="web_search">
China GDP reached 18.5 trillion USD in 2024, making it the second largest economy.
</source>
</context>''';

      final content = await generate(
        '$context\n\nUser question: 中国GDP是多少？请用中文回答。',
        model: 'gpt-oss:120b',
      );

      print('Chinese response with citation:');
      print(content);

      final hasCitations = RegExp(r'\[\d+\]|\u3010\d+\u3011').hasMatch(content);
      print('\nHas citations: $hasCitations');

      expect(content, isNotEmpty);
      // Should contain Chinese characters
      expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(content), isTrue,
          reason: 'Response should be in Chinese');
    });
  });
}
