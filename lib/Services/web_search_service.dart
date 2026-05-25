import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:llamaseek/Utils/text_splitter.dart';

class WebSearchResult {
  final String title;
  final String snippet;
  final String url;
  String? pageContent;
  List<String>? chunks;

  WebSearchResult({
    required this.title,
    required this.snippet,
    required this.url,
    this.pageContent,
    this.chunks,
  });
}

class WebSearchService {
  static const _baseUrl = 'https://html.duckduckgo.com/html/';
  static const _maxPageContentLength = 4000;
  static const _fetchTimeout = Duration(seconds: 8);
  static const _searchTimeout = Duration(seconds: 10);
  static const _retryBackoff = Duration(seconds: 2);
  static const _maxConcurrentFetches = 3;

  // ============================================================
  // Public API
  // ============================================================

  /// Full search pipeline with text chunking and relevance filtering:
  /// 1. Search DuckDuckGo (overfetch to allow filtering)
  /// 2. Fetch full page content (concurrency-limited)
  /// 3. Chunk content with recursive text splitter
  /// 4. Rank by relevance and return top results
  Future<List<WebSearchResult>> searchAndExtract(String query,
      {int maxResults = 8}) async {
    // Overfetch to build a pool for quality filtering
    final results = await searchAndFetch(query, maxResults: maxResults + 4);

    for (final result in results) {
      if (result.pageContent != null && result.pageContent!.isNotEmpty) {
        result.chunks = splitText(
          result.pageContent!,
          chunkSize: 1500,
          overlap: 200,
        );
      }
    }

    return _rankByRelevance(results, query, maxResults);
  }

  /// Search DuckDuckGo + fetch page content (concurrency-limited).
  Future<List<WebSearchResult>> searchAndFetch(String query,
      {int maxResults = 8}) async {
    final results = await search(query, maxResults: maxResults);
    if (results.isEmpty) return results;

    final semaphore = _Semaphore(_maxConcurrentFetches);
    await Future.wait(
      results.map((r) => semaphore.run(() => _fetchPageContent(r))),
      eagerError: false,
    );

    return results;
  }

  /// Searches DuckDuckGo via WebView (primary) with HTTP fallback.
  Future<List<WebSearchResult>> search(String query,
      {int maxResults = 5}) async {
    // Try WebView first (bypasses CAPTCHA)
    try {
      final results = await _searchViaWebView(query, maxResults: maxResults);
      if (results.isNotEmpty) return results;
    } catch (e) {
      // WebView failed, fall back to HTTP
    }

    // Fall back to HTTP (may be CAPTCHA-blocked)
    try {
      return await _searchOnce(query, maxResults: maxResults);
    } catch (e) {
      if (e is TimeoutException ||
          e is SocketException ||
          e is http.ClientException) {
        await Future.delayed(_retryBackoff);
        try {
          return await _searchOnce(query, maxResults: maxResults);
        } catch (_) {
          return [];
        }
      }
      return [];
    }
  }

  /// Formats search results as RAG context.
  /// Uses top chunks when available, falls back to snippet.
  static String formatResultsAsContext(List<WebSearchResult> results) {
    if (results.isEmpty) return '';

    final sourceContext = StringBuffer();
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      String content;
      if (r.chunks != null && r.chunks!.isNotEmpty) {
        content = r.chunks!.take(2).join('\n\n');
      } else if (r.pageContent != null && r.pageContent!.isNotEmpty) {
        content = r.pageContent!;
      } else {
        content = '${r.title}\n${r.snippet}';
      }
      sourceContext.writeln(
          '<source id="${i + 1}" name="${r.url}" resource-type="web_search">');
      sourceContext.writeln(content);
      sourceContext.writeln('</source>');
    }

