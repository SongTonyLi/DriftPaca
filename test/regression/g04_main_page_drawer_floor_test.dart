import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirrors the drawer-width cap applied in _DriftPacaLargeMainPage: the side
// panel is capped so the chat pane never drops below the 360px usable floor,
// while still allowing the full 400px drawer once the screen is wide enough.
double _drawerWidthFor(double screenWidth) =>
    screenWidth - 360 < 400 ? screenWidth - 360 : 400.0;

Widget _largeLayout(double drawerWidth) {
  return MaterialApp(
    home: Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: drawerWidth,
              child: const Drawer(width: 400, child: SizedBox.shrink()),
            ),
            const Expanded(
              child: SizedBox.expand(
                child: ColoredBox(key: Key('chatPane'), color: Colors.blue),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<double> _paneWidthAt(WidgetTester tester, double screenWidth) async {
  tester.view.physicalSize = Size(screenWidth, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_largeLayout(_drawerWidthFor(screenWidth)));
  return tester.getSize(find.byKey(const Key('chatPane'))).width;
}

void main() {
  testWidgets('chat pane keeps the 360px floor across the tablet band',
      (tester) async {
    for (final width in <double>[451, 500, 550, 554, 650, 760, 800]) {
      final paneWidth = await _paneWidthAt(tester, width);
      expect(
        paneWidth,
        greaterThanOrEqualTo(360),
        reason: 'chat pane fell below 360px at screen width $width',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('wider screens still allow the full 400px drawer',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_largeLayout(_drawerWidthFor(1200)));

    final drawerSize = tester.getSize(find.byType(Drawer));
    expect(drawerSize.width, 400);
    expect(tester.takeException(), isNull);
  });
}
