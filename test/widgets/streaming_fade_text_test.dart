import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/streaming_fade_text.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _reducedMotionHost(Widget child) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: child),
      ),
    );

TextSpan _rootSpan(WidgetTester tester) {
  final text = tester.widget<Text>(
    find.descendant(
      of: find.byType(StreamingFadeText),
      matching: find.byWidgetPredicate(
        (widget) => widget is Text && widget.textSpan != null,
      ),
    ),
  );
  return text.textSpan as TextSpan;
}

List<InlineSpan> _rootChildren(WidgetTester tester) {
  final root = _rootSpan(tester);
  return root.children ?? (root.text == null ? const <InlineSpan>[] : <InlineSpan>[root]);
}

int _widgetSpanCount(WidgetTester tester) => _rootChildren(tester).whereType<WidgetSpan>().length;

int _textSpanCount(WidgetTester tester) => _rootChildren(tester).whereType<TextSpan>().length;

Finder _fadeFinder() => find.descendant(
      of: find.byType(StreamingFadeText),
      matching: find.byType(FadeTransition),
    );

String _plain(WidgetTester tester) {
  final fadeTexts = tester
      .widgetList<Text>(find.descendant(
        of: _fadeFinder(),
        matching: find.byType(Text),
      ))
      .toList();
  var fadeIndex = 0;
  final buffer = StringBuffer();
  for (final span in _rootChildren(tester)) {
    if (span is TextSpan) {
      buffer.write(span.text ?? '');
    } else if (span is WidgetSpan) {
      if (span.child is SizedBox) {
        buffer.write('\n');
      } else {
        buffer.write(fadeTexts[fadeIndex++].data ?? '');
      }
    }
  }
  return buffer.toString();
}

class _StreamHost extends StatefulWidget {
  const _StreamHost({
    super.key,
    required this.initial,
    this.style,
  });

  final String initial;
  final TextStyle? style;

  @override
  State<_StreamHost> createState() => _StreamHostState();
}

class _StreamHostState extends State<_StreamHost> {
  late String text = widget.initial;
  bool isStreaming = true;

  void setText(String value) => setState(() => text = value);

  void setStreaming(bool value) => setState(() => isStreaming = value);

  /// Two assignments in one event so Flutter coalesces them into a single
  /// rebuild — the same-frame merge the fade widget has to perform.
  void setTextTwice(String first, String second) {
    setState(() => text = first);
    setState(() => text = second);
  }

  @override
  Widget build(BuildContext context) {
    return StreamingFadeText(
      text: text,
      isStreaming: isStreaming,
      style: widget.style,
    );
  }
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('history (isStreaming: false) is one plain TextSpan with no ticker', (tester) async {
    await tester.pumpWidget(_host(
      const StreamingFadeText(
        text: 'A finished answer.',
        isStreaming: false,
      ),
    ));
    await tester.pump();

    expect(_plain(tester), 'A finished answer.');
    expect(_widgetSpanCount(tester), 0);
    expect(_fadeFinder(), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('text present at creation is settled and does not fade', (tester) async {
    await tester.pumpWidget(_host(
      const StreamingFadeText(
        text: 'Hello there, first batch.',
        isStreaming: true,
      ),
    ));
    await tester.pump();

    expect(_plain(tester), 'Hello there, first batch.');
    expect(_fadeFinder(), findsNothing);
    expect(_widgetSpanCount(tester), 0);
  });

  testWidgets('appended stream text fades in from 0 over 400ms then settles', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(
      _StreamHost(key: key, initial: 'Hello'),
    ));
    await tester.pump();

    key.currentState!.setText('Hello world');
    await tester.pump();
    await tester.pump();

    expect(_plain(tester), 'Hello world');
    expect(_fadeFinder(), findsOneWidget);
    expect(_widgetSpanCount(tester), 1);
    expect(_textSpanCount(tester), 1);

    final fade = tester.widget<FadeTransition>(_fadeFinder());
    expect(fade.opacity.value, lessThan(1.0));

    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();

    expect(_fadeFinder(), findsNothing);
    expect(_widgetSpanCount(tester), 0);
    expect(_plain(tester), 'Hello world');
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('settled chunks are never re-animated when a later chunk arrives', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(
      _StreamHost(key: key, initial: 'One'),
    ));
    await tester.pump();

    key.currentState!.setText('One two');
    await tester.pump();
    await tester.pump();
    expect(_fadeFinder(), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(_fadeFinder(), findsNothing);

    key.currentState!.setText('One two three');
    await tester.pump();
    await tester.pump();

    expect(_plain(tester), 'One two three');
    expect(_fadeFinder(), findsOneWidget);
    expect(_widgetSpanCount(tester), 1, reason: 'only the new tail is a WidgetSpan');

    final fadingText = tester
        .widget<Text>(find.descendant(
          of: _fadeFinder(),
          matching: find.byType(Text),
        ))
        .data;
    expect(fadingText, ' three');
  });

  testWidgets('chunks from the same frame merge into one fading span', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(
      _StreamHost(key: key, initial: 'A'),
    ));
    await tester.pump();

    key.currentState!.setTextTwice('AB', 'ABC');
    await tester.pump();
    await tester.pump();

    expect(_plain(tester), 'ABC');
    expect(_widgetSpanCount(tester), 1, reason: 'AB and ABC arrived in one rebuild');
    final fadingText = tester
        .widget<Text>(find.descendant(
          of: _fadeFinder(),
          matching: find.byType(Text),
        ))
        .data;
    expect(fadingText, 'BC');
  });

