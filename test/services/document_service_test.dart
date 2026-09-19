import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/chat_attachment.dart';
import 'package:llamaseek/Services/document_service.dart';
import 'package:llamaseek/Services/document_types.dart';
import 'package:llamaseek/Services/file_picker_service.dart';
import 'package:llamaseek/Services/image_service.dart';
import 'package:llamaseek/Services/pdf_content_extractor.dart';

void main() {
  late Directory tempDir;
  late DocumentService service;
  late _FakeImageService images;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('document_service_test');
    images = _FakeImageService();
    service = DocumentService(
      imageService: images,
      storageDirectory: Directory('${tempDir.path}/images'),
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('imports a text file as extracted document text', () async {
    final attachment = await service.import(PickedAttachmentFile(
      name: 'notes.txt',
      bytes: Uint8List.fromList(utf8.encode('  hello notes  ')),
    ));
    expect(attachment.kind, ChatAttachmentKind.document);
    expect(attachment.extractedText, 'hello notes');
    expect(attachment.images, isEmpty);
  });

  test('imports a PDF as text plus saved JPEG pages', () async {
    service = DocumentService(
      imageService: images,
      storageDirectory: Directory('${tempDir.path}/images'),
      pdfExtractor: _FakePdfExtractor(),
    );
    final attachment = await service.import(PickedAttachmentFile(
      name: 'report.pdf',
      bytes: Uint8List.fromList(utf8.encode('%PDF-1.1 fake')),
    ));
    expect(attachment.kind, ChatAttachmentKind.pdf);
    expect(attachment.extractedText, contains('Quarterly report'));
    expect(attachment.images, hasLength(1));
    expect(attachment.images.single.existsSync(), isTrue);
  });

  test('rejects legacy .doc files with a convert hint', () async {
    expect(
      () => service.import(PickedAttachmentFile(
        name: 'old.doc',
        bytes: Uint8List.fromList([0, 1, 2]),
      )),
      throwsA(isA<DocumentImportException>()),
    );
  });

  test('rejects files over the size cap', () async {
    expect(
      () => service.import(PickedAttachmentFile(
        name: 'huge.txt',
        bytes: Uint8List(DocumentService.maxFileBytes + 1),
      )),
      throwsA(isA<DocumentImportException>()),
    );
  });

  test('strips HTML before sending it as text', () async {
    final attachment = await service.import(PickedAttachmentFile(
      name: 'page.html',
      bytes: Uint8List.fromList(utf8.encode('<html><p>Hi&nbsp;there</p></html>')),
    ));
    expect(attachment.extractedText, contains('Hi there'));
    expect(attachment.extractedText, isNot(contains('<p>')));
  });
}

class _FakeImageService implements ImageService {
  @override
  Future<File?> compressAndSave(String sourcePath, {int quality = 10}) async {
    return File(sourcePath);
  }

  @override
  Future<void> deleteImage(File imageFile) async {}

  @override
  Future<void> deleteImages(List<File> imageFiles) async {}

  @override
  Future<Directory> getImagesDirectory() async => Directory.systemTemp;
}

class _FakePdfExtractor implements PdfContentExtractor {
  @override
  PdfExtractedContent extract(Uint8List bytes) {
    return PdfExtractedContent(
      text: 'Quarterly report',
      jpegImages: [
        Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xd9]),
      ],
    );
  }
}
