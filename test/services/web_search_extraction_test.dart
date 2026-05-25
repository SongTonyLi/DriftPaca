import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Services/web_search_service.dart';

void main() {
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
