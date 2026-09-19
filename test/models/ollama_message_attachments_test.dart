import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/chat_attachment.dart';
import 'package:llamaseek/Models/ollama_message.dart';

void main() {
  test('modelContent appends extracted document text and keeps the user prompt', () {
    final message = OllamaMessage(
      'Summarize this',
      role: OllamaMessageRole.user,
      attachments: [
        ChatAttachment(
          fileName: 'notes.txt',
          kind: ChatAttachmentKind.document,
          extractedText: 'Quarterly revenue rose.',
        ),
      ],
    );

    final content = message.modelContent();
    expect(content, contains('Summarize this'));
    expect(content, contains('notes.txt'));
    expect(content, contains('Quarterly revenue rose.'));
  });

  test('toChatJson includes document text and omits images when vision is off', () async {
    final image = File('${Directory.systemTemp.path}/page.jpg');
    await image.writeAsBytes(const [0xff, 0xd8, 0xff, 0xd9]);
    addTearDown(() {
      if (image.existsSync()) image.deleteSync();
    });
    final message = OllamaMessage(
      'What does this PDF say?',
      role: OllamaMessageRole.user,
      images: [image],
      attachments: [
        ChatAttachment(
          fileName: 'brief.pdf',
          kind: ChatAttachmentKind.pdf,
          extractedText: 'Page one text',
          images: [image],
          pageCount: 1,
        ),
      ],
    );

    final withVision = await message.toChatJson();
    expect(withVision['content'], contains('Page one text'));
    expect(withVision.containsKey('images'), isTrue);

    final withoutVision = await message.toChatJson(supportsVision: false);
    expect(withoutVision['content'], contains('Page one text'));
    expect(withoutVision.containsKey('images'), isFalse);
    expect(
      withoutVision['content'],
      isNot(contains('not viewable by this model')),
      reason: 'extracted text is enough; no need for the image placeholder',
    );
  });

  test('photo-only messages still get a placeholder on non-vision models', () async {
    final image = File('${Directory.systemTemp.path}/photo.jpg');
    final message = OllamaMessage(
      'What is this?',
      role: OllamaMessageRole.user,
      images: [image],
      attachments: [
        ChatAttachment(
          fileName: 'photo.jpg',
          kind: ChatAttachmentKind.image,
          images: [image],
        ),
      ],
    );

    final json = await message.toChatJson(supportsVision: false);
    expect(json.containsKey('images'), isFalse);
    expect(json['content'], contains('not viewable by this model'));
    expect(json['content'], contains('What is this?'));
  });
}
