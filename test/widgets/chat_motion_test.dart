import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/streaming_llama.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_welcome.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/welcome_scaffold.dart';
import 'package:llamaseek/Utils/favicon_cache.dart';

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

  testWidgets('assistant actions skip size animation with reduced motion',
      (tester) async {
    final message = OllamaMessage(
      'Completed answer',
      role: OllamaMessageRole.assistant,
    );

    await tester.pumpWidget(
      reducedMotionHost(ChatBubble(message: message)),
    );

    final animatedSize = tester.widget<AnimatedSize>(
      find.byType(AnimatedSize),
    );
    expect(animatedSize.duration, Duration.zero);
  });

  testWidgets('copy feedback skips switch animation with reduced motion',
      (tester) async {
    final message = OllamaMessage(
      'Copy this prompt',
      role: OllamaMessageRole.user,
    );

    await tester.pumpWidget(
      reducedMotionHost(ChatBubble(message: message)),
    );

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, Duration.zero);
  });

  testWidgets('link favicon pop is settled with reduced motion',
      (tester) async {
    FaviconCache.instance.clearForTest();
    final message = OllamaMessage(
      '[Example](https://reduced-motion.invalid)',
      role: OllamaMessageRole.assistant,
    );

    await tester.pumpWidget(
      reducedMotionHost(ChatBubble(message: message)),
    );

    final fade = tester.widget<FadeTransition>(
      find.byKey(const ValueKey('link-favicon-fade')),
    );
    expect(fade.opacity.value, 1.0);

    await tester.pumpWidget(reducedMotionHost(const SizedBox.shrink()));
    FaviconCache.instance.clearForTest();
  });
}
