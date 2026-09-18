import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:llamaseek/Widgets/token_reveal_text.dart';

/// The plain-text typewriter used for streamed reasoning. What matters here
/// is that history never animates (a block built from a saved message shows
/// its text on the first frame), that text appended to a live block arrives
/// progressively rather than as a jump, and that neither of those spends a
/// frame rendering half of an emoji.

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _reducedMotionHost(Widget child) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: child),
      ),
    );

Finder _fadeFinder() => find.descendant(
      of: find.byType(TokenRevealText),
      matching: find.byType(FadeTransition),
    );

String _shown(WidgetTester tester) {
  final text = tester.widget<Text>(
    find.descendant(
      of: find.byType(TokenRevealText),
      matching: find.byWidgetPredicate(
        (widget) => widget is Text && widget.textSpan != null,
      ),
    ),
  );
  final root = text.textSpan as TextSpan;
  final children = root.children ??
      (root.text == null ? const <InlineSpan>[] : <InlineSpan>[root]);
  final fadeTexts = tester
      .widgetList<Text>(find.descendant(
        of: _fadeFinder(),
        matching: find.byType(Text),
      ))
      .toList();
  var fadeIndex = 0;
  final buffer = StringBuffer();
  for (final span in children) {
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

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('text present at creation shows in full on the first frame',
      (tester) async {
    // A reloaded message's reasoning is history, not a stream: typing it out
    // again would be a lie about when it happened.
    await tester.pumpWidget(_host(
      const TokenRevealText('Reasoning from a saved message.'),
    ));

    expect(_shown(tester), 'Reasoning from a saved message.');
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('appended thinking fades in while revealing', (tester) async {
    await tester.pumpWidget(_host(const TokenRevealText('Hmm')));
    await tester.pumpWidget(
      _host(const TokenRevealText('Hmm, maybe forty two after all')),
    );
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(_fadeFinder(), findsWidgets);
  });

  testWidgets('live thinking does not dump a long backlog within a second',
      (tester) async {
    const head = 'Hi';
    const tail = ' word';
    final full = '$head${tail * 80}';

    await tester.pumpWidget(_host(const TokenRevealText(head)));
    await tester.pumpWidget(_host(TokenRevealText(full)));

    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final shown = _shown(tester);
    expect(shown.startsWith(head), isTrue);
    expect(shown.length, lessThan(full.length ~/ 2),
        reason: 'fast thinking dumps must still type out slowly enough to fade');
  });

  testWidgets('appended text is revealed over several frames', (tester) async {
    const head = 'First.';
    final tail = ' ${'word ' * 40}';

    await tester.pumpWidget(_host(const TokenRevealText(head)));
    expect(_shown(tester), head);

    await tester.pumpWidget(_host(TokenRevealText(head + tail)));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final partial = _shown(tester);
    expect(partial.length, greaterThan(head.length));
    expect(partial.length, lessThan((head + tail).length));
    expect((head + tail).startsWith(partial), isTrue);

    // Base pace is 0.7 chars/frame; give the ~200-char tail time to finish,
    // then let the last fade controller settle.
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_shown(tester), head + tail);
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('never renders an orphaned high surrogate mid-reveal',
      (tester) async {
    // Astral-plane emoji are two UTF-16 code units; a cursor that lands
    // between them renders a tofu box for a frame.
    const head = 'x';
    final tail = '😀' * 60;

    await tester.pumpWidget(_host(const TokenRevealText(head)));
    await tester.pumpWidget(_host(TokenRevealText(head + tail)));

    for (var i = 0; i < 250; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final shown = _shown(tester);
      if (shown.isEmpty) continue;
      final last = shown.codeUnitAt(shown.length - 1);
      expect(last >= 0xD800 && last <= 0xDBFF, isFalse,
          reason: 'frame $i ended on an unpaired high surrogate');
    }
    expect(_shown(tester), head + tail);
  });

  testWidgets('revealing: false shows appended text at once with no ticker',
      (tester) async {
    await tester.pumpWidget(
        _host(const TokenRevealText('Done.', revealing: false)));
    await tester.pumpWidget(_host(
        const TokenRevealText('Done. And the rest of it.', revealing: false)));
    await tester.pump();

    expect(_shown(tester), 'Done. And the rest of it.');
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('a block that completes mid-reveal snaps to its full text',
      (tester) async {
    const head = 'First.';
    final tail = ' ${'word ' * 40}';

    await tester.pumpWidget(_host(const TokenRevealText(head)));
    await tester.pumpWidget(_host(TokenRevealText(head + tail)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_shown(tester).length, lessThan((head + tail).length));

    // The turn ended: the segment is closed while the tail is still typing.
    await tester
        .pumpWidget(_host(TokenRevealText(head + tail, revealing: false)));
    await tester.pump();

    expect(_shown(tester), head + tail);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('reduced motion reveals appended text on the next frame',
      (tester) async {
    await tester.pumpWidget(_reducedMotionHost(const TokenRevealText('First.')));
    await tester.pumpWidget(
        _reducedMotionHost(TokenRevealText('First.${'word ' * 40}')));
    await tester.pump();

    expect(_shown(tester), 'First.${'word ' * 40}');
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('text that shrinks is not left with a stale cursor',
      (tester) async {
    // The bubble clears a rejected draft by handing the same widget a
    // shorter string; substring on a stale cursor would throw.
    await tester.pumpWidget(_host(const TokenRevealText('A long first draft.')));
    await tester.pumpWidget(_host(const TokenRevealText('Short.')));
    await tester.pump(const Duration(milliseconds: 16));

    expect(_shown(tester), 'Short.');
  });
}
