/// Stress tests specifically for LaTeX inside markdown tables.
///
/// Tables are the most fragile area because:
/// - Markdown table `|` conflicts with LaTeX `|` (absolute value, norms, etc.)
/// - Long equations can overflow narrow table cells
/// - Display math inside table cells is unusual
/// - Multiple LaTeX expressions per cell compound all issues
library;

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

  // ---------------------------------------------------------------------------
  // Pipe conflicts: LaTeX absolute values / norms inside table cells
  // ---------------------------------------------------------------------------
  group('pipe conflicts in table cells', () {
    testWidgets('single absolute value |x| in cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Expression | Value |\n| --- | --- |\n| Absolute | \$|x|\$ |',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('double norm ||v|| in cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Norm | Formula |\n| --- | --- |\n| L2 | \$||v||_2\$ |',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('probability density |Ψ|² in cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Quantity | Expression |\n| --- | --- |\n| Probability | \$\\rho = |\\Psi|^2\$ |',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('conditional probability P(A|B) in cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Concept | Formula |\n| --- | --- |\n| Bayes | \$P(A|B) = \\frac{P(B|A)P(A)}{P(B)}\$ |',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('set builder {x | x > 0} in cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Set | Definition |\n| --- | --- |\n| Positive reals | \$\\{x | x > 0\\}\$ |',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('determinant |A| in cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Property | Formula |\n| --- | --- |\n| Determinant | \$|A| = ad - bc\$ |',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('multiple pipe-containing expressions in different cells same row', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Norm | Abs |\n| --- | --- |\n| \$||v||\$ | \$|x|\$ |',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('pipes in multiple rows', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Name | Formula |\n| --- | --- |\n'
            '| Abs value | \$|x|\$ |\n'
            '| Norm | \$||v||_2\$ |\n'
            '| Cond. prob | \$P(A|B)\$ |\n'
            '| Determinant | \$|A|\$ |',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('\\vert and \\lvert already escaped by model', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Expression |\n| --- |\n| \$\\lvert x \\rvert + \\lVert v \\rVert\$ |',
      );
      expect(nonOverflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('\\mid for set builder (model-escaped)', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Set |\n| --- |\n| \$\\{x \\mid x > 0\\}\$ |',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('mixing raw pipes and \\vert in same table', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Raw pipe | Escaped |\n| --- | --- |\n| \$|x|\$ | \$\\vert y \\vert\$ |',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Long unbreakable equations in table cells
  // ---------------------------------------------------------------------------
  group('long equations in table cells', () {
    testWidgets('very long summation in cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Formula |\n| --- |\n| \$\\sum_{i=1}^{n} \\frac{x_i^2 + y_i^2 + z_i^2}{\\sigma_x^2 + \\sigma_y^2 + \\sigma_z^2}\$ |',
        surfaceSize: const Size(320, 800),
      );
      expect(overflowErrors(errors), isEmpty);
    });

    testWidgets('wide matrix in cell on narrow screen', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Matrix |\n| --- |\n| \$\\begin{pmatrix} a_{11} & a_{12} & a_{13} & a_{14} & a_{15} & a_{16} \\\\ b_{21} & b_{22} & b_{23} & b_{24} & b_{25} & b_{26} \\end{pmatrix}\$ |',
        surfaceSize: const Size(300, 800),
      );
      expect(overflowErrors(errors), isEmpty);
    });

    testWidgets('chain of fractions in cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Chain |\n| --- |\n| \$\\frac{a}{b} + \\frac{c}{d} + \\frac{e}{f} + \\frac{g}{h} + \\frac{i}{j} + \\frac{k}{l} + \\frac{m}{n}\$ |',
        surfaceSize: const Size(320, 800),
      );
      expect(overflowErrors(errors), isEmpty);
    });

    testWidgets('deeply nested fraction in cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Continued fraction |\n| --- |\n| \$1 + \\frac{1}{1 + \\frac{1}{1 + \\frac{1}{1 + \\frac{1}{1 + \\frac{1}{1 + \\cdots}}}}}\$ |',
        surfaceSize: const Size(320, 800),
      );
      expect(overflowErrors(errors), isEmpty);
    });

    testWidgets('integral with long limits in cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Integral |\n| --- |\n| \$\\int_{x=a_{\\min}}^{x=b_{\\max}} \\frac{\\partial^2 f(x,y,z)}{\\partial x \\partial y} \\, dx \\, dy \\, dz\$ |',
        surfaceSize: const Size(320, 800),
      );
      expect(overflowErrors(errors), isEmpty);
    });

    testWidgets('product notation with complex indices in cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Product |\n| --- |\n| \$\\prod_{k=1}^{N} \\left(1 + \\frac{x_k^2}{\\sigma_k^2}\\right)^{-\\alpha_k/2}\$ |',
        surfaceSize: const Size(320, 800),
      );
      expect(overflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Multiple LaTeX expressions per cell
  // ---------------------------------------------------------------------------
  group('multiple LaTeX expressions per cell', () {
    testWidgets('two inline equations in one cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Relations |\n| --- |\n| \$a \\leq b\$ and \$c \\geq d\$ |',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('inline equation + text + inline equation in cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Note |\n| --- |\n| If \$x > 0\$ then \$\\sqrt{x}\$ exists |',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('three equations in a cell with <br> separators', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Steps |\n| --- |\n| \$x = 1\$<br>\$y = 2\$<br>\$z = x + y = 3\$ |',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('cell with LaTeX followed by code', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Math | Code |\n| --- | --- |\n| \$x^2\$ | `x**2` |',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Display math in table cells
  // ---------------------------------------------------------------------------
  group('display math in table cells', () {
    testWidgets('double-dollar display math in cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Equation |\n| --- |\n| \$\$\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}\$\$ |',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });

    testWidgets('display math with \\[ \\] delimiters in cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Equation |\n| --- |\n| \\[\\sum_{n=0}^{\\infty} \\frac{1}{n!} = e\\] |',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Table structure edge cases
  // ---------------------------------------------------------------------------
  group('table structure edge cases', () {
    testWidgets('table with no alignment row (invalid markdown)', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| A | B |\n| \$x\$ | \$y\$ |',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('table with extra pipes at edges', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '|| A || B ||\n| --- | --- |\n|| \$x^2\$ || \$y^2\$ ||',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('table with missing trailing pipe', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| A | B\n| --- | ---\n| \$x\$ | \$y\$',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('single-column table with LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Formula |\n| --- |\n| \$x^2 + y^2 = r^2\$ |\n| \$e^{i\\pi} + 1 = 0\$ |\n| \$a^2 + b^2 = c^2\$ |',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(3));
    });

    testWidgets('wide table with many columns and LaTeX', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| A | B | C | D | E | F |\n| --- | --- | --- | --- | --- | --- |\n| \$x_1\$ | \$x_2\$ | \$x_3\$ | \$x_4\$ | \$x_5\$ | \$x_6\$ |',
        surfaceSize: const Size(320, 800),
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(6));
    });

    testWidgets('table followed by another table', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| A |\n| --- |\n| \$x^2\$ |\n\n| B |\n| --- |\n| \$y^2\$ |',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(2));
    });

    testWidgets('table inside blockquote', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '> | Formula |\n> | --- |\n> | \$x^2\$ |',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('empty cells mixed with LaTeX cells', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| A | B | C |\n| --- | --- | --- |\n| | \$x^2\$ | |\n| \$y^2\$ | | \$z^2\$ |',
      );
      expect(overflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Realistic model outputs: equations in tables
  // ---------------------------------------------------------------------------
  group('realistic equation tables', () {
    testWidgets('Schrödinger equations comparison table', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '## Quantum Mechanics Equations\n\n'
            '| Equation | Form | Expression |\n'
            '| --- | --- | --- |\n'
            '| Schrödinger (TD) | Time-dependent | \$i\\hbar\\frac{\\partial}{\\partial t}\\Psi = \\hat{H}\\Psi\$ |\n'
            '| Schrödinger (TI) | Time-independent | \$\\hat{H}\\Psi = E\\Psi\$ |\n'
            '| Probability | Density | \$\\rho = |\\Psi|^2\$ |\n'
            '| Normalization | Constraint | \$\\int_{-\\infty}^{\\infty} |\\Psi|^2 dx = 1\$ |\n'
            '| Uncertainty | Heisenberg | \$\\Delta x \\cdot \\Delta p \\geq \\frac{\\hbar}{2}\$ |',
        surfaceSize: const Size(500, 1200),
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsWidgets);
    });

    testWidgets('calculus formulas table', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Rule | Formula |\n'
            '| --- | --- |\n'
            '| Power | \$\\frac{d}{dx}x^n = nx^{n-1}\$ |\n'
            '| Product | \$\\frac{d}{dx}(fg) = f\'g + fg\'\$ |\n'
            '| Chain | \$\\frac{d}{dx}f(g(x)) = f\'(g(x)) \\cdot g\'(x)\$ |\n'
            '| Integration by parts | \$\\int u \\, dv = uv - \\int v \\, du\$ |\n'
            '| Fundamental theorem | \$\\int_a^b f\'(x) \\, dx = f(b) - f(a)\$ |',
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsNWidgets(5));
    });

    testWidgets('distribution table with dense formulas', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Distribution | PDF | Mean | Variance |\n'
            '| --- | --- | --- | --- |\n'
            '| Normal | \$\\frac{1}{\\sigma\\sqrt{2\\pi}}e^{-\\frac{(x-\\mu)^2}{2\\sigma^2}}\$ | \$\\mu\$ | \$\\sigma^2\$ |\n'
            '| Poisson | \$\\frac{\\lambda^k e^{-\\lambda}}{k!}\$ | \$\\lambda\$ | \$\\lambda\$ |\n'
            '| Binomial | \$\\binom{n}{k}p^k(1-p)^{n-k}\$ | \$np\$ | \$np(1-p)\$ |\n'
            '| Exponential | \$\\lambda e^{-\\lambda x}\$ | \$\\frac{1}{\\lambda}\$ | \$\\frac{1}{\\lambda^2}\$ |',
        surfaceSize: const Size(500, 1000),
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsWidgets);
    });

    testWidgets('Maxwell equations in table with integrals', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Law | Differential | Integral |\n'
            '| --- | --- | --- |\n'
            '| Gauss (E) | \$\\nabla \\cdot \\mathbf{E} = \\frac{\\rho}{\\epsilon_0}\$ | \$\\oint \\mathbf{E} \\cdot d\\mathbf{A} = \\frac{Q}{\\epsilon_0}\$ |\n'
            '| Gauss (B) | \$\\nabla \\cdot \\mathbf{B} = 0\$ | \$\\oint \\mathbf{B} \\cdot d\\mathbf{A} = 0\$ |\n'
            '| Faraday | \$\\nabla \\times \\mathbf{E} = -\\frac{\\partial \\mathbf{B}}{\\partial t}\$ | \$\\oint \\mathbf{E} \\cdot d\\mathbf{l} = -\\frac{d\\Phi_B}{dt}\$ |\n'
            '| Ampère | \$\\nabla \\times \\mathbf{B} = \\mu_0\\mathbf{J} + \\mu_0\\epsilon_0\\frac{\\partial \\mathbf{E}}{\\partial t}\$ | \$\\oint \\mathbf{B} \\cdot d\\mathbf{l} = \\mu_0 I + \\mu_0\\epsilon_0\\frac{d\\Phi_E}{dt}\$ |',
        surfaceSize: const Size(600, 1000),
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsWidgets);
    });

    testWidgets('mixed code + LaTeX + table in single response', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '## Euler\'s Formula\n\n'
            'The famous identity:\n\n'
            '\$\$e^{i\\theta} = \\cos\\theta + i\\sin\\theta\$\$\n\n'
            '### Special cases\n\n'
            '| \$\\theta\$ | \$e^{i\\theta}\$ | Value |\n'
            '| --- | --- | --- |\n'
            '| \$0\$ | \$e^{0}\$ | \$1\$ |\n'
            '| \$\\pi/2\$ | \$e^{i\\pi/2}\$ | \$i\$ |\n'
            '| \$\\pi\$ | \$e^{i\\pi}\$ | \$-1\$ |\n'
            '| \$2\\pi\$ | \$e^{2\\pi i}\$ | \$1\$ |\n\n'
            '### Python verification\n\n'
            '```python\nimport cmath\nfor theta in [0, cmath.pi/2, cmath.pi, 2*cmath.pi]:\n    print(f"e^(i*{theta:.2f}) = {cmath.exp(1j*theta):.4f}")\n```\n\n'
            'This confirms that \$e^{i\\pi} + 1 = 0\$ (Euler\'s identity).',
        surfaceSize: const Size(500, 2000),
      );
      expect(overflowErrors(errors), isEmpty);
      expect(find.byType(Math), findsWidgets);
    });
  });

  // ---------------------------------------------------------------------------
  // Table with <br> and LaTeX combined
  // ---------------------------------------------------------------------------
  group('table cells with <br> and LaTeX', () {
    testWidgets('LaTeX formula + br + text in cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Info |\n| --- |\n| \$x^2 + y^2 = r^2\$<br>Circle equation |',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('text + br + LaTeX + br + text in cell', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Detail |\n| --- |\n| Given:<br>\$a = 3, b = 4\$<br>Then \$c = 5\$ |',
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('multiple LaTeX with br in cell containing pipes', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Properties |\n| --- |\n| \$|\\Psi|^2\$ is positive<br>\$\\int |\\Psi|^2 dx = 1\$<br>normalization |',
        surfaceSize: const Size(500, 800),
      );
      expect(nonOverflowErrors(errors), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Narrow viewport stress tests
  // ---------------------------------------------------------------------------
  group('narrow viewport table rendering', () {
    testWidgets('3-column table on 280px wide screen', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Name | Formula | Value |\n| --- | --- | --- |\n| Pi | \$\\pi\$ | 3.14159 |\n| e | \$e\$ | 2.71828 |',
        surfaceSize: const Size(280, 800),
      );
      expect(overflowErrors(errors), isEmpty);
    });

    testWidgets('table with long equation on 250px screen — no crash', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Formula |\n| --- |\n| \$\\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}\$ |',
        surfaceSize: const Size(250, 800),
      );
      // Overflow is acceptable on extremely narrow screens; we only assert no crash.
      expect(nonOverflowErrors(errors), isEmpty);
    });

    testWidgets('4-column table with LaTeX on 300px screen', (tester) async {
      final errors = await pumpBubbleAndCollectErrors(
        tester,
        '| Dist | PDF | \$\\mu\$ | \$\\sigma^2\$ |\n'
            '| --- | --- | --- | --- |\n'
            '| Normal | \$\\frac{1}{\\sqrt{2\\pi}\\sigma}e^{-\\frac{(x-\\mu)^2}{2\\sigma^2}}\$ | \$\\mu\$ | \$\\sigma^2\$ |',
        surfaceSize: const Size(300, 800),
      );
      expect(overflowErrors(errors), isEmpty);
    });
  });
}
