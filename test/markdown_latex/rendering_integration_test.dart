/// Integration tests that hit the real Ollama Cloud API and verify rendering.
///
/// These tests call the API with prompts designed to elicit complex
/// markdown/LaTeX responses, then render them through ChatBubble and
/// verify no crashes or overflow errors occur.
///
/// Run with: flutter test test/markdown_latex/rendering_integration_test.dart
///
/// NOTE: Requires network access and a valid API key.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:http/http.dart' as http;
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart';

final String _apiKey = Platform.environment['OLLAMA_API_KEY'] ?? '';
const String _baseUrl = 'https://ollama.com';

/// Models to test rendering with — each produces different LaTeX styles.
const List<String> _models = [
  'gemma3:12b',
  'qwen3-next:80b',
  'deepseek-v3.2',
];

Widget _buildTestApp(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Future<List<FlutterErrorDetails>> _pumpAndCollectErrors(
  WidgetTester tester,
  String content, {
  Size surfaceSize = const Size(400, 2000),
}) async {
  final originalOnError = FlutterError.onError;
  final errors = <FlutterErrorDetails>[];

  addTearDown(() {
    FlutterError.onError = originalOnError;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = surfaceSize;

  try {
    FlutterError.onError = (details) {
      errors.add(details);
    };

    final message = OllamaMessage(
      content,
      role: OllamaMessageRole.assistant,
    );

    await tester.pumpWidget(_buildTestApp(ChatBubble(message: message)));
    await tester.pumpAndSettle();
    return errors;
  } finally {
    FlutterError.onError = originalOnError;
  }
}

List<FlutterErrorDetails> _overflowErrors(Iterable<FlutterErrorDetails> errors) {
  return errors.where((d) => d.exceptionAsString().contains('overflowed by')).toList();
}

/// Calls the Ollama Cloud API and returns the response content.
Future<String> _askModel(String model, String prompt) async {
  final url = Uri.parse('$_baseUrl/api/chat');

  final response = await http.post(
    url,
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_apiKey',
    },
    body: json.encode({
      'model': model,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'stream': false,
    }),
  );

  if (response.statusCode == 200) {
    final jsonBody = json.decode(response.body);
    return jsonBody['message']['content'] as String;
  } else {
    throw Exception('API error ${response.statusCode}: ${response.body}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  if (_apiKey.trim().isEmpty) {
    test(
      'live Markdown/LaTeX rendering integration tests',
      () {},
      skip: 'Set OLLAMA_API_KEY to run live rendering tests.',
    );
    return;
  }

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // ---------------------------------------------------------------------------
  // Group 1: Schrödinger's equation and quantum physics tables
  // ---------------------------------------------------------------------------
  group('real API — quantum physics equations in tables', () {
    for (final model in _models) {
      testWidgets('[$model] Schrödinger equation table renders without error', (tester) async {
        final response = await _askModel(
          model,
          'Write the time-dependent and time-independent Schrödinger equations. '
              'Present them in a markdown table with columns: Name, Equation, Notes. '
              'Include |Ψ|² probability density in one cell. Use LaTeX.',
        );

        final errors = await _pumpAndCollectErrors(tester, response);

        expect(_overflowErrors(errors), isEmpty,
            reason: 'Overflow in Schrödinger table from $model:\n${response.substring(0, 200.clamp(0, response.length))}');
        expect(find.byType(Math), findsWidgets,
            reason: 'Expected LaTeX widgets from $model response');
      }, timeout: Timeout.none);
    }
  });

  // ---------------------------------------------------------------------------
  // Group 2: Code blocks mixed with LaTeX
  // ---------------------------------------------------------------------------
  group('real API — code + markdown + LaTeX mixture', () {
    for (final model in _models) {
      testWidgets('[$model] heat equation with Python code renders', (tester) async {
        final response = await _askModel(
          model,
          'Explain the heat equation ∂u/∂t = α∇²u. Show:\n'
              '1. The PDE in LaTeX with boundary conditions\n'
              '2. Python code using numpy for finite differences\n'
              '3. The CFL stability condition as a formula\n'
              'Keep it concise.',
        );

        final errors = await _pumpAndCollectErrors(tester, response);

        expect(_overflowErrors(errors), isEmpty,
            reason: 'Overflow in code+LaTeX from $model');
        // Should have both code blocks and math
        expect(find.byType(Math), findsWidgets);
      }, timeout: Timeout.none);
    }
  });

  // ---------------------------------------------------------------------------
  // Group 3: Tables with pipes inside LaTeX (|Ψ|², |x|, etc.)
  // ---------------------------------------------------------------------------
  group('real API — pipes in LaTeX within tables', () {
    for (final model in _models) {
      testWidgets('[$model] set notation with pipes in table', (tester) async {
        final response = await _askModel(
          model,
          'Create a table with these math concepts, each using | (pipe) in LaTeX:\n'
              '| Concept | Formula |\n'
              'Include: absolute value |x|, norm ||v||, set builder {x | x>0}, '
              'conditional probability P(A|B), determinant |A|. Use LaTeX in cells.',
        );

        final errors = await _pumpAndCollectErrors(tester, response);

        expect(_overflowErrors(errors), isEmpty,
            reason: 'Pipe/LaTeX conflict in table from $model');
      }, timeout: Timeout.none);
    }
  });

  // ---------------------------------------------------------------------------
  // Group 4: Long unbreakable equations in narrow viewport
  // ---------------------------------------------------------------------------
  group('real API — long equations narrow viewport', () {
    for (final model in _models) {
      testWidgets('[$model] Maxwell equations table on narrow screen', (tester) async {
        final response = await _askModel(
          model,
          "Show Maxwell's 4 equations in both differential and integral form "
              "in a table. Use full LaTeX notation with all the integrals and operators.",
        );

        final errors = await _pumpAndCollectErrors(
          tester,
          response,
          surfaceSize: const Size(320, 2000), // narrow phone
        );

        expect(_overflowErrors(errors), isEmpty,
            reason: 'Overflow on narrow screen from $model');
      }, timeout: Timeout.none);
    }
  });

  // ---------------------------------------------------------------------------
  // Group 5: Statistics cheat sheet — dense LaTeX in tables
  // ---------------------------------------------------------------------------
  group('real API — statistics formulas table', () {
    for (final model in _models) {
      testWidgets('[$model] distribution formulas table renders', (tester) async {
        final response = await _askModel(
          model,
          'Create a statistics table with columns: Distribution, PDF/PMF, Mean, Variance.\n'
              'Include: Normal N(μ,σ²), Poisson P(λ), Binomial B(n,p), Exponential Exp(λ).\n'
              'Write all formulas in LaTeX.',
        );

        final errors = await _pumpAndCollectErrors(tester, response);

        expect(_overflowErrors(errors), isEmpty);
        expect(find.byType(Math), findsWidgets);
      }, timeout: Timeout.none);
    }
  });

  // ---------------------------------------------------------------------------
  // Group 6: Mixed delimiters (\(...\) and $...$)
  // ---------------------------------------------------------------------------
  group('real API — mixed LaTeX delimiters', () {
    for (final model in _models) {
      testWidgets('[$model] mixed delimiter styles render correctly', (tester) async {
        final response = await _askModel(
          model,
          r'Show these physics equations using \( \) for inline and \[ \] for display math: '
              r'E=mc², F=ma, p=mv. Then show them again using $ $ and $$ $$.',
        );

        final errors = await _pumpAndCollectErrors(tester, response);

        expect(_overflowErrors(errors), isEmpty);
        expect(find.byType(Math), findsWidgets);
      }, timeout: Timeout.none);
    }
  });

  // ---------------------------------------------------------------------------
  // Group 7: Currency ambiguity (\$5 vs $x$)
  // ---------------------------------------------------------------------------
  group('real API — currency vs LaTeX dollar signs', () {
    for (final model in _models) {
      testWidgets('[$model] pricing table with math formulas', (tester) async {
        final response = await _askModel(
          model,
          r'A store: widgets $5, gadgets $10, gizmos $15. '
              r'Create a table with columns: Item, Price, Quantity, Total. '
              r'Add a row for the total cost formula using LaTeX: $T = 5x + 10y + 15z$. '
              'Include profit formula P = 0.3T.',
        );

        final errors = await _pumpAndCollectErrors(tester, response);

        expect(_overflowErrors(errors), isEmpty,
            reason: 'Currency/LaTeX confusion from $model');
      }, timeout: Timeout.none);
    }
  });

  // ---------------------------------------------------------------------------
  // Group 8: Chinese text mixed with LaTeX
  // ---------------------------------------------------------------------------
  group('real API — CJK text with LaTeX', () {
    for (final model in _models) {
      testWidgets('[$model] Chinese Remainder Theorem in Chinese', (tester) async {
        final response = await _askModel(
          model,
          '用中文简要解释中国剩余定理。用LaTeX写出定理公式，并在表格中展示一个求解例子。',
        );

        final errors = await _pumpAndCollectErrors(tester, response);

        expect(_overflowErrors(errors), isEmpty,
            reason: 'CJK + LaTeX rendering error from $model');
      }, timeout: Timeout.none);
    }
  });

  // ---------------------------------------------------------------------------
  // Group 9: Deep nesting and continued fractions
  // ---------------------------------------------------------------------------
  group('real API — deeply nested fractions', () {
    for (final model in _models) {
      testWidgets('[$model] continued fractions render without crash', (tester) async {
        final response = await _askModel(
          model,
          'Show the continued fraction representation of √2 and the golden ratio φ. '
              'Use deeply nested \\frac{}{} notation in LaTeX. Show at least 5 levels deep.',
        );

        final errors = await _pumpAndCollectErrors(tester, response);

        expect(_overflowErrors(errors), isEmpty);
        expect(find.byType(Math), findsWidgets);
      }, timeout: Timeout.none);
    }
  });

  // ---------------------------------------------------------------------------
  // Group 10: Multi-step aligned proofs
  // ---------------------------------------------------------------------------
  group('real API — aligned equation proofs', () {
    for (final model in _models) {
      testWidgets('[$model] induction proof with aligned equations', (tester) async {
        final response = await _askModel(
          model,
          'Prove by induction that the sum 1+2+...+n = n(n+1)/2. '
              'Use aligned LaTeX equations for each step. '
              'Include both the base case and inductive step clearly.',
        );

        final errors = await _pumpAndCollectErrors(tester, response);

        expect(_overflowErrors(errors), isEmpty);
        expect(find.byType(Math), findsWidgets);
      }, timeout: Timeout.none);
    }
  });

  // ---------------------------------------------------------------------------
  // Group 11: Piecewise functions with cases environment
  // ---------------------------------------------------------------------------
  group('real API — piecewise functions', () {
    for (final model in _models) {
      testWidgets('[$model] cases/piecewise LaTeX renders', (tester) async {
        final response = await _askModel(
          model,
          'Show these piecewise functions using LaTeX cases environment:\n'
              '1. |x| (absolute value)\n'
              '2. sign(x)\n'
              '3. ReLU(x)\n'
              'Put them in a table with Name and Definition columns.',
        );

        final errors = await _pumpAndCollectErrors(tester, response);

        expect(_overflowErrors(errors), isEmpty);
        expect(find.byType(Math), findsWidgets);
      }, timeout: Timeout.none);
    }
  });

  // ---------------------------------------------------------------------------
  // Group 12: Very long responses with mixed content
  // ---------------------------------------------------------------------------
  group('real API — long mixed responses', () {
    for (final model in _models) {
      testWidgets('[$model] full calculus derivation renders', (tester) async {
        final response = await _askModel(
          model,
          'Derive the Taylor series expansion of e^x from scratch. Show:\n'
              '1. Definition of Taylor series (display math)\n'
              '2. Computing derivatives of e^x (inline math list)\n'
              '3. The pattern and final formula\n'
              '4. A table showing first 8 terms with numerical values\n'
              '5. Python code to verify numerically',
        );

        final errors = await _pumpAndCollectErrors(tester, response);

        expect(_overflowErrors(errors), isEmpty);
      }, timeout: Timeout.none);
    }
  });

  // ---------------------------------------------------------------------------
  // Group 13: Streaming simulation — partial content rendering
  // ---------------------------------------------------------------------------
  group('real API — partial/streaming content', () {
    for (final model in _models) {
      testWidgets('[$model] response truncated mid-equation renders safely', (tester) async {
        final response = await _askModel(
          model,
          'Write the complete derivation of the quadratic formula. Use display math.',
        );

        // Simulate streaming by truncating at various points
        final cutPoints = [
          response.length ~/ 4,
          response.length ~/ 2,
          (response.length * 3) ~/ 4,
        ];

        for (final cut in cutPoints) {
          final partial = response.substring(0, cut);
          final errors = await _pumpAndCollectErrors(tester, partial);

          // Partial content should never crash — it may show fallback
          final nonOverflowErrors = errors.where(
            (d) => !d.exceptionAsString().contains('overflowed by'),
          );
          expect(nonOverflowErrors, isEmpty,
              reason: 'Crash on partial content (cut=$cut) from $model');
        }
      }, timeout: Timeout.none);
    }
  });
}
