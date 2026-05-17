import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart';

Widget buildTestApp(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  List<FlutterErrorDetails> overflowErrors(Iterable<FlutterErrorDetails> errors) {
    return errors.where((details) => details.exceptionAsString().contains('overflowed by')).toList(growable: false);
  }

  Future<List<FlutterErrorDetails>> pumpBubbleAndCollectErrors(
    WidgetTester tester,
    String content, {
    Size surfaceSize = const Size(360, 800),
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

      await tester.pumpWidget(buildTestApp(ChatBubble(message: message)));
      await tester.pumpAndSettle();
      return errors;
    } finally {
      FlutterError.onError = originalOnError;
    }
  }

  testWidgets('shows raw inline latex when math parsing fails', (tester) async {
    final message = OllamaMessage(
      r'Broken formula: $\frac{1}{2$',
      role: OllamaMessageRole.assistant,
    );

    await tester.pumpWidget(buildTestApp(ChatBubble(message: message)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Parser Error'), findsNothing);
    expect(find.textContaining(r'$\frac{1}{2$'), findsOneWidget);
  });

  testWidgets('renders single-dollar inline latex before a closing bracket', (tester) async {
    final message = OllamaMessage(
      r'Inline math ($x^2 + y^2$) should render.',
      role: OllamaMessageRole.assistant,
    );

    await tester.pumpWidget(buildTestApp(ChatBubble(message: message)));
    await tester.pumpAndSettle();

    expect(find.textContaining(r'$x^2 + y^2$'), findsNothing);
    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('renders single-dollar inline latex with inner whitespace', (tester) async {
    final message = OllamaMessage(
      r'Inline math like $ D $ and $ \pm $ should render.',
      role: OllamaMessageRole.assistant,
    );

    await tester.pumpWidget(buildTestApp(ChatBubble(message: message)));
    await tester.pumpAndSettle();

    expect(find.textContaining(r'$ D $'), findsNothing);
    expect(find.textContaining(r'$ \pm $'), findsNothing);
    expect(find.byType(Math), findsNWidgets(2));
  });

  testWidgets('does not overflow inline latex inside markdown tables', (tester) async {
    final errors = await pumpBubbleAndCollectErrors(
      tester,
      r'''
| Label | Value |
| --- | --- |
| Long inline math | $x_1 + x_2 + x_3 + x_4 + x_5 + x_6 + x_7 + x_8 + x_9 + x_{10} = \frac{a+b+c+d+e+f+g+h+i+j}{k}$ |
''',
    );

    expect(overflowErrors(errors), isEmpty);
  });

  testWidgets('does not overflow display latex inside markdown tables', (tester) async {
    final errors = await pumpBubbleAndCollectErrors(
      tester,
      r'''
| Formula |
| --- |
| $$\sum_{i=1}^{10} x_i = \frac{a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p}{q}$$ |
''',
    );

    expect(overflowErrors(errors), isEmpty);
  });
}
