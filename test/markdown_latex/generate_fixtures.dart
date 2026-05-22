/// Fixture generator for markdown/LaTeX rendering tests.
///
/// Run with: dart test/markdown_latex/generate_fixtures.dart
///
/// This script hits the Ollama Cloud API with carefully crafted prompts
/// using multiple models to generate real-world responses that exercise
/// markdown and LaTeX rendering edge cases. Responses are saved as JSON
/// fixtures for repeatable widget tests.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

final String apiKey = Platform.environment['OLLAMA_API_KEY'] ?? '';
const String baseUrl = 'https://ollama.com';

/// Models to test across — different models produce different LaTeX styles.
const List<String> models = [
  'gemma3:12b',
  'qwen3-next:80b',
  'deepseek-v3.2',
];

/// Prompts designed to elicit specific markdown/LaTeX patterns.
const Map<String, String> prompts = {
  // --- Physics: Schrödinger & quantum mechanics ---
  'schrodinger_equations': '''
Write Schrödinger's equation (time-dependent and time-independent forms) and present them in a markdown table alongside related quantum mechanics equations (Dirac equation, Klein-Gordon equation, Heisenberg uncertainty principle). Include the probability density |Ψ|² in the table cells. Use LaTeX notation.
''',

  // --- Dense table with long equations ---
  'calculus_comparison_table': '''
Create a comparison table of integration formulas with these columns: Name, Formula, Example. Include at least 8 rows: integration by parts, substitution, partial fractions, trigonometric substitution, improper integrals, double integrals, line integrals, and surface integrals. Use full LaTeX notation for all formulas.
''',

  // --- Code + LaTeX mixture ---
  'code_and_math_mixture': '''
Explain how to numerically solve the heat equation ∂u/∂t = α∇²u. Show:
1. The mathematical formulation with boundary conditions using LaTeX
2. A Python implementation using finite differences
3. The stability condition (CFL condition) as a LaTeX formula
4. A table comparing explicit vs implicit methods with their stability formulas
''',

  // --- Set builder notation with pipes in tables ---
  'set_builder_pipes': '''
Create a reference table of set theory notation. Include: set builder notation {x | P(x)}, absolute value |x|, norms ||v||, conditional probability P(A|B), and determinants |A|. Show each in a markdown table with columns: Symbol, LaTeX, Meaning. Use actual LaTeX rendering.
''',

  // --- Matrix norms and absolute values ---
  'matrix_norms': '''
Explain different matrix norms in a table format. Include:
- Frobenius norm: ||A||_F
- Spectral norm: ||A||_2
- Max norm: ||A||_max
- L1 norm: ||A||_1
For each, show the formula with absolute values and pipes. Also show the relationship between vector norms and matrix norms.
''',

  // --- Long unbreakable equations ---
  'long_chain_equations': '''
Show the complete derivation of the Euler-Lagrange equation starting from the action principle. Write it as a chain of equalities on single lines. Then show Maxwell's equations in both differential and integral form in a table.
''',

  // --- Piecewise functions ---
  'piecewise_functions': '''
Show examples of piecewise functions using the cases environment in LaTeX:
1. Absolute value function
2. Sign function
3. Heaviside step function
4. ReLU activation function
5. Softmax (with the full formula)
Put them all in a table with Name, Definition (using cases), and Domain columns.
''',

  // --- Aligned equations / multi-step proof ---
  'aligned_proof': '''
Prove that the sum of the first n squares is n(n+1)(2n+1)/6 using mathematical induction. Show each step with aligned equations. Use display math for the key steps and inline math for the explanatory text.
''',

  // --- Mixed delimiters ---
  'mixed_delimiters': '''
Show the following physics equations using \\( \\) for inline math and \\[ \\] for display math:
- Einstein's mass-energy equivalence
- Planck-Einstein relation
- de Broglie wavelength
- Heisenberg uncertainty principle
- Schrödinger equation
Then show them again in a table using \$ \$ and \$\$ \$\$ notation for comparison.
''',

  // --- Currency vs math ambiguity ---
  'pricing_and_formulas': '''
A store sells widgets for \$5, gadgets for \$10, and gizmos for \$15. If a customer buys x widgets, y gadgets, and z gizmos:
1. Write the total cost formula
2. If the profit margin is 30%, write the profit formula
3. Create a pricing table showing items, unit cost, quantity formula, and total with both dollar amounts and mathematical expressions
''',

  // --- Statistics with heavy LaTeX ---
  'statistics_cheatsheet': '''
Create a statistics cheat sheet as a table with these distributions:
- Normal N(μ,σ²): PDF, mean, variance
- Poisson P(λ): PMF, mean, variance
- Binomial B(n,p): PMF, mean, variance
- Exponential Exp(λ): PDF, CDF, mean, variance
- Chi-squared χ²(k): PDF, mean, variance
Include all formulas in LaTeX.
''',

  // --- Conditional probability with set notation in tables ---
  'conditional_probability': '''
Explain Bayes' theorem with a table showing:
| Concept | Formula | Description |
Include: prior P(A), likelihood P(B|A), marginal P(B), posterior P(A|B), and the full Bayes formula. Use set notation with pipes (|) for conditional probability.
''',

  // --- Chinese + LaTeX ---
  'chinese_remainder_theorem': '''
用中文解释中国剩余定理（Chinese Remainder Theorem）。包含：
1. 定理的数学表述（用LaTeX）
2. 求解步骤
3. 一个具体的数值例子
4. 用表格展示求解过程
''',

  // --- Complex nested fractions ---
  'continued_fractions': '''
Show the continued fraction representation of:
1. The golden ratio φ
2. √2
3. e (Euler's number)
4. π (using Ramanujan's formula)
Present each as both a continued fraction and its convergents in a table. Use deeply nested fractions.
''',

  // --- Streaming cutoff simulation ---
  'incomplete_latex': '''
Write out the complete proof of the Pythagorean theorem using coordinate geometry. Include:
- Setting up coordinates
- Distance formula
- The algebraic expansion
- Final simplification
Use both inline and display math throughout. Make it detailed with many intermediate steps.
''',
};