    return '''### Task:
Respond to the user query using the provided context, incorporating inline citations in the format [id] **only when the <source> tag includes an explicit id attribute** (e.g., <source id="1">).

### Guidelines:
- If you don't know the answer, clearly state that.
- If uncertain, ask the user for clarification.
- Respond in the same language as the user's query.
- **Only include inline citations using [id] when the <source> tag includes an id attribute.**

<context>
${sourceContext.toString().trim()}
</context>
''';
  }

  // ============================================================
  // Relevance Ranking
  // ============================================================

  /// Scores and ranks results by query-term relevance, content quality,
  /// and content length. Filters out empty results.
  static List<WebSearchResult> _rankByRelevance(
    List<WebSearchResult> results, String query, int maxResults) {
    final queryTerms = query.toLowerCase().split(RegExp(r'\s+'))
        .where((t) => t.length > 2).toList();
    if (queryTerms.isEmpty) return results.take(maxResults).toList();

    final scores = <WebSearchResult, double>{};
    for (final r in results) {
      double score = 0;
      final text = '${r.title} ${r.pageContent ?? r.snippet}'.toLowerCase();

      // Has real page content (not just snippet)
      if (r.pageContent != null && r.pageContent!.isNotEmpty) score += 3;

      // Query term presence in title + content
      for (final term in queryTerms) {
        if (r.title.toLowerCase().contains(term)) score += 2;
        if (text.contains(term)) score += 1;
      }

      // Content richness bonus (longer = more useful, capped)
      final len = r.pageContent?.length ?? r.snippet.length;
      score += (len / 1000).clamp(0, 2).toDouble();

      scores[r] = score;
    }

    final ranked = results.toList()
      ..sort((a, b) => scores[b]!.compareTo(scores[a]!));

    return ranked
        .where((r) => r.pageContent != null || r.snippet.isNotEmpty)
        .take(maxResults)
        .toList();
  }

  // ============================================================
  // HTML Extraction
  // ============================================================

  /// Extracts readable text from HTML with semantic tag priority.
  /// Prioritizes <article> or <main> content, falls back to <body>.
  static String extractTextFromHtml(String html) {
    if (html.isEmpty) return '';

    // Remove script, style, and comments entirely
    var text = html
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

    // Try to extract semantic content: <article> first, then <main>
    String? semanticContent;
    for (final tag in ['article', 'main']) {
      final match = RegExp(
        '<$tag[^>]*>(.*?)</$tag>',
        dotAll: true,
      ).firstMatch(text);
      if (match != null) {
        semanticContent = match.group(1);
        break;
      }
    }

    // Use semantic content if found, otherwise strip boilerplate from full body
    if (semanticContent != null) {
      text = semanticContent;
    } else {
      text = text
          .replaceAll(RegExp(r'<nav[^>]*>.*?</nav>', dotAll: true), '')
          .replaceAll(RegExp(r'<footer[^>]*>.*?</footer>', dotAll: true), '')
          .replaceAll(RegExp(r'<header[^>]*>.*?</header>', dotAll: true), '')
          .replaceAll(RegExp(r'<aside[^>]*>.*?</aside>', dotAll: true), '');
    }

    // Strip all remaining HTML tags
    text = text.replaceAll(RegExp(r'<[^>]*>'), '');

    // Decode HTML entities
    text = _decodeHtmlEntities(text);

    // Collapse whitespace
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text;
  }

  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#x27;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#x2F;', '/')
        .replaceAll('&mdash;', '\u2014')
        .replaceAll('&ndash;', '\u2013');
  }

  // ============================================================
  // DDG Search Internals
  // ============================================================

  /// Searches DuckDuckGo using a headless WebView (bypasses CAPTCHA).
  Future<List<WebSearchResult>> _searchViaWebView(String query,
      {int maxResults = 5}) async {
    final completer = Completer<List<WebSearchResult>>();
    HeadlessInAppWebView? headless;

    final timer = Timer(const Duration(seconds: 12), () {
      if (!completer.isCompleted) {
        completer.complete([]);
      }
    });

    try {
      final encodedQuery = Uri.encodeComponent(query);
      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri('https://duckduckgo.com/?q=$encodedQuery&ia=web'),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          userAgent:
              'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
        ),
        onLoadStop: (controller, url) async {
          if (completer.isCompleted) return;

          // Poll for results instead of blind delay
          for (var attempt = 0; attempt < 10; attempt++) {
            await Future.delayed(const Duration(milliseconds: 300));
            if (completer.isCompleted) return;
            final count = await controller.evaluateJavascript(
              source: 'document.querySelectorAll("article[data-testid=\\"result\\"]").length || document.querySelectorAll(".result").length || 0',
            );
            final n = count is int ? count : int.tryParse(count?.toString() ?? '') ?? 0;
            if (n > 0) break;
          }
          if (completer.isCompleted) return;

          try {
            final jsResult = await controller.evaluateJavascript(source: '''
(function() {
  var results = [];
  var articles = document.querySelectorAll('article[data-testid="result"]');
  if (!articles.length) articles = document.querySelectorAll('.result');
  if (!articles.length) articles = document.querySelectorAll('[data-result]');
  for (var i = 0; i < articles.length && i < $maxResults; i++) {
    var el = articles[i];
    var link = el.querySelector('a[data-testid="result-title-a"]')
      || el.querySelector('a[href^="http"]');
    var snippet = el.querySelector('[data-result="snippet"]')
      || el.querySelector('.result__snippet')
      || el.querySelector('span');
    if (link && link.href && !link.href.includes('duckduckgo.com')) {
      results.push({
        title: (link.textContent || '').trim(),
        url: link.href,
        snippet: snippet ? (snippet.textContent || '').trim() : '',
      });
    }
  }
  return JSON.stringify(results);
})()
''');

            if (jsResult != null && jsResult is String && jsResult.isNotEmpty) {
              final parsed = jsonDecode(jsResult) as List;
              final searchResults = <WebSearchResult>[];
              final seenUrls = <String>{};
              for (final item in parsed) {
                final url = item['url']?.toString() ?? '';
                final title = item['title']?.toString() ?? '';
                if (url.isNotEmpty && title.isNotEmpty && seenUrls.add(url)) {
                  searchResults.add(WebSearchResult(
                    title: title,
                    snippet: item['snippet']?.toString() ?? '',
                    url: url,
                  ));
                }
              }
              if (!completer.isCompleted) {
                completer.complete(searchResults);
              }
            } else {
              if (!completer.isCompleted) completer.complete([]);
            }
          } catch (e) {
            if (!completer.isCompleted) completer.complete([]);
          }
        },
        onReceivedError: (controller, request, error) {
          if (!completer.isCompleted) completer.complete([]);
        },
      );

      await headless.run();
      return await completer.future;
    } catch (e) {
      if (!completer.isCompleted) completer.complete([]);
      return await completer.future;
    } finally {
      timer.cancel();
      headless?.dispose();
    }
  }

  Future<List<WebSearchResult>> _searchOnce(String query,
      {int maxResults = 5}) async {
    final response = await http
        .post(
          Uri.parse(_baseUrl),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent':
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
          },
          body: 'q=${Uri.encodeComponent(query)}',
        )
        .timeout(_searchTimeout);

    if (response.statusCode == 429) {
      throw TimeoutException('Rate limited');
    }

    if (response.statusCode >= 500) {
      throw http.ClientException('Server error ${response.statusCode}');
    }

    if (response.statusCode != 200) return [];

    return _parseResults(response.body, maxResults);
  }

  Future<void> _fetchPageContent(WebSearchResult result) async {
    try {
      final response = await http.get(
        Uri.parse(result.url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
          'Accept': 'text/html',
        },
      ).timeout(_fetchTimeout);

      if (response.statusCode != 200) return;

      // Skip non-HTML responses
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('text/html') &&
          !contentType.contains('text/plain') &&
          !contentType.contains('application/xhtml')) {
        return;
      }

      // Skip responses > 1MB
      if (response.bodyBytes.length > 1024 * 1024) return;

      final extracted = extractTextFromHtml(response.body);
      if (extracted.isNotEmpty) {
        result.pageContent = extracted.length > _maxPageContentLength
            ? extracted.substring(0, _maxPageContentLength)
            : extracted;
      }
    } catch (e) {
      // Keep snippet as fallback
    }
  }

  List<WebSearchResult> _parseResults(String html, int maxResults) {
    final results = <WebSearchResult>[];
    final seenUrls = <String>{};

    final resultPattern = RegExp(
      r'<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>.*?'
      r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
      dotAll: true,
    );

    for (final match in resultPattern.allMatches(html)) {
      if (results.length >= maxResults) break;

      final rawUrl = match.group(1) ?? '';
      final title = _decodeHtmlEntities(match.group(2) ?? '')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .trim();
      final snippet = _decodeHtmlEntities(match.group(3) ?? '')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .trim();
      final actualUrl = _extractUrl(rawUrl);

      if (title.isNotEmpty && actualUrl.isNotEmpty && seenUrls.add(actualUrl)) {
        results.add(WebSearchResult(
          title: title,
          snippet: snippet,
          url: actualUrl,
        ));
      }
    }

    return results;
  }

  String _extractUrl(String ddgUrl) {
    final uddgMatch = RegExp(r'uddg=([^&]+)').firstMatch(ddgUrl);
    if (uddgMatch != null) {
      return Uri.decodeComponent(uddgMatch.group(1)!);
    }
    if (ddgUrl.startsWith('http')) return ddgUrl;
    return '';
  }
}

/// Simple semaphore for limiting concurrent async operations.
class _Semaphore {
  final int _maxCount;
  int _currentCount = 0;
  final _waitQueue = <Completer<void>>[];

  _Semaphore(this._maxCount);

  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_currentCount < _maxCount) {
      _currentCount++;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  void _release() {
    if (_waitQueue.isNotEmpty) {
      _waitQueue.removeAt(0).complete();
    } else {
      _currentCount--;
    }
  }
}
