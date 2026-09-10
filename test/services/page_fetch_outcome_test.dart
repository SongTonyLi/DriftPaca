import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llamaseek/Models/page_fetch_outcome.dart';
import 'package:llamaseek/Services/web_search_service.dart';

void main() {
  test('a transport timeout retains its timeout classification', () async {
    final service = WebSearchService(
        pageClientFactory: () => MockClient((_) async => throw TimeoutException('transport deadline')));
    expect((await service.fetchPage(Uri.parse('https://example.org'))).state, PageFetchState.timedOut);
  });
  test('oversized declared response stops before consuming its body', () async {
    var listened = false;
    final client = MockClient.streaming((_, __) async => http.StreamedResponse(Stream<List<int>>.multi((controller) {
          listened = true;
          controller.add([1]);
          controller.close();
        }), 200, contentLength: 64 * 1024 * 1024, headers: {'content-type': 'text/html'}));
    final result = await WebSearchService(pageClientFactory: () => client).fetchPage(Uri.parse('https://example.org'));
    expect(result.state, PageFetchState.tooLarge);
    expect(listened, isFalse);
  });
  test('preserves status and rejects non-page responses', () async {
    for (final entry in {
      403: PageFetchState.httpError,
      404: PageFetchState.httpError,
      429: PageFetchState.httpError,
    }.entries) {
      final service = WebSearchService(
          pageClientFactory: () =>
              MockClient((_) async => http.Response('Forbidden', entry.key, headers: {'content-type': 'text/html'})));
      final result = await service.fetchPage(Uri.parse('https://example.org'));
      expect(result.state, entry.value);
      expect(result.httpStatus, entry.key);
      expect(result.text, isNull);
    }
  });

  test('extracts HTML and plain text but rejects PDF and empty pages', () async {
    for (final row in [
      ('text/html', '<article>Useful evidence</article>', PageFetchState.extracted),
      ('text/plain', 'Useful evidence', PageFetchState.extracted),
      ('application/pdf', '%PDF-1.7', PageFetchState.unsupportedType),
      ('text/html', '<html></html>', PageFetchState.emptyText),
    ]) {
      final service = WebSearchService(
          pageClientFactory: () =>
              MockClient((_) async => http.Response(row.$2, 200, headers: {'content-type': row.$1})));
      final result = await service.fetchPage(Uri.parse('https://example.org'));
      expect(result.state, row.$3);
      if (result.isSuccess) expect(result.text, 'Useful evidence');
    }
  });

  test('timeout closes its own transport and returns a typed failure', () async {
    final client = _HangingClient();
    final result = await WebSearchService(pageClientFactory: () => client)
        .fetchPage(Uri.parse('https://example.org'), timeout: const Duration(milliseconds: 10));
    expect(result.state, PageFetchState.timedOut);
    expect(client.closed, isTrue);
  });

  test('cancellation closes transport without waiting for HTTP', () async {
    final cancel = Completer<void>();
    final client = _HangingClient();
    final result = WebSearchService(pageClientFactory: () => client)
        .fetchPage(Uri.parse('https://example.org'), cancelled: cancel.future);
    cancel.complete();
    expect((await result).state, PageFetchState.cancelled);
    expect(client.closed, isTrue);
  });

  test('transport exceptions are distinct from HTTP failures', () async {
    final service =
        WebSearchService(pageClientFactory: () => MockClient((_) async => throw http.ClientException('disconnected')));
    expect((await service.fetchPage(Uri.parse('https://example.org'))).state, PageFetchState.networkError);
  });
}

class _HangingClient extends http.BaseClient {
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => Completer<http.StreamedResponse>().future;
  @override
  void close() {
    closed = true;
  }
}
