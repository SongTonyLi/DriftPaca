import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:llamaseek/Models/research_phase.dart';
import 'package:llamaseek/Widgets/pulsing_icon.dart';
import 'package:llamaseek/Widgets/research_activity_strip.dart';

/// The strip that says what the research loop is doing right now.
///
/// It holds a repeating controller and a 250 ms timer, so nothing here ever
/// settles: every test advances the clock with explicit `pump(Duration)`
/// calls instead of `pumpAndSettle`, and unmounts the strip before it ends.

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _reducedMotionHost(Widget child) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: child),
      ),
    );

/// Drops the strip and lets its timer be cancelled, so the test does not end
/// with the periodic timer still pending.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(_host(const SizedBox.shrink()));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('names every phase a run can be in', (tester) async {
    for (final phase in ResearchPhase.values) {
      await tester.pumpWidget(_host(ResearchActivityStrip(phase: phase)));
      // Past the label cross-fade, so the previous phase's label is gone.
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text(phase.label), findsOneWidget,
          reason: 'no label for $phase');
    }
    await _unmount(tester);
  });

  testWidgets('a phase change cross-fades one label into the next',
      (tester) async {
    await tester.pumpWidget(_host(
        const ResearchActivityStrip(phase: ResearchPhase.searching)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Searching'), findsOneWidget);

    await tester.pumpWidget(
        _host(const ResearchActivityStrip(phase: ResearchPhase.reading)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Mid-transition both labels are on screen: the phase changes by
    // dissolving, not by cutting.
    expect(find.text('Searching'), findsOneWidget);
    expect(find.text('Reading sources'), findsOneWidget);
    expect(find.byType(FadeTransition), findsWidgets);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Searching'), findsNothing);
    expect(find.text('Reading sources'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('counts the seconds spent in the phase, starting at one second',
      (tester) async {
    await tester.pumpWidget(_host(ResearchActivityStrip(
      phase: ResearchPhase.searching,
      startedAt: DateTime.now(),
    )));
    await tester.pump();

    // Under a second there is no number: a counter that flickers 0s onto the
    // screen for every fast phase is noise.
    expect(find.text('0s'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('1s'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('2s'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('the counter restarts when the phase does', (tester) async {
    final started = DateTime.now();
    await tester.pumpWidget(_host(ResearchActivityStrip(
      phase: ResearchPhase.searching,
      startedAt: started,
    )));
    await tester.pump(const Duration(milliseconds: 2100));
    expect(find.text('2s'), findsOneWidget);

    await tester.pumpWidget(_host(ResearchActivityStrip(
      phase: ResearchPhase.reading,
      startedAt: started.add(const Duration(seconds: 2)),
    )));
    await tester.pump(const Duration(milliseconds: 300));

    // Time in the new phase, not time in the run.
    expect(find.text('2s'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('1s'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('model-call phases pulse; a phase waiting on a person does not',
      (tester) async {
    for (final phase in [
      ResearchPhase.thinking,
      ResearchPhase.reading,
      ResearchPhase.checkingCoverage,
    ]) {
      await tester.pumpWidget(_host(ResearchActivityStrip(phase: phase)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PulsingIcon), findsOneWidget, reason: '$phase');
    }

    await tester.pumpWidget(_host(const ResearchActivityStrip(
        phase: ResearchPhase.awaitingClarification)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PulsingIcon), findsNothing);

    await _unmount(tester);
  });

  testWidgets('is a live region so a screen reader is told the phase changed',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(ResearchActivityStrip(
      phase: ResearchPhase.checkingCoverage,
      startedAt: DateTime.now(),
    )));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.getSemantics(find.byType(ResearchActivityStrip)),
      matchesSemantics(
        label: 'Checking the answer against the goal',
        isLiveRegion: true,
      ),
    );

    handle.dispose();
    await _unmount(tester);
  });

  testWidgets('reduced motion leaves nothing running', (tester) async {
    await tester.pumpWidget(_reducedMotionHost(
        const ResearchActivityStrip(phase: ResearchPhase.searching)));
    await tester.pump(const Duration(milliseconds: 300));

    // No repeating glyph controller, and no cross-fade pending.
    expect(tester.binding.transientCallbackCount, 0);
    expect(find.text('Searching'), findsOneWidget);

    await tester.pumpWidget(_reducedMotionHost(
        const ResearchActivityStrip(phase: ResearchPhase.drafting)));
    await tester.pump();

    // The label swaps on the next frame instead of dissolving.
    expect(find.text('Searching'), findsNothing);
    expect(find.text('Writing the answer'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(_reducedMotionHost(
        const ResearchActivityStrip(phase: ResearchPhase.thinking)));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);

    await tester.pumpWidget(_reducedMotionHost(const SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the second counter stops when the strip goes away',
      (tester) async {
    // A run that ends leaves no timer behind — flutter_test fails the test
    // if one is still pending once the tree is gone.
    await tester.pumpWidget(_host(ResearchActivityStrip(
      phase: ResearchPhase.drafting,
      startedAt: DateTime.now(),
    )));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('1s'), findsOneWidget);

    await tester.pumpWidget(_host(const SizedBox.shrink()));
    await tester.pump(const Duration(seconds: 5));

    expect(find.byType(ResearchActivityStrip), findsNothing);
  });
}