  testWidgets('chunks from different frames stay separate while both animate', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(
      _StreamHost(key: key, initial: 'A'),
    ));
    await tester.pump();

    key.currentState!.setText('AB');
    await tester.pump();
    await tester.pump();
    expect(_widgetSpanCount(tester), 1);

    key.currentState!.setText('ABC');
    await tester.pump();
    await tester.pump();

    expect(_plain(tester), 'ABC');
    expect(_widgetSpanCount(tester), 2, reason: 'second frame must not mutate the first chunk');
  });

  testWidgets('reduced motion appends at full opacity with no controller', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_reducedMotionHost(
      _StreamHost(key: key, initial: 'Hello'),
    ));
    await tester.pump();

    key.currentState!.setText('Hello world');
    await tester.pump();

    expect(_plain(tester), 'Hello world');
    expect(_fadeFinder(), findsNothing);
    expect(_widgetSpanCount(tester), 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('inline code and fenced code are settled, surrounding prose fades', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(
      _StreamHost(key: key, initial: 'see '),
    ));
    await tester.pump();

    key.currentState!.setText('see `code` plus');
    await tester.pump();
    await tester.pump();

    expect(_plain(tester), 'see `code` plus');
    expect(_fadeFinder(), findsOneWidget);
    final fadingText = tester
        .widget<Text>(find.descendant(
          of: _fadeFinder(),
          matching: find.byType(Text),
        ))
        .data;
    expect(fadingText, ' plus');
    expect(fadingText, isNot(contains('code')));

    key.currentState!.setText('intro\n');
    await tester.pump();
    key.currentState!.setText('intro\n```\nvoid main() {}\n```');
    await tester.pump();
    await tester.pump();

    expect(_plain(tester), 'intro\n```\nvoid main() {}\n```');
    expect(_fadeFinder(), findsNothing);
  });

  testWidgets('animating and settled spans share the same TextStyle', (tester) async {
    const style = TextStyle(
      fontSize: 16,
      height: 1.48,
      fontWeight: FontWeight.w500,
      color: Color(0xFF111111),
    );
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(
      _StreamHost(key: key, initial: 'Hello', style: style),
    ));
    await tester.pump();

    key.currentState!.setText('Hello world');
    await tester.pump();
    await tester.pump();

    final root = _rootSpan(tester);
    final settled = _rootChildren(tester).whereType<TextSpan>().first;
    final innerText = tester.widget<Text>(find.descendant(
      of: _fadeFinder(),
      matching: find.byType(Text),
    ));

    expect(settled.style ?? root.style, style);
    expect(innerText.style, style);
  });

  testWidgets('isStreaming false mid-stream drops live controllers', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(
      _StreamHost(key: key, initial: 'Hello'),
    ));
    await tester.pump();
    key.currentState!.setText('Hello world');
    await tester.pump();
    await tester.pump();
    expect(_fadeFinder(), findsOneWidget);

    key.currentState!.setStreaming(false);
    await tester.pump();

    expect(_plain(tester), 'Hello world');
    expect(_fadeFinder(), findsNothing);
    expect(_widgetSpanCount(tester), 0);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('truncated text does not throw or keep a stale tail', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(
      _StreamHost(key: key, initial: 'A long first draft.'),
    ));
    await tester.pump();
    key.currentState!.setText('Short.');
    await tester.pump();

    expect(_plain(tester), 'Short.');
  });

  testWidgets('ChatBubble reads isStreaming: fade helper only while live', (tester) async {
    final message = OllamaMessage(
      'Hello',
      role: OllamaMessageRole.assistant,
    );

    await tester.pumpWidget(_host(
      ChatBubble(message: message, isStreaming: true),
    ));
    await tester.pump();
    expect(find.byType(StreamingFadeText), findsOneWidget);

    message.content = 'Hello from the model.';
    await tester.pumpWidget(_host(
      ChatBubble(message: message, isStreaming: true),
    ));
    // Typewriter reveals the tail over a few frames; give it time to append
    // at least one fading chunk without waiting out the 400ms settle.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect(find.byType(StreamingFadeText), findsOneWidget);

    await tester.pumpWidget(_host(
      ChatBubble(message: message, isStreaming: false),
    ));
    await tester.pump();
    expect(find.byType(StreamingFadeText), findsNothing);
    expect(find.byType(MarkdownBody), findsOneWidget);

    await tester.pumpWidget(_host(const SizedBox.shrink()));
  });

  testWidgets('curve is easeOut over the default duration', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(
      _StreamHost(key: key, initial: 'Hello'),
    ));
    await tester.pump();
    key.currentState!.setText('Hello world');
    await tester.pump();
    await tester.pump();

    final fade = tester.widget<FadeTransition>(_fadeFinder());
    // At 50% wall time, easeOut is ahead of linear (0.5).
    await tester.pump(const Duration(milliseconds: 200));
    expect(fade.opacity.value, greaterThan(0.5));
    expect(fade.opacity.value, lessThan(1.0));
  });

  testWidgets('unclosed inline code stays settled until prose resumes', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(
      _StreamHost(key: key, initial: 'see '),
    ));
    await tester.pump();

    key.currentState!.setText('see `not closed yet');
    await tester.pump();
    await tester.pump();
    expect(_plain(tester), 'see `not closed yet');
    expect(_fadeFinder(), findsNothing);

    key.currentState!.setText('see `not closed yet` trailing');
    await tester.pump();
    await tester.pump();
    expect(_plain(tester), 'see `not closed yet` trailing');
    expect(_fadeFinder(), findsOneWidget);
    final fadingText = tester
        .widget<Text>(find.descendant(
          of: _fadeFinder(),
          matching: find.byType(Text),
        ))
        .data;
    expect(fadingText, ' trailing');
    expect(fadingText, isNot(contains('not closed')));
  });

  testWidgets('a long catch-up dump only fades the last token', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(
      _StreamHost(key: key, initial: 'A'),
    ));
    await tester.pump();

    const tail = ' one two three four five six seven eight nine ten';
    key.currentState!.setText('A$tail');
    await tester.pump();
    await tester.pump();

    expect(_plain(tester), 'A$tail');
    expect(_widgetSpanCount(tester), 1);
    final fadingText = tester
        .widget<Text>(find.descendant(
          of: _fadeFinder(),
          matching: find.byType(Text),
        ))
        .data;
    expect(fadingText, ' ten');
  });

  testWidgets('a newline stays a line break while the next line fades', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(
      _StreamHost(key: key, initial: 'para'),
    ));
    await tester.pump();

    key.currentState!.setText('para\nnext');
    await tester.pump();
    await tester.pump();

    expect(_plain(tester), 'para\nnext');
    expect(_fadeFinder(), findsOneWidget);
    final fadingText = tester
        .widget<Text>(find.descendant(
          of: _fadeFinder(),
          matching: find.byType(Text),
        ))
        .data;
    expect(fadingText, 'next');
    expect(fadingText, isNot(contains('\n')));
  });

  testWidgets('enabling motion after reduced-motion appends does not re-fade', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_reducedMotionHost(
      _StreamHost(key: key, initial: 'Hello'),
    ));
    await tester.pump();
    key.currentState!.setText('Hello world');
    await tester.pump();
    expect(_fadeFinder(), findsNothing);

    await tester.pumpWidget(_host(
      _StreamHost(key: key, initial: 'Hello world'),
    ));
    await tester.pump();

    expect(_plain(tester), 'Hello world');
    expect(_fadeFinder(), findsNothing);
  });

  testWidgets('emoji appends do not emit an orphaned surrogate', (tester) async {
    final key = GlobalKey<_StreamHostState>();
    await tester.pumpWidget(_host(
      _StreamHost(key: key, initial: 'x'),
    ));
    await tester.pump();
    key.currentState!.setText('x😀y');
    await tester.pump();
    await tester.pump();

    final shown = _plain(tester);
    expect(shown, 'x😀y');
    for (var i = 0; i < shown.length; i++) {
      final unit = shown.codeUnitAt(i);
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        expect(i + 1 < shown.length, isTrue);
        final next = shown.codeUnitAt(i + 1);
        expect(next >= 0xDC00 && next <= 0xDFFF, isTrue);
        i++;
      }
    }
  });
}
