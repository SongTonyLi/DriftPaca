import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Services/web_search_service.dart';

void main() {
  group('decodeHtmlBytes', () {
    test('decodes UTF-8 Chinese page with no Content-Type charset', () {
      // Reproduces the bug from the screenshot: cssn.cn / gov.cn sites
      // serve UTF-8 but only declare it in <meta>, not the response header.
      const html =
          '<html><head><meta charset="utf-8"></head><body>'
          '满清入关战役的影响</body></html>';
      final bytes = utf8.encode(html);
      final decoded =
          WebSearchService.decodeHtmlBytes(bytes, contentTypeHeader: 'text/html');
      expect(decoded, contains('满清入关战役的影响'));
      // Negative check: Latin-1 decoding of the same bytes would produce
      // mojibake — confirm we didn't fall back to that.
      expect(decoded, isNot(contains('æ')));
    });

    test('honours charset from Content-Type header', () {
      const html =
          '<html><head><meta charset="iso-8859-1"></head><body>résumé</body></html>';
      final bytes = utf8.encode(html);
      final decoded = WebSearchService.decodeHtmlBytes(
        bytes,
        contentTypeHeader: 'text/html; charset=utf-8',
      );
      // Header wins over meta — header says UTF-8, bytes are UTF-8.
      expect(decoded, contains('résumé'));
    });

    test('respects <meta charset> when header has no charset', () {
      const html =
          '<html><head><meta charset="utf-8"></head><body>café</body></html>';
      final bytes = utf8.encode(html);
      final decoded = WebSearchService.decodeHtmlBytes(
        bytes,
        contentTypeHeader: 'text/html',
      );
      expect(decoded, contains('café'));
    });

    test('respects HTML4 http-equiv meta charset', () {
      const html =
          '<html><head><meta http-equiv="Content-Type" '
          'content="text/html; charset=utf-8"></head><body>北京</body></html>';
      final bytes = utf8.encode(html);
      final decoded = WebSearchService.decodeHtmlBytes(
        bytes,
        contentTypeHeader: 'text/html',
      );
      expect(decoded, contains('北京'));
    });

    test('falls back to UTF-8 when nothing is declared', () {
      // No charset in header, no meta tag — but bytes are UTF-8.
      const html = '<html><body>東京</body></html>';
      final bytes = utf8.encode(html);
      final decoded = WebSearchService.decodeHtmlBytes(bytes);
      expect(decoded, contains('東京'));
    });

    test('decodes ASCII content unchanged', () {
      const html = '<html><body>hello world</body></html>';
      final bytes = utf8.encode(html);
      final decoded = WebSearchService.decodeHtmlBytes(
        bytes,
        contentTypeHeader: 'text/html; charset=us-ascii',
      );
      expect(decoded, contains('hello world'));
    });

    test('handles unsupported charsets by falling back to UTF-8', () {
      // GBK is not in dart:convert. Bytes are actually UTF-8.
      const html =
          '<html><head><meta charset="gbk"></head><body>测试</body></html>';
      final bytes = utf8.encode(html);
      final decoded = WebSearchService.decodeHtmlBytes(bytes);
      // GBK lookup returns null → fall through → UTF-8 with allowMalformed
      // succeeds on this UTF-8 byte stream.
      expect(decoded, contains('测试'));
    });

    test('quoted charset value in header is unwrapped', () {
      const html = '<html><body>ok</body></html>';
      final bytes = utf8.encode(html);
      final decoded = WebSearchService.decodeHtmlBytes(
        bytes,
        contentTypeHeader: 'text/html; charset="utf-8"',
      );
      expect(decoded, contains('ok'));
    });
  });

  group('extractTextFromHtml', () {
    test('prioritizes article tag content', () {
      final html = '''
        <html><body>
          <nav>Navigation stuff</nav>
          <article>This is the article content.</article>
          <footer>Footer stuff</footer>
        </body></html>
      ''';
      final result = WebSearchService.extractTextFromHtml(html);
      expect(result, contains('This is the article content'));
      expect(result, isNot(contains('Navigation')));
      expect(result, isNot(contains('Footer')));
    });

    test('prioritizes main tag when no article', () {
      final html = '''
        <html><body>
          <header>Header stuff</header>
          <main>Main content here.</main>
          <aside>Sidebar</aside>
        </body></html>
      ''';
      final result = WebSearchService.extractTextFromHtml(html);
      expect(result, contains('Main content'));
      expect(result, isNot(contains('Header')));
      expect(result, isNot(contains('Sidebar')));
    });

    test('falls back to body when no article or main', () {
      final html = '''
        <html><body>
          <div>Some content here.</div>
          <script>var x = 1;</script>
          <style>.foo { color: red; }</style>
        </body></html>
      ''';
      final result = WebSearchService.extractTextFromHtml(html);
      expect(result, contains('Some content'));
      expect(result, isNot(contains('var x')));
      expect(result, isNot(contains('color: red')));
    });

    test('strips all boilerplate tags', () {
      final html = '''
        <html><body>
          <script>alert("xss")</script>
          <style>.hidden{}</style>
          <nav>nav</nav>
          <footer>foot</footer>
          <header>head</header>
          <aside>side</aside>
          <!-- comment -->
          <p>Real content.</p>
        </body></html>
      ''';
      final result = WebSearchService.extractTextFromHtml(html);
      expect(result, contains('Real content'));
      expect(result, isNot(contains('alert')));
      expect(result, isNot(contains('hidden')));
      expect(result, isNot(contains('comment')));
    });

    test('decodes HTML entities', () {
      final html = '<p>Tom &amp; Jerry &lt;3 &quot;fun&quot;</p>';
      final result = WebSearchService.extractTextFromHtml(html);
      expect(result, contains('Tom & Jerry'));
      expect(result, contains('"fun"'));
    });

    test('collapses whitespace', () {
      final html = '<p>Too    much   \n\n\n   space</p>';
      final result = WebSearchService.extractTextFromHtml(html);
      expect(result, isNot(contains('   ')));
    });

    test('returns empty string for empty input', () {
      expect(WebSearchService.extractTextFromHtml(''), isEmpty);
    });
  });
}
