import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/chat_attachment.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Services/ollama_service.dart';

void main() {
  test('prepareMessages keeps PDF text and drops page images without vision', () async {
    final page = File('${Directory.systemTemp.path}/pdf-page.jpg');
    final user = OllamaMessage(
      'Summarize',
      role: OllamaMessageRole.user,
      images: [page],
      attachments: [
        ChatAttachment(
          fileName: 'brief.pdf',
          kind: ChatAttachmentKind.pdf,
          extractedText: 'Contract clause 4',
          images: [page],
        ),
      ],
    );

    final prepared = await OllamaService().prepareMessagesWithSystemPrompt(
      [user],
      null,
      supportsVision: false,
    );

    expect(prepared.single['content'], contains('Contract clause 4'));
    expect(prepared.single.containsKey('images'), isFalse);
  });

  test('prepareMessages includes images when the model can see them', () async {
    final page = File('${Directory.systemTemp.path}/visible.jpg');
    await page.writeAsBytes(const [0xff, 0xd8, 0xff, 0xd9]);
    addTearDown(() {
      if (page.existsSync()) page.deleteSync();
    });

    final user = OllamaMessage(
      'Look at this',
      role: OllamaMessageRole.user,
      images: [page],
      attachments: [
        ChatAttachment(
          fileName: 'shot.jpg',
          kind: ChatAttachmentKind.image,
          images: [page],
        ),
      ],
    );

    final prepared = await OllamaService().prepareMessagesWithSystemPrompt(
      [user],
      null,
      supportsVision: true,
    );

    expect(prepared.single['content'], 'Look at this');
    expect(prepared.single['images'], isA<List>());
    expect((prepared.single['images'] as List).single, isNotEmpty);
  });
}
