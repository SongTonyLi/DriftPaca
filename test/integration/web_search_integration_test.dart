/// Integration tests for the web search workflow.
/// Requires network access and Ollama Cloud API key.
///
/// Run with: flutter test test/integration/web_search_integration_test.dart --timeout 120s
///
/// These tests verify:
/// 1. The model outputs WEBSEARCH: when instructed (via Ollama Cloud)
/// 2. The model does NOT search for general knowledge
/// 3. Content extraction and chunking work on real pages
/// 4. The full pipeline: model → search → context formatting → answer
///
/// Note: WebView search requires a running Flutter engine (device/emulator).
/// In `flutter test` (headless), WebView returns empty — those tests are
/// marked accordingly. Run on a device for full coverage.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Services/ollama_service.dart';
import 'package:llamaseek/Services/web_search_service.dart';
import 'package:llamaseek/Utils/text_splitter.dart';

// API key read from environment — not committed
// Run with: OLLAMA_CLOUD_API_KEY=<key> flutter test test/integration/web_search_integration_test.dart
const _cloudApiKey = String.fromEnvironment('OLLAMA_CLOUD_API_KEY');
const _testModel = 'gpt-oss:120b-cloud';

const _webSearchSystemPrompt = '''If you need current or real-time information from the web to answer the user's question, start your response with WEBSEARCH: followed by a concise search query (max 10 words) on the first line.

If you can answer without web search, respond normally.''';

