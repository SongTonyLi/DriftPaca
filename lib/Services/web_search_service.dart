import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
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

  /// Shared client across all WebSearchService instances so the connection
  /// pool survives between searches (the service itself is instantiated
  /// per-search). DDG is always the same host; reuse is significant there.
  static final http.Client _client = http.Client();

  /// Domains that are walled gardens, video/image-only, or content farms.
  /// Filtered out before page fetching to save bandwidth and improve quality.
  static const _blockedDomains = <String>{
    // Walled gardens / hard to scrape
    'facebook.com', 'instagram.com', 'tiktok.com',
    'twitter.com', 'x.com', 'threads.net',
    // Video/image — no extractable text
    'youtube.com', 'youtu.be', 'vimeo.com',
    'imgur.com', 'flickr.com', 'giphy.com',
    // Content farms / low signal
    'pinterest.com', 'pinterest.co', 'pin.it',
    'quora.com',
  };

  static bool _isReliableSource(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    for (final blocked in _blockedDomains) {
      if (host == blocked || host.endsWith('.$blocked')) return false;
    }
    return true;
  }

  // ============================================================
  // Public API
  // ============================================================

  /// Full search pipeline with text chunking:
  /// 1. Search DuckDuckGo
  /// 2. Fetch full page content (concurrency-limited)
  /// 3. Chunk content with recursive text splitter
  /// 4. Filter out empty results, preserving DDG relevance order
  ///
  /// Optional progress callbacks let the UI render a pending → resolved
  /// transition: [onUrlsKnown] fires once after DDG returns and before
  /// page fetches begin; [onUrlFetched] fires per URL as each fetch
  /// resolves with a success bool.
  Future<List<WebSearchResult>> searchAndExtract(
    String query, {
    int maxResults = 8,
    void Function(List<WebSearchResult> urls)? onUrlsKnown,
    void Function(String url, bool success)? onUrlFetched,
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() == true) return [];
    final results = await searchAndFetch(
      query,
      maxResults: maxResults,
      onUrlsKnown: onUrlsKnown,
      onUrlFetched: onUrlFetched,
      isCancelled: isCancelled,
    );
    if (isCancelled?.call() == true) return [];

    for (final result in results) {
      if (result.pageContent != null && result.pageContent!.isNotEmpty) {
        result.chunks = splitText(
          result.pageContent!,
          chunkSize: 1500,
          overlap: 200,
        );
      }
    }

    // Preserve DuckDuckGo's search-engine relevance ordering.
    // Only filter out results that failed to fetch any content.
    return results
        .where((r) => r.pageContent != null || r.snippet.isNotEmpty)
        .take(maxResults)
        .toList();
  }

  /// Search DuckDuckGo + fetch page content (concurrency-limited).
  /// Overfetches from DDG, filters unreliable sources, then fetches pages
  /// for the top results only.
  Future<List<WebSearchResult>> searchAndFetch(
    String query, {
    int maxResults = 8,
    void Function(List<WebSearchResult> urls)? onUrlsKnown,
    void Function(String url, bool success)? onUrlFetched,
    bool Function()? isCancelled,
  }) async {
    // Overfetch to compensate for filtered sources
    final results = await search(query,
        maxResults: maxResults + 4, isCancelled: isCancelled);
    if (results.isEmpty) return results;
    if (isCancelled?.call() == true) return [];

    // Drop unreliable sources, keep DDG relevance order
    results.removeWhere((r) => !_isReliableSource(r.url));

    // Only fetch pages for what we need
    final toFetch = results.take(maxResults).toList();

    if (isCancelled?.call() == true) return toFetch;
    // Notify the UI of the URL list before fetching starts so the
    // search card can render each row in a "pending" state.
    onUrlsKnown?.call(toFetch);

    final semaphore = _Semaphore(_maxConcurrentFetches);
    await Future.wait(
      toFetch.map((r) => semaphore.run(() async {
            if (isCancelled?.call() == true) return;
            await _fetchPageContent(r);
            if (isCancelled?.call() == true) return;
            final ok = r.pageContent != null && r.pageContent!.isNotEmpty;
            onUrlFetched?.call(r.url, ok);
          })),
      eagerError: false,
    );

    return toFetch;
  }

  /// Searches DuckDuckGo via WebView (primary) with HTTP fallback.
  Future<List<WebSearchResult>> search(String query,
      {int maxResults = 5, bool Function()? isCancelled}) async {
    if (isCancelled?.call() == true) return [];
    // Try WebView first (bypasses CAPTCHA)
    try {
      final results = await _searchViaWebView(query,
          maxResults: maxResults, isCancelled: isCancelled);
      if (results.isNotEmpty) return results;
    } catch (e) {
      // WebView failed, fall back to HTTP
    }
    if (isCancelled?.call() == true) return [];

    // Fall back to HTTP (may be CAPTCHA-blocked)
    try {
      return await _searchOnce(query, maxResults: maxResults);
    } catch (e) {
      if (e is TimeoutException ||
          e is SocketException ||
          e is http.ClientException) {
        if (isCancelled?.call() == true) return [];
        await Future.delayed(_retryBackoff);
        if (isCancelled?.call() == true) return [];
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
Respond to the user query using the provided sources. Cross-reference multiple sources to verify facts before stating them — if sources disagree, note the discrepancy. Cite sources inline using [id] format.

### Guidelines:
- Cross-reference all sources: compare data across sources and prefer claims supported by multiple sources.
- If sources conflict, state what each source says and which seems most reliable.
- If you don't know the answer, clearly state that.
- Respond in the same language as the user's query.
- Cite every reference using EXACTLY the form `[N]`, where N is the source id digit — `[1]` for source id="1", `[3]` for source id="3", `[10]` for source id="10". This is the only accepted citation format. Always write the marker with ASCII square brackets and plain ASCII digits 0-9 and nothing inside but the digit — even when the rest of your answer is in Chinese or another language. Never translate, localize, relabel, or restyle it: do not write `[id:1]`, `[src:1]`, `[source:1]`, `[来源:1]`, `[来源：1]`, `【1】`, `(src 1)`, `(source 1)`, `(see source 1)`, fullwidth brackets `【】`, fullwidth colons `：`, fullwidth digits, superscript digits like `[¹]`, `[²]`, `[³]`, or any other variant — those will not render as links. Never wrap the marker (or a chain of markers) in backticks or any code formatting — `` `[1]` ``, `` `[1][2]` ``, `` ``[1]`` ``, indented-by-4-spaces lines — those make it render as monospace literal text, not a clickable link. For multiple sources, write each one in its own bracket and chain them with no separator: `[1][3][5]`. Never group ids inside a single bracket as a comma list — do not write `[1, 3, 5]`, `[1,3,5]`, `[1，3，5]`, `[1、3、5]`, `【1, 3, 5】`, or any similar grouped form — those break rendering because the comma stops the citation parser. Use the same `[N]` form in prose, tables, list items, and headers alike.

<context>
${sourceContext.toString().trim()}
</context>
''';
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
      {int maxResults = 5, bool Function()? isCancelled}) async {
    final completer = Completer<List<WebSearchResult>>();
    HeadlessInAppWebView? headless;

    final timer = Timer(const Duration(seconds: 12), () {
      if (!completer.isCompleted) {
        completer.complete([]);
      }
    });

    // Poll cancellation alongside the result poll so a stop during the
    // 12s WebView load short-circuits without waiting for the timeout.
    Timer? cancelPoll;
    if (isCancelled != null) {
      cancelPoll = Timer.periodic(const Duration(milliseconds: 100), (t) {
        if (isCancelled() && !completer.isCompleted) {
          completer.complete([]);
          t.cancel();
        }
      });
    }

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
      cancelPoll?.cancel();
      headless?.dispose();
    }
  }

  Future<List<WebSearchResult>> _searchOnce(String query,
      {int maxResults = 5}) async {
    final response = await _client
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
      final response = await _client.get(
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

      final html = _decodeResponseBody(response);
      final extracted = extractTextFromHtml(html);
      if (extracted.isNotEmpty) {
        result.pageContent = extracted.length > _maxPageContentLength
            ? extracted.substring(0, _maxPageContentLength)
            : extracted;
      }
    } catch (e) {
      // Keep snippet as fallback
    }
  }

  /// Decodes response bytes using the correct character encoding.
  ///
  /// `response.body` decodes with Latin-1 whenever the `Content-Type` header
  /// omits a `charset` — which is the norm for many Chinese/Japanese sites
  /// that declare encoding only in `<meta charset>`. Reading those as
  /// Latin-1 produces mojibake (`æ§¶å°²…`) in the extracted text.
  ///
  /// Resolution order: Content-Type charset → `<meta charset>` scanned from
  /// the first 4KB (using Latin-1 to safely walk ASCII) → UTF-8.
  static String _decodeResponseBody(http.Response response) =>
      decodeHtmlBytes(response.bodyBytes,
          contentTypeHeader: response.headers['content-type'] ?? '');

  @visibleForTesting
  static String decodeHtmlBytes(
    List<int> bytes, {
    String contentTypeHeader = '',
  }) {
    final headerCharset = _extractHeaderCharset(contentTypeHeader);
    if (headerCharset != null) {
      final decoded = _tryDecodeBytes(bytes, headerCharset);
      if (decoded != null) return decoded;
    }

    // Latin-1 round-trips bytes 0x00..0xFF, so the ASCII parts of the head
    // remain readable regardless of the document's real encoding.
    final headSize = bytes.length < 4096 ? bytes.length : 4096;
    final headPeek = latin1.decode(bytes.sublist(0, headSize));
    final metaCharset = _extractMetaCharset(headPeek);
    if (metaCharset != null) {
      final decoded = _tryDecodeBytes(bytes, metaCharset);
      if (decoded != null) return decoded;
    }

    return utf8.decode(bytes, allowMalformed: true);
  }

  static final _headerCharsetPattern =
      RegExp(r'charset\s*=\s*"?([\w-]+)', caseSensitive: false);

  static String? _extractHeaderCharset(String contentType) =>
      _headerCharsetPattern.firstMatch(contentType)?.group(1)?.toLowerCase();

  // Matches both HTML5 `<meta charset="utf-8">` and HTML4
  // `<meta http-equiv="Content-Type" content="text/html; charset=...">`.
  static final _metaCharsetPattern =
      RegExp(r'''<meta[^>]+charset\s*=\s*["']?([\w-]+)''',
          caseSensitive: false);

  static String? _extractMetaCharset(String html) =>
      _metaCharsetPattern.firstMatch(html)?.group(1)?.toLowerCase();

  static String? _tryDecodeBytes(List<int> bytes, String charset) {
    switch (charset) {
      case 'utf-8':
      case 'utf8':
        return utf8.decode(bytes, allowMalformed: true);
      case 'iso-8859-1':
      case 'latin1':
      case 'latin-1':
        return latin1.decode(bytes);
      case 'us-ascii':
      case 'ascii':
        return ascii.decode(bytes, allowInvalid: true);
      default:
        // GBK, Big5, Shift-JIS, etc. — dart:convert doesn't ship decoders
        // for these. Caller falls through to UTF-8 with allowMalformed.
        return null;
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
