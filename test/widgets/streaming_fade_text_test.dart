import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_think_block.dart';
import 'package:llamaseek/Widgets/streaming_fade_text.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _reducedMotionHost(Widget child) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: child),
      ),
    );

Finder _lastLineFade() => find.byKey(const ValueKey('streaming-last-line-fade'));

String _streamedAnswer(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final element in find
      .descendant(
        of: find.byType(StreamingFadeText),
        matching: find.byType(RichText),
      )
      .evaluate()) {
    buffer.write((element.widget as RichText).text.toPlainText());
  }
  return buffer.toString();
}

Finder _favicon() => find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_LinkFavicon',
    );

class _StreamHost extends StatefulWidget {
  const _StreamHost({
    super.key,
    required this.initial,
  });

  final String initial;

  @override
  State<_StreamHost> createState() => _StreamHostState();
}

class _StreamHostState extends State<_StreamHost> {
  late String text = widget.initial;
  bool isStreaming = true;
  final fadeKey = GlobalKey<StreamingFadeTextState>();

  void setText(String value) => setState(() => text = value);

  void setStreaming(bool value) => setState(() => isStreaming = value);

  double get lineFadeOpacity => fadeKey.currentState!.lineFadeOpacity;

  @override
  Widget build(BuildContext context) {
    return StreamingFadeText(
      key: fadeKey,
      text: text,
      isStreaming: isStreaming,
      child: Text(text),
    );
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('history (isStreaming: false) renders the child with no ticker',
      (tester) async {
    await tester.pumpWidget(_host(
      const StreamingFadeText(
        text: 'A finished answer.',
        isStreaming: false,
        child: Text('A finished answer.'),
      ),
    ));
    await tester.pump();

    expect(find.text('A finished answer.'), findsOneWidget);
    expect(_lastLineFade(), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('text present at creation is settled and does not fade',
      (tester) async {
    await tester.pumpWidget(_host(
      const StreamingFadeText(
        text: 'Hello there, first batch.',
        isStreaming: true,
        child: Text('Hello there, first batch.'),
      ),
    ));
    await tester.pump();

    expect(_lastLineFade(), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('same-line appends do not restart a last-line fade', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(_StreamHost(key: key, initial: 'Hello')));
    await tester.pump();

    key.currentState!.setText('Hello world');
    await tester.pump();

    expect(_lastLineFade(), findsNothing);
    expect(key.currentState!.lineFadeOpacity, 1.0);
  });

  testWidgets('a new line fades in from 0 over 400ms then settles', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(_StreamHost(key: key, initial: 'Hello')));
    await tester.pump();

    key.currentState!.setText('Hello\nworld');
    await tester.pump();

    expect(_lastLineFade(), findsOneWidget);
    expect(key.currentState!.lineFadeOpacity, 0.0);

    await tester.pump();
    expect(key.currentState!.lineFadeOpacity, lessThan(1.0));

    await tester.pump(const Duration(milliseconds: 450));
    expect(key.currentState!.lineFadeOpacity, 1.0);
    expect(_lastLineFade(), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('content after a trailing newline starts a last-line fade',
      (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(_StreamHost(key: key, initial: 'Hello\n')));
    await tester.pump();

    key.currentState!.setText('Hello\nworld');
    await tester.pump();

    expect(_lastLineFade(), findsOneWidget);
    expect(key.currentState!.lineFadeOpacity, 0.0);
  });

  testWidgets('same-line tokens keep the in-progress line fade', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(_StreamHost(key: key, initial: 'Hello')));
    await tester.pump();

    key.currentState!.setText('Hello\nwo');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final mid = key.currentState!.lineFadeOpacity;
    expect(mid, greaterThan(0.0));
    expect(mid, lessThan(1.0));

    key.currentState!.setText('Hello\nworld');
    await tester.pump();

    expect(_lastLineFade(), findsOneWidget);
    expect(key.currentState!.lineFadeOpacity, closeTo(mid, 0.0001));
  });

  testWidgets('a later newline restarts the line fade from 0', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(_StreamHost(key: key, initial: 'Hello')));
    await tester.pump();

    key.currentState!.setText('Hello\nworld');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(key.currentState!.lineFadeOpacity, greaterThan(0.0));

    key.currentState!.setText('Hello\nworld\nnext');
    await tester.pump();

    expect(_lastLineFade(), findsOneWidget);
    expect(key.currentState!.lineFadeOpacity, 0.0);
  });

  testWidgets('reduced motion appends at full opacity with no controller',
      (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_reducedMotionHost(
      _StreamHost(key: key, initial: 'Hello'),
    ));
    await tester.pump();

    key.currentState!.setText('Hello\nworld');
    await tester.pump();

    expect(_lastLineFade(), findsNothing);
    expect(key.currentState!.lineFadeOpacity, 1.0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('isStreaming false mid-stream drops the line fade', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(_StreamHost(key: key, initial: 'Hello')));
    await tester.pump();
    key.currentState!.setText('Hello\nworld');
    await tester.pump();
    expect(_lastLineFade(), findsOneWidget);

    key.currentState!.setStreaming(false);
    await tester.pump();

    expect(_lastLineFade(), findsNothing);
    expect(key.currentState!.lineFadeOpacity, 1.0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('truncated text does not throw or keep a stale fade', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(
      _StreamHost(key: key, initial: 'A long first draft.'),
    ));
    await tester.pump();
    key.currentState!.setText('Short.');
    await tester.pump();

    expect(find.text('Short.'), findsOneWidget);
    expect(_lastLineFade(), findsNothing);
    expect(key.currentState!.lineFadeOpacity, 1.0);
  });

  testWidgets('curve is easeOut over the default duration', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(_StreamHost(key: key, initial: 'Hello')));
    await tester.pump();
    key.currentState!.setText('Hello\nworld');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(key.currentState!.lineFadeOpacity, greaterThan(0.5));
    expect(key.currentState!.lineFadeOpacity, lessThan(1.0));
  });

