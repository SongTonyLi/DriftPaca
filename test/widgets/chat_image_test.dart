import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Widgets/chat_image.dart';

// The `Image` widget does not expose public cacheWidth/cacheHeight getters;
// those constructor args are folded into `Image.image` via
// `ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight, provider)`. That wraps
// the provider in a `ResizeImage(width: cacheWidth, height: cacheHeight)` when
// either dimension is non-null, and returns the bare provider when both are
// null. So the observable effect of cacheWidth/cacheHeight is exactly the
// `ResizeImage.width`/`ResizeImage.height` we assert on below.

/// A 1x1 transparent PNG. We never wait for it to decode; we only inspect the
/// built [Image] widget's provider synchronously after pump.
final _tinyImage = MemoryImage(Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]));

/// Pumps [child] under a [MaterialApp] with a fixed [devicePixelRatio] so the
/// cacheWidth/cacheHeight math is deterministic.
Widget _host(Widget child, {required double devicePixelRatio}) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(devicePixelRatio: devicePixelRatio),
          child: Scaffold(body: Center(child: child)),
        );
      },
    ),
  );
}

void main() {
  testWidgets(
      'bubble-thumbnail pattern (width given): caps decode width at width * DPR, '
      'leaves height uncapped', (tester) async {
    await tester.pumpWidget(
      _host(
        ChatImage(image: _tinyImage, aspectRatio: 1.5, width: 120),
        devicePixelRatio: 2.0,
      ),
    );

    final provider = tester.widget<Image>(find.byType(Image)).image;
    expect(provider, isA<ResizeImage>(),
        reason: 'a width was given, so decode must be capped');
    final resize = provider as ResizeImage;
    expect(resize.width, 240, reason: '120 * 2.0 devicePixelRatio (cacheWidth)');
    expect(resize.height, isNull,
        reason: 'height not provided; preserve source aspect ratio '
            '(cacheHeight stays null)');
  });

  testWidgets(
      'attachment-preview pattern (height given): caps decode height at '
      'height * DPR, leaves width uncapped', (tester) async {
    await tester.pumpWidget(
      _host(
        ChatImage(image: _tinyImage, height: 90),
        devicePixelRatio: 2.0,
      ),
    );

    final provider = tester.widget<Image>(find.byType(Image)).image;
    expect(provider, isA<ResizeImage>(),
        reason: 'a height was given, so decode must be capped');
    final resize = provider as ResizeImage;
    expect(resize.height, 180,
        reason: '90 * 2.0 devicePixelRatio (cacheHeight)');
    expect(resize.width, isNull,
        reason: 'width not provided; preserve source aspect ratio '
            '(cacheWidth stays null)');
  });
}
