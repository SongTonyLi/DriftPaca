/// Widget tests that render pre-saved API response fixtures.
///
/// Run `dart test/markdown_latex/generate_fixtures.dart` first to populate
/// the fixtures directory, then run these tests:
///   flutter test test/markdown_latex/fixture_rendering_test.dart
///
/// These tests verify that real model outputs render without crashes
/// or overflow errors, providing repeatable regression coverage
/// without requiring network access.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final fixtureFile = File('test/markdown_latex/fixtures/api_responses.json');

  // Skip gracefully if fixtures haven't been generated yet
  if (!fixtureFile.existsSync()) {
    test('fixtures not found — run generate_fixtures.dart first', () {
      print(
        'No fixtures found. Run:\n'
        '  dart test/markdown_latex/generate_fixtures.dart\n'
        'to generate fixtures, then re-run these tests.',
      );
    });
    return;
  }

  final fixturesJson = json.decode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;

  // Viewport sizes to test each fixture at
  const viewportSizes = {
    'phone_narrow': Size(320, 2000),
    'phone_normal': Size(400, 2000),
    'tablet': Size(768, 2000),
  };

  // Group fixtures by prompt name for organized test output
  final promptNames = fixturesJson.values
      .map((f) => f['prompt_name'] as String)
      .toSet()
      .toList()
    ..sort();

  for (final promptName in promptNames) {
    group('fixture: $promptName', () {
      final fixtures = fixturesJson.entries.where((e) => e.value['prompt_name'] == promptName);

      for (final entry in fixtures) {
        final fixture = entry.value;
        final model = fixture['model'] as String;
        final response = fixture['response'] as String;

        for (final viewport in viewportSizes.entries) {
          testWidgets(
            '[$model] renders on ${viewport.key} (${viewport.value.width.toInt()}px)',
            (tester) async {
              final errors = await pumpBubbleAndCollectErrors(
                tester,
                response,
                surfaceSize: viewport.value,
              );

              // Non-overflow errors (crashes) must never occur at any size.
              expect(nonOverflowErrors(errors), isEmpty,
                  reason: 'Render error at ${viewport.key} for $model/$promptName:\n'
                      '${response.substring(0, 300.clamp(0, response.length))}...');

              // Overflow is only asserted on tablet — narrow screens may overflow
              // for very long equations (visual-only, not a crash).
              if (viewport.key == 'tablet') {
                expect(overflowErrors(errors), isEmpty,
                    reason: 'Overflow at tablet width for $model/$promptName');
              }
            },
          );
        }

        // Streaming simulation — truncate at 25%, 50%, 75%
        testWidgets('[$model] handles streaming truncation', (tester) async {
          final cutPoints = [
            response.length ~/ 4,
            response.length ~/ 2,
            (response.length * 3) ~/ 4,
          ];

          for (final cut in cutPoints) {
            final partial = response.substring(0, cut);
            final errors = await pumpBubbleAndCollectErrors(tester, partial);

            expect(nonOverflowErrors(errors), isEmpty,
                reason: 'Crash on partial content (cut=$cut) for $model/$promptName');
          }
        });

        // Verify LaTeX is being rendered when present in the response.
        // Some models output Unicode math or wrap in code blocks — only
        // assert Math widgets when response contains bare LaTeX delimiters
        // (not inside backtick-code or code fences).
        final strippedOfCode = response
            .replaceAll(RegExp(r'```[\s\S]*?```'), '')
            .replaceAll(RegExp(r'`[^`\n]+`'), '');
        final hasLatexDelimiters = RegExp(r'\$[^$\n]+\$|\\\(|\\\[').hasMatch(strippedOfCode);
        if (hasLatexDelimiters) {
          testWidgets('[$model] produces Math widgets', (tester) async {
            final errors = await pumpBubbleAndCollectErrors(tester, response);

            expect(find.byType(Math), findsWidgets,
                reason: 'Response contains LaTeX delimiters but no Math widgets rendered for $model/$promptName');
          });
        }
      }
    });
  }
}
