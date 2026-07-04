import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirrors the drawer-width cap applied in _DriftPacaLargeMainPage: the side
// panel is capped at min(400, 35% of screen width) so the chat pane keeps a
// usable width on mid-sized screens.
double _drawerWidthFor(double screenWidth) =>
    screenWidth * 0.35 < 400 ? screenWidth * 0.35 : 400.0;

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

void main() {
  testWidgets('drawer cap leaves the chat pane usable on a narrow tablet',
      (tester) async {
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final drawerWidth = _drawerWidthFor(500);
    await tester.pumpWidget(_largeLayout(drawerWidth));

    final drawerSize = tester.getSize(find.byType(Drawer));
    final paneSize = tester.getSize(find.byKey(const Key('chatPane')));

    // The Drawer honours the outer cap instead of its intrinsic 400px.
    expect(drawerSize.width, lessThan(400));
    expect(drawerSize.width, closeTo(175, 0.5));
    // The chat pane keeps the remaining width; it is far from the sub-200px
    // sliver produced by an uncapped 400px drawer.
    expect(paneSize.width, greaterThan(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wider screens still allow the full 400px drawer',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final drawerWidth = _drawerWidthFor(1200);
    await tester.pumpWidget(_largeLayout(drawerWidth));

    final drawerSize = tester.getSize(find.byType(Drawer));
    expect(drawerSize.width, 400);
    expect(tester.takeException(), isNull);
  });
}
