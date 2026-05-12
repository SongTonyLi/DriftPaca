import 'package:http/http.dart' as http;

class WebSearchResult {
  final String title;
  final String snippet;
  final String url;

  WebSearchResult({
    required this.title,
    required this.snippet,
    required this.url,
  });
}

class WebSearchService {
  static const _baseUrl = 'https://html.duckduckgo.com/html/';

  /// Searches DuckDuckGo and returns top results.
  /// Mirrors open-webui's search_duckduckgo() in retrieval/web/duckduckgo.py
  Future<List<WebSearchResult>> search(String query,
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
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return [];

    return _parseResults(response.body, maxResults);
  }

  /// Parses DuckDuckGo HTML results page.
  List<WebSearchResult> _parseResults(String html, int maxResults) {
    final results = <WebSearchResult>[];

    // DuckDuckGo HTML has results in <a class="result__a"> tags
    // and snippets in <a class="result__snippet"> tags
    final resultPattern = RegExp(
      r'<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>.*?'
      r'<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
      dotAll: true,
    );

    for (final match in resultPattern.allMatches(html)) {
      if (results.length >= maxResults) break;

      final rawUrl = match.group(1) ?? '';
      final title = _stripHtml(match.group(2) ?? '');
      final snippet = _stripHtml(match.group(3) ?? '');

      // DuckDuckGo wraps URLs in a redirect - extract the actual URL
      final actualUrl = _extractUrl(rawUrl);

      if (title.isNotEmpty && actualUrl.isNotEmpty) {
        results.add(WebSearchResult(
          title: title,
          snippet: snippet,
          url: actualUrl,
        ));
      }
    }

    return results;
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#x27;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  String _extractUrl(String ddgUrl) {
    // DuckDuckGo wraps URLs: //duckduckgo.com/l/?uddg=ENCODED_URL&...
    final uddgMatch = RegExp(r'uddg=([^&]+)').firstMatch(ddgUrl);
    if (uddgMatch != null) {
      return Uri.decodeComponent(uddgMatch.group(1)!);
    }
    if (ddgUrl.startsWith('http')) return ddgUrl;
    return '';
  }

  /// Formats search results as RAG context using open-webui's source tag format.
  /// Mirrors open-webui's get_source_context() and rag_template() in middleware.py
  static String formatResultsAsContext(
      List<WebSearchResult> results, String query) {
    if (results.isEmpty) return '';

    // Build <source> tags like open-webui's get_source_context()
    final sourceContext = StringBuffer();
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      sourceContext.writeln(
          '<source id="${i + 1}" name="${r.url}" resource-type="web_search">');
      sourceContext.writeln('${r.title}\n${r.snippet}');
      sourceContext.writeln('</source>');
    }

    // Apply open-webui's DEFAULT_RAG_TEMPLATE format
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
}
