import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Services/search_orchestrator.dart';

void main() {
  group('sanitizeQuery', () {
    test('strips quotes', () {
      expect(SearchOrchestrator.sanitizeQuery('"flutter update"'), 'flutter update');
      expect(SearchOrchestrator.sanitizeQuery("'dart 3.0'"), 'dart 3.0');
    });

    test('strips backticks', () {
      expect(SearchOrchestrator.sanitizeQuery('`flutter`'), 'flutter');
      expect(SearchOrchestrator.sanitizeQuery('```query```'), 'query');
    });

    test('strips asterisks', () {
      expect(SearchOrchestrator.sanitizeQuery('**bold query**'), 'bold query');
    });

    test('preserves normal text', () {
      expect(SearchOrchestrator.sanitizeQuery('flutter state management'), 'flutter state management');
    });

    test('handles empty string', () {
      expect(SearchOrchestrator.sanitizeQuery(''), '');
    });
  });

  group('parseEvaluation', () {
    test('detects DONE signals', () {
      for (final signal in ['DONE', 'I have enough information', 'READY', 'sufficient']) {
        final result = SearchOrchestrator.parseEvaluation('Some reasoning\n$signal');
        expect(result.canAnswer, true, reason: 'Failed for signal: $signal');
      }
    });

    test('extracts search query with SEARCH: prefix', () {
      final result = SearchOrchestrator.parseEvaluation(
        'I need more info about the API.\nSEARCH: flutter riverpod tutorial',
      );
      expect(result.canAnswer, false);
      expect(result.nextQuery, 'flutter riverpod tutorial');
      expect(result.reasoning, 'I need more info about the API.');
    });

    test('uses last line as query when no SEARCH prefix', () {
      final result = SearchOrchestrator.parseEvaluation(
        'Missing details.\nflutter 4.0 release date',
      );
      expect(result.canAnswer, false);
      expect(result.nextQuery, 'flutter 4.0 release date');
    });

    test('treats empty response as done', () {
      final result = SearchOrchestrator.parseEvaluation('');
      expect(result.canAnswer, true);
    });

    test('treats too-long query as done', () {
      final longQuery = 'a' * 201;
      final result = SearchOrchestrator.parseEvaluation('Reasoning\n$longQuery');
      expect(result.canAnswer, true);
    });

    test('strips quotes from query', () {
      final result = SearchOrchestrator.parseEvaluation(
        'Need more.\nSEARCH: "dart async patterns"',
      );
      expect(result.canAnswer, false);
      expect(result.nextQuery, 'dart async patterns');
    });

    test('handles single-line done signal', () {
      final result = SearchOrchestrator.parseEvaluation('DONE');
      expect(result.canAnswer, true);
      expect(result.reasoning, '');
    });

    test('handles search for: prefix', () {
      final result = SearchOrchestrator.parseEvaluation(
        'Need more.\nSearch for: React hooks best practices',
      );
      expect(result.canAnswer, false);
      expect(result.nextQuery, 'React hooks best practices');
    });

    test('preserves reasoning text', () {
      final result = SearchOrchestrator.parseEvaluation(
        'The results show Flutter 3.x but not 4.x.\nI need to find the latest release.\nSEARCH: Flutter 4 release',
      );
      expect(result.canAnswer, false);
      expect(result.reasoning, contains('Flutter 3.x'));
      expect(result.reasoning, contains('latest release'));
    });
  });
}