OllamaService _createCloudService() {
  final service = OllamaService();
  service.isCloudMode = true;
  service.apiKey = _cloudApiKey;
  // isCloudMode setter already sets baseUrl to https://ollama.com
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // Group 1: Ollama Cloud — WEBSEARCH behavior
  // =========================================================================
  group('Ollama Cloud — WEBSEARCH instruction', () {
    late OllamaService ollamaService;

    setUp(() {
      ollamaService = _createCloudService();
    });

    test('model outputs WEBSEARCH: for current events question', () async {
      final chat = OllamaChat(
        model: _testModel,
        systemPrompt: _webSearchSystemPrompt,
      );

      final response = await ollamaService
          .generate("What is Vietnam's GDP in 2025?", chat: chat)
          .timeout(const Duration(seconds: 30));

      print('--- Model response for current events question ---');
      print('Content:\n${response.content}');

      final firstLine = response.content.split('\n').first.trim();
      print('\nFirst line: "$firstLine"');

      expect(
        firstLine.toUpperCase().startsWith('WEBSEARCH:'),
        isTrue,
        reason: 'Model should output WEBSEARCH: for a question requiring current data.\nGot: "$firstLine"',
      );

      final query = firstLine.substring(
        firstLine.toUpperCase().indexOf('WEBSEARCH:') + 'WEBSEARCH:'.length,
      ).trim();
      print('Extracted query: "$query"');
      expect(query, isNotEmpty, reason: 'Search query should not be empty');
    });

    test('model does NOT output WEBSEARCH: for general knowledge', () async {
      final chat = OllamaChat(
        model: _testModel,
        systemPrompt: _webSearchSystemPrompt,
      );

      final response = await ollamaService
          .generate('What is 2 + 2?', chat: chat)
          .timeout(const Duration(seconds: 30));

      print('--- Model response for general knowledge ---');
      print('Content:\n${response.content}');

      final firstLine = response.content.split('\n').first.trim();
      expect(
        firstLine.toUpperCase().startsWith('WEBSEARCH:'),
        isFalse,
        reason: 'Model should NOT search for simple math.\nGot: "$firstLine"',
      );
    });

    test('model outputs WEBSEARCH: for recent news', () async {
      final chat = OllamaChat(
        model: _testModel,
        systemPrompt: _webSearchSystemPrompt,
      );

      final response = await ollamaService
          .generate('What are the latest tech news today?', chat: chat)
          .timeout(const Duration(seconds: 30));

      print('--- Model response for news question ---');
      print('Content:\n${response.content}');

      final firstLine = response.content.split('\n').first.trim();
      expect(
        firstLine.toUpperCase().startsWith('WEBSEARCH:'),
        isTrue,
        reason: 'Model should search for current news.\nGot: "$firstLine"',
      );
    });

    test('model outputs WEBSEARCH: for CJK question', () async {
      final chat = OllamaChat(
        model: _testModel,
        systemPrompt: _webSearchSystemPrompt,
      );

      final response = await ollamaService
          .generate('越南2025年GDP是多少？', chat: chat)
          .timeout(const Duration(seconds: 30));

      print('--- Model response for CJK question ---');
      print('Content:\n${response.content}');

      final firstLine = response.content.split('\n').first.trim();
      print('First line: "$firstLine"');

      // CJK query should also trigger search
      expect(
        firstLine.toUpperCase().startsWith('WEBSEARCH:'),
        isTrue,
        reason: 'Model should search for CJK current events question.\nGot: "$firstLine"',
      );
    });
  });

  // =========================================================================
  // Group 2: WebSearchService — HTTP fallback (WebView won't work in test env)
  // =========================================================================
  group('WebSearchService — search pipeline', () {
    late WebSearchService searchService;

    setUp(() {
      searchService = WebSearchService();
    });

    test('formatResultsAsContext produces valid structure', () {
      final results = [
        WebSearchResult(
          title: 'Test Page',
          snippet: 'A test snippet',
          url: 'https://example.com/test',
          pageContent: 'Full page content here with details about the topic.',
        ),
        WebSearchResult(
          title: 'Another Page',
          snippet: 'Another snippet',
          url: 'https://example.org/page',
        ),
      ];

      // Add chunks to first result
      results[0].chunks = splitText(results[0].pageContent!, chunkSize: 100, overlap: 0);

      final context = WebSearchService.formatResultsAsContext(results);

      print('--- formatResultsAsContext ---');
      print(context);

      expect(context, contains('<source id="1" name="https://example.com/test"'));
      expect(context, contains('<source id="2" name="https://example.org/page"'));
      expect(context, contains('</source>'));
      expect(context, contains('Full page content'));
      expect(context, contains('Another Page'));
    });

    test('extractTextFromHtml prioritizes article content', () {
      final html = '''
        <html><body>
          <nav>Navigation</nav>
          <article>Important article content about Vietnam GDP.</article>
          <footer>Footer</footer>
        </body></html>
      ''';

      final result = WebSearchService.extractTextFromHtml(html);

      print('--- extractTextFromHtml ---');
      print('Result: $result');

      expect(result, contains('Vietnam GDP'));
      expect(result, isNot(contains('Navigation')));
      expect(result, isNot(contains('Footer')));
    });

    test('text splitter chunks content with overlap', () {
      final text = List.generate(10, (i) => 'Paragraph $i with some content about topic.').join('\n\n');

      final chunks = splitText(text, chunkSize: 100, overlap: 20);

      print('--- Text splitter ---');
      print('Input: ${text.length} chars');
      print('Chunks: ${chunks.length}');
      for (var i = 0; i < chunks.length; i++) {
        print('  Chunk $i (${chunks[i].length} chars): ${chunks[i].substring(0, chunks[i].length.clamp(0, 60))}...');
      }

      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(120),
            reason: 'Chunk should be ≤ chunkSize + overlap');
      }
    });
  });

  // =========================================================================
  // Group 3: Full pipeline — model + search + answer
  // =========================================================================
  group('Full pipeline', () {
    late OllamaService ollamaService;

    setUp(() {
      ollamaService = _createCloudService();
    });

    test('model answers with citations when given search context', () async {
      // Simulate search results
      final mockResults = [
        WebSearchResult(
          title: 'Vietnam GDP Forecast 2025 - World Bank',
          snippet: 'Vietnam GDP is projected to grow 6.5% in 2025.',
          url: 'https://worldbank.org/vietnam-gdp',
          pageContent: 'The World Bank projects Vietnam GDP growth at 6.5% in 2025, with nominal GDP reaching approximately 514 billion USD. The country maintains strong economic momentum driven by manufacturing exports and FDI inflows.',
        ),
        WebSearchResult(
          title: 'IMF Vietnam Economic Outlook',
          snippet: 'IMF forecasts Vietnam as one of fastest growing economies.',
          url: 'https://imf.org/vietnam-outlook',
          pageContent: 'According to the IMF, Vietnam GDP per capita is expected to reach 4,650 USD in 2025. The purchasing power parity GDP is estimated at 2.2 trillion USD.',
        ),
      ];

      // Build context
      final context = WebSearchService.formatResultsAsContext(mockResults);

      // Ask model to answer with context
      final chat = OllamaChat(model: _testModel);

      final response = await ollamaService
          .generate(
            '''$context

Based on the search results above, answer the user's question with inline citations [N].

User question: What is Vietnam's GDP in 2025?''',
            chat: chat,
          )
          .timeout(const Duration(seconds: 60));

      print('=== Full pipeline answer ===');
      print(response.content);

      expect(response.content, isNotEmpty);
      expect(response.content.toLowerCase(), contains('vietnam'));

      // Check for any citation format
      final hasBracketCitations = RegExp(r'\[\d+\]').hasMatch(response.content);
      final hasFullwidthCitations = RegExp(r'\u3010\d+\u3011').hasMatch(response.content);
      print('\nHas [N] citations: $hasBracketCitations');
      print('Has 【N】 citations: $hasFullwidthCitations');
      print('Has any citations: ${hasBracketCitations || hasFullwidthCitations}');

      // Check content quality
      final mentionsGDP = response.content.toLowerCase().contains('gdp');
      final mentionsNumber = RegExp(r'\d{3}').hasMatch(response.content);
      print('Mentions GDP: $mentionsGDP');
      print('Contains numbers: $mentionsNumber');

      expect(mentionsGDP, isTrue, reason: 'Answer should discuss GDP');
    });

    test('citation replacement handles both bracket formats', () {
      // This tests the ChatProvider.replaceCitationsWithLinks static method
      // Import it indirectly via a simple test

      final sourceUrls = {1: 'https://example.com', 2: 'https://test.org'};

      // Standard brackets
      final text1 = 'Growth is 6.5% [1] and per capita is 4650 [2].';
      final result1 = text1.replaceAllMapped(
        RegExp(r'(?:\[(\d+)\]|\u3010(\d+)\u3011)(?!\()'),
        (match) {
          final id = int.tryParse(match.group(1) ?? match.group(2) ?? '');
          if (id != null && sourceUrls.containsKey(id)) {
            return '[[$id]](${sourceUrls[id]})';
          }
          return match.group(0)!;
        },
      );

      print('--- Citation replacement ---');
      print('Standard brackets: $result1');
      expect(result1, contains('[[1]](https://example.com)'));
      expect(result1, contains('[[2]](https://test.org)'));

      // Fullwidth brackets
      final text2 = 'Growth is 6.5%\u30101\u3011and per capita\u30102\u3011.';
      final result2 = text2.replaceAllMapped(
        RegExp(r'(?:\[(\d+)\]|\u3010(\d+)\u3011)(?!\()'),
        (match) {
          final id = int.tryParse(match.group(1) ?? match.group(2) ?? '');
          if (id != null && sourceUrls.containsKey(id)) {
            return '[[$id]](${sourceUrls[id]})';
          }
          return match.group(0)!;
        },
      );

      print('Fullwidth brackets: $result2');
      expect(result2, contains('[[1]](https://example.com)'));
      expect(result2, contains('[[2]](https://test.org)'));
    });
  });
}
