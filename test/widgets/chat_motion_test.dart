import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/streaming_llama.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_welcome.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/welcome_scaffold.dart';

Widget reducedMotionHost(Widget child) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('server welcome settles directly on its actionable state',
      (tester) async {
    await tester.pumpWidget(
      reducedMotionHost(
        const ChatWelcome(
          showingState: CrossFadeState.showFirst,
          secondChildScale: 0.0,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Tap to configure a server address'), findsOneWidget);
    expect(find.text('Welcome to DriftPaca!'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('welcome scaffold skips its decorative entrance',
      (tester) async {
    await tester.pumpWidget(
      reducedMotionHost(
        WelcomeScaffold(
          eyebrow: 'WELCOME',
          title: 'Start a conversation',
          ctaLabel: 'Start',
          accent: Colors.blue,
          onCta: () {},
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<Opacity>(find.byType(Opacity).first).opacity,
      1.0,
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
      'streaming answer shows newly arrived text immediately with reduced motion',
      (tester) async {
    final message = OllamaMessage(
      'A',
      role: OllamaMessageRole.assistant,
    );

    await tester.pumpWidget(
      reducedMotionHost(ChatBubble(message: message, isStreaming: true)),
    );
    await tester.pump();
    message.content = 'A complete current token batch.';
    await tester.pumpWidget(
      reducedMotionHost(ChatBubble(message: message, isStreaming: true)),
    );
    await tester.pump();

    expect(
      find.textContaining(
        'complete current token batch',
        findRichText: true,
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(reducedMotionHost(const SizedBox.shrink()));
  });

  testWidgets('new user bubble begins entering on the next frame',
      (tester) async {
    final message = OllamaMessage(
      'New prompt',
      role: OllamaMessageRole.user,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatBubble(message: message, animate: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final entrance = tester.widget<FadeTransition>(
      find.byType(FadeTransition).first,
    );
    expect(entrance.opacity.value, greaterThan(0.0));
  });

  testWidgets('running llama is static with reduced motion', (tester) async {
    await tester.pumpWidget(
      reducedMotionHost(const StreamingLlama(isRunning: true)),
    );
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
