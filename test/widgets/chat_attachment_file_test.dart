import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/chat_attachment.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_attachment/chat_attachment_file.dart';

void main() {
  testWidgets('pending file chip shows the name and can be removed', (tester) async {
    final attachment = ChatAttachment(
      fileName: 'brief.pdf',
      kind: ChatAttachmentKind.pdf,
      extractedText: 'Hello',
      pageCount: 3,
    );
    ChatAttachment? removed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatAttachmentFile(
            attachment: attachment,
            onRemove: (value) => removed = value,
          ),
        ),
      ),
    );

    expect(find.text('brief.pdf'), findsOneWidget);
    expect(find.text('PDF · 3 pages'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    expect(removed, same(attachment));
  });

  testWidgets('bubble chip shows the attached file name', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatBubbleFileChip(
            attachment: ChatAttachment(
              fileName: 'slides.pptx',
              kind: ChatAttachmentKind.document,
              extractedText: 'Deck',
            ),
          ),
        ),
      ),
    );

    expect(find.text('slides.pptx'), findsOneWidget);
  });
}
