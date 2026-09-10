// Explicit live diagnostic; no model calls or API keys required.
// RUN_SEARCH_DIAGNOSTIC=1 flutter test --reporter expanded
// test/integration/search_retrieval_diagnostic_live_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Services/web_search_service.dart';

void main() {
  test('measure live search retrieval', () async {
    final queries = [
      'Jalen Brunson college basketball Villanova',
      'Tokyo Delhi Shanghai Sao Paulo population 2025',
      '越南 2025 GDP 世界银行',
    ];
    final report = <Map<String, Object?>>[];
    final repeats = int.tryParse(Platform.environment['SEARCH_DIAGNOSTIC_REPEATS'] ?? '') ?? 1;
    for (var run = 0; run < repeats; run++) {
      for (final query in queries) {
        if (report.isNotEmpty) await Future<void>.delayed(const Duration(seconds: 2));
        final watch = Stopwatch()..start();
        final rows = <Map<String, Object?>>[];
        final attempted = <String, WebSearchResult>{};
        int? discoveryMs;
        try {
          final results = await WebSearchService().searchAndExtract(
            query,
            onUrlsKnown: (urls) {
              discoveryMs ??= watch.elapsedMilliseconds;
              for (final result in urls) {
                attempted[result.url] = result;
              }
            },
            onUrlFetched: (url, success) {
              rows.add({
                'url': url,
                'extracted': success,
                'reason': attempted[url]?.fetchOutcome?.state.name,
                'httpStatus': attempted[url]?.fetchOutcome?.httpStatus,
                'downloadMs': attempted[url]?.fetchOutcome?.downloadElapsed.inMilliseconds,
                'extractionMs': attempted[url]?.fetchOutcome?.extractionElapsed.inMilliseconds,
                'completedMs': watch.elapsedMilliseconds
              });
            },
          );
          final record = {
            'query': query,
            'run': run + 1,
            'elapsedMs': watch.elapsedMilliseconds,
            'discoveryMs': discoveryMs,
            'returned': results.length,
            'extracted': results.where((r) => r.pageContent?.isNotEmpty == true).length,
            'pages': rows,
            'sources': results
                .map((r) => {
                      'url': r.url,
                      'textLength': r.pageContent?.length ?? 0,
                      'snippetLength': r.snippet.length,
                      'textPreview': (r.pageContent ?? '').substring(0, (r.pageContent?.length ?? 0).clamp(0, 180))
                    })
                .toList()
          };
          report.add(record);
          stdout.writeln(jsonEncode(record));
          await File('build/search_retrieval_diagnostic.json').writeAsString(jsonEncode(report));
        } on WebSearchUnavailableException catch (error) {
          stdout.writeln(jsonEncode({
            'query': query,
            'elapsedMs': watch.elapsedMilliseconds,
            'error': error.toString(),
            'remainingQueries': 'not attempted after throttle'
          }));
          report.add({'query': query, 'error': error.toString()});
          await File('build/search_retrieval_diagnostic.json').writeAsString(jsonEncode(report));
          return;
        }
      }
    }
  }, skip: Platform.environment['RUN_SEARCH_DIAGNOSTIC'] != '1', timeout: const Timeout(Duration(minutes: 15)));
}
