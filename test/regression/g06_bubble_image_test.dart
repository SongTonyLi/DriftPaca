import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_image.dart';
import 'package:llamaseek/Widgets/chat_image.dart';
import 'package:photo_view/photo_view_gallery.dart';

class _RecordingObserver extends NavigatorObserver {
  TransitionRoute<dynamic>? pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is TransitionRoute<dynamic>) {
      pushed = route;
    }
  }
}

/// A 1x1 transparent PNG written to disk so `FileImage` has a real source.
const List<int> _tinyPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

/// Pumps [child] under a [MaterialApp] with a fixed logical screen [size] so
/// the orientation-dependent thumbnail math is deterministic.
Widget _host(
  Widget child, {
  required Size size,
  bool disableAnimations = false,
  NavigatorObserver? observer,
}) {
  return MaterialApp(
    navigatorObservers: [if (observer != null) observer],
    home: Builder(
      builder: (context) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: size,
            disableAnimations: disableAnimations,
          ),
          child: Scaffold(body: Center(child: child)),
        );
      },
    ),
  );
}

void main() {
  late Directory tempDir;
  late List<File> images;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('g06_bubble_image');
    images = List.generate(3, (i) {
      final file = File('${tempDir.path}/img_$i.png');
      file.writeAsBytesSync(Uint8List.fromList(_tinyPng));
      return file;
    });
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets(
      'thumbnail width is the width-derived term on a tall/narrow portrait '
      'phone, not the height-derived one', (tester) async {
    // iPhone 14 logical size: height/width = 844/390 = 2.16, well above 1.4,
    // so the old max(...) formula picked height * 0.25 = 211 instead of the
    // intended width * 0.35 = 136.5.
    const size = Size(390, 844);
    await tester.pumpWidget(
      _host(
        ChatBubbleImage(
          imageFile: images[0],
          allImages: images,
          index: 0,
        ),
        size: size,
      ),
    );

    final chatImage = tester.widget<ChatImage>(find.byType(ChatImage));
    expect(chatImage.width, closeTo(size.width * 0.35, 0.001),
        reason: 'width should be 35% of screen width on a portrait phone');
    expect(chatImage.width, lessThan(size.height * 0.25),
        reason: 'the height-derived term must not win in portrait');
  });

  testWidgets(
      'thumbnail width is capped by the height-derived term in landscape',
      (tester) async {
    // Landscape: height/width = 390/844 = 0.46, so height * 0.25 = 97.5 is
    // smaller than width * 0.35 = 295.4 and should cap the thumbnail.
    const size = Size(844, 390);
    await tester.pumpWidget(
      _host(
        ChatBubbleImage(
          imageFile: images[0],
          allImages: images,
          index: 0,
        ),
        size: size,
      ),
    );

    final chatImage = tester.widget<ChatImage>(find.byType(ChatImage));
    expect(chatImage.width, closeTo(size.height * 0.25, 0.001),
        reason: 'the smaller height-derived term should cap width in landscape');
  });

  testWidgets(
      'swiping to the next gallery page resets the shared scale state so the '
      'next image is not pre-zoomed', (tester) async {
    await tester.pumpWidget(
      _host(
        ChatBubbleImage(
          imageFile: images[0],
          allImages: images,
          index: 0,
        ),
        size: const Size(390, 844),
      ),
    );

    await tester.tap(find.byType(ChatBubbleImage));
    // Bounded pumps: FileImage decoding leaves the scheduler perpetually busy,
    // so pumpAndSettle would time out. A few frames are enough to open the
    // route and settle the fade transition.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(PhotoViewGallery), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);

    // Swipe to the next page.
    await tester.fling(
      find.byType(PhotoViewGallery),
      const Offset(-400, 0),
      1000,
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('2 / 3'), findsOneWidget,
        reason: 'the page counter should advance to the second image');
  });

  testWidgets('gallery route has zero timing when animations are disabled',
      (tester) async {
    final observer = _RecordingObserver();
    await tester.pumpWidget(
      _host(
        ChatBubbleImage(
          imageFile: images[0],
          allImages: images,
          index: 0,
        ),
        size: const Size(390, 844),
        disableAnimations: true,
        observer: observer,
      ),
    );

    await tester.tap(find.byType(ChatBubbleImage));
    await tester.pump();

    expect(observer.pushed!.transitionDuration, Duration.zero);
    expect(observer.pushed!.reverseTransitionDuration, Duration.zero);
  });

  testWidgets('gallery dots skip size animation with reduced motion',
      (tester) async {
    await tester.pumpWidget(
      _host(
        ChatBubbleImage(
          imageFile: images[0],
          allImages: images,
          index: 0,
        ),
        size: const Size(390, 844),
        disableAnimations: true,
      ),
    );
    await tester.tap(find.byType(ChatBubbleImage));
    await tester.pump();

    final dot = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('gallery-dot-0')),
    );
    expect(dot.duration, Duration.zero);
  });
}
