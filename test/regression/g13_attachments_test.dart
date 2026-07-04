import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_attachment/chat_attachment_image.dart';
import 'package:llamaseek/Widgets/chat_image.dart';

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
/// the height-derived thumbnail math is deterministic.
Widget _host(Widget child, {required Size size}) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(size: size),
          child: Scaffold(
            body: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [child]),
            ),
          ),
        );
      },
    ),
  );
}

void main() {
  late Directory tempDir;
  late File image;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('g13_attachments');
    image = File('${tempDir.path}/img.png');
    image.writeAsBytesSync(Uint8List.fromList(_tinyPng));
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets(
      'remove button exposes at least a 48x48 dp tap target', (tester) async {
    var removed = false;
    await tester.pumpWidget(
      _host(
        ChatAttachmentImage(
          imageFile: image,
          onRemove: (_) => removed = true,
        ),
        size: const Size(390, 844),
      ),
    );

    final inkWell = find.byType(InkWell);
    expect(inkWell, findsOneWidget);

    final tapTarget = tester.getSize(inkWell);
    expect(tapTarget.width, greaterThanOrEqualTo(48),
        reason: 'the remove button hit area must meet the 48dp minimum');
    expect(tapTarget.height, greaterThanOrEqualTo(48),
        reason: 'the remove button hit area must meet the 48dp minimum');

    // A tap near the corner of the enlarged target still removes the image.
    await tester.tap(inkWell);
    expect(removed, isTrue);
  });

  testWidgets(
      'thumbnail does not force a 1:1 square crop on attachment previews',
      (tester) async {
    await tester.pumpWidget(
      _host(
        ChatAttachmentImage(
          imageFile: image,
          onRemove: (_) {},
        ),
        size: const Size(390, 844),
      ),
    );

    final chatImage = tester.widget<ChatImage>(find.byType(ChatImage));
    expect(chatImage.aspectRatio, isNot(1.0),
        reason: 'a square crop hides the real orientation of the attachment');
    expect(chatImage.height,
        closeTo(844 * ChatAttachmentImage.previewHeightFactor, 0.001),
        reason: 'the preview is still sized by the height-derived factor');
    expect(chatImage.width, isNull,
        reason: 'width stays null so decode preserves the source aspect ratio');
  });
}
