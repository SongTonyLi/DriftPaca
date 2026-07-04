import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _longModel = 'hf.co/bartowski/Qwen2.5-72B-Instruct-GGUF:Q4_K_M';

// Mirrors the model-chip subtree of ChatAppBar so the layout chain
// (FractionallySizedBox -> Column(min) -> Container -> InkWell -> Row(min))
// that produced the overflow is exercised without the full provider stack.
Widget _chip(String model) {
  return MaterialApp(
    home: Scaffold(
      appBar: AppBar(
        title: FractionallySizedBox(
          widthFactor: 0.8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'A conversation title',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              InkWell(
                onTap: () {},
                customBorder: const StadiumBorder(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3.0),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.dns_outlined, size: 12),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.kodeMono(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('long model name in the chip does not overflow the title bound',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_chip(_longModel));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final chipText = tester.renderObject<RenderParagraph>(find.text(_longModel));
    expect(chipText.size.width, lessThanOrEqualTo(360 * 0.8));
  });

  testWidgets('short model name still renders in full', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_chip('llama3.2'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('llama3.2'), findsOneWidget);
  });
}
