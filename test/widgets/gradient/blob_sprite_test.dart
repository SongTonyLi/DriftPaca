import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Widgets/gradient/blob_sprite.dart';

void main() {
  testWidgets('bakes a square sprite that is opaque at centre, transparent at edge',
      (tester) async {
    await tester.runAsync(() async {
      const size = 64;
      final img = bakeBlobSprite(size: size);
      addTearDown(img.dispose);

      expect(img.width, size);
      expect(img.height, size);

      final bytes =
          (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final px = bytes.buffer.asUint8List();
      int alphaAt(int x, int y) => px[(y * size + x) * 4 + 3];

      // Centre is well inside the solid 0..40% plateau -> alpha ~255.
      expect(alphaAt(size ~/ 2, size ~/ 2), greaterThan(250));
      // The very corner is outside the circle -> alpha 0.
      expect(alphaAt(0, 0), 0);
      // A point near the edge has faded substantially below centre.
      expect(alphaAt(size - 2, size ~/ 2), lessThan(120));
    });
  });
}