  testWidgets('enabling motion after reduced-motion appends does not re-fade',
      (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_reducedMotionHost(
      _StreamHost(key: key, initial: 'Hello'),
    ));
    await tester.pump();
    key.currentState!.setText('Hello\nworld');
    await tester.pump();
    expect(_lastLineFade(), findsNothing);

    await tester.pumpWidget(_host(_StreamHost(key: key, initial: 'Hello\nworld')));
    await tester.pump();

    expect(_lastLineFade(), findsNothing);
    expect(key.currentState!.lineFadeOpacity, 1.0);
  });

  testWidgets('ChatBubble streams markdown so citations render as favicons',
      (tester) async {
    final message = OllamaMessage(
      '必备材料之一[²](https://isso.columbia.edu/content/f1-opt).',
      role: OllamaMessageRole.assistant,
    );

    await tester.pumpWidget(_host(
      ChatBubble(message: message, isStreaming: true),
    ));
    await tester.pump();

    expect(find.byType(StreamingFadeText), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.textContaining('](https://'), findsNothing);
    expect(find.textContaining('isso.columbia.edu'), findsNothing);
    expect(_favicon(), findsOneWidget);

    await tester.pumpWidget(_host(const SizedBox.shrink()));
  });

  testWidgets('ChatBubble keeps markdown while live and drops the fade helper after',
      (tester) async {
    final message = OllamaMessage(
      'Hello',
      role: OllamaMessageRole.assistant,
    );

    await tester.pumpWidget(_host(
      ChatBubble(message: message, isStreaming: true),
    ));
    await tester.pump();
    expect(find.byType(StreamingFadeText), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);

    message.content = 'Hello from the model.';
    await tester.pumpWidget(_host(
      ChatBubble(message: message, isStreaming: true),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect(find.byType(StreamingFadeText), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);

    await tester.pumpWidget(_host(
      ChatBubble(message: message, isStreaming: false),
    ));
    await tester.pump();
    expect(find.byType(StreamingFadeText), findsNothing);
    expect(find.byType(MarkdownBody), findsOneWidget);

    await tester.pumpWidget(_host(const SizedBox.shrink()));
  });

  testWidgets('live streaming does not dump a long backlog within a second',
      (tester) async {
    final message = OllamaMessage(
      'Hi',
      role: OllamaMessageRole.assistant,
    );
    await tester.pumpWidget(_host(
      ChatBubble(message: message, isStreaming: true),
    ));
    await tester.pump();

    const tail = ' word';
    message.content = 'Hi${tail * 80}';
    await tester.pumpWidget(_host(
      ChatBubble(message: message, isStreaming: true),
    ));

    // Old catch-up drained ~the whole backlog in 90 frames (~1.5 s), which
    // made the fade a last-word blink. Live reveal must stay well behind.
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final shown = _streamedAnswer(tester);
    expect(shown.startsWith('Hi'), isTrue);
    expect(shown.length, lessThan(message.content.length ~/ 2),
        reason: 'a fast model dump must still type out slowly enough to fade');

    await tester.pumpWidget(_host(const SizedBox.shrink()));
  });

  testWidgets('ThinkBlockWidget fades a newly started thinking line',
      (tester) async {
    await tester.pumpWidget(_host(
      const ThinkBlockWidget(
        content: 'Hmm',
        isComplete: false,
        isStreaming: true,
      ),
    ));
    await tester.pump();
    expect(find.byType(StreamingFadeText), findsOneWidget);

    await tester.pumpWidget(_host(
      const ThinkBlockWidget(
        content: 'Hmm\nmaybe forty two after all of that',
        isComplete: false,
        isStreaming: true,
      ),
    ));
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(_lastLineFade(), findsOneWidget);

    await tester.pumpWidget(_host(const SizedBox.shrink()));
  });
}