Future<String?> chatWithModel(String model, String prompt) async {
  final url = Uri.parse('$baseUrl/api/chat');

  final body = json.encode({
    'model': model,
    'messages': [
      {'role': 'user', 'content': prompt},
    ],
    'stream': false,
  });

  try {
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: body,
    );

    if (response.statusCode == 200) {
      final jsonBody = json.decode(response.body);
      return jsonBody['message']['content'] as String?;
    } else {
      stderr.writeln('  ERROR [$model]: ${response.statusCode} ${response.body.substring(0, 200.clamp(0, response.body.length))}');
      return null;
    }
  } catch (e) {
    stderr.writeln('  ERROR [$model]: $e');
    return null;
  }
}

Future<void> main() async {
  final fixturesDir = Directory('test/markdown_latex/fixtures');
  if (!fixturesDir.existsSync()) {
    fixturesDir.createSync(recursive: true);
  }

  final allFixtures = <String, dynamic>{};

  for (final model in models) {
    stdout.writeln('\n=== Model: $model ===');

    for (final entry in prompts.entries) {
      final name = entry.key;
      final prompt = entry.value;
      final fixtureKey = '${model.replaceAll(':', '_').replaceAll('.', '_')}__$name';

      stdout.write('  $name ... ');
      final response = await chatWithModel(model, prompt);

      if (response != null) {
        allFixtures[fixtureKey] = {
          'model': model,
          'prompt_name': name,
          'prompt': prompt.trim(),
          'response': response,
          'generated_at': DateTime.now().toIso8601String(),
        };
        stdout.writeln('OK (${response.length} chars)');
      } else {
        stdout.writeln('FAILED');
      }

      // Small delay to avoid rate limiting
      await Future.delayed(Duration(milliseconds: 500));
    }
  }

  // Write all fixtures to a single JSON file
  final outputFile = File('${fixturesDir.path}/api_responses.json');
  final encoder = JsonEncoder.withIndent('  ');
  outputFile.writeAsStringSync(encoder.convert(allFixtures));
  stdout.writeln('\n✓ Wrote ${allFixtures.length} fixtures to ${outputFile.path}');

  // Also write individual fixture files per prompt (all models combined)
  for (final promptName in prompts.keys) {
    final promptFixtures = <String, dynamic>{};
    for (final model in models) {
      final key = '${model.replaceAll(':', '_').replaceAll('.', '_')}__$promptName';
      if (allFixtures.containsKey(key)) {
        promptFixtures[model] = allFixtures[key];
      }
    }
    if (promptFixtures.isNotEmpty) {
      final file = File('${fixturesDir.path}/$promptName.json');
      file.writeAsStringSync(encoder.convert(promptFixtures));
    }
  }

  stdout.writeln('✓ Wrote individual fixture files per prompt');
}
