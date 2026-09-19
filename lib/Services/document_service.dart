import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:llamaseek/Constants/constants.dart';
import 'package:llamaseek/Models/chat_attachment.dart';
import 'package:llamaseek/Services/document_types.dart';
import 'package:llamaseek/Services/file_picker_service.dart';
import 'package:llamaseek/Services/image_service.dart';
import 'package:llamaseek/Services/office_text_extractor.dart';
import 'package:llamaseek/Services/pdf_content_extractor.dart';

/// Turns a picked file into a [ChatAttachment] the model can read.
class DocumentService {
  static const int maxFileBytes = 25 * 1024 * 1024;
  static const int maxTextChars = 80000;

  final ImageService _imageService;
  final PdfContentExtractor _pdfExtractor;
  final OfficeTextExtractor _officeExtractor;
  final Directory? _storageDirectory;

  DocumentService({
    required ImageService imageService,
    PdfContentExtractor pdfExtractor = const PdfContentExtractor(),
    OfficeTextExtractor officeExtractor = const OfficeTextExtractor(),
    Directory? storageDirectory,
  })  : _imageService = imageService,
        _pdfExtractor = pdfExtractor,
        _officeExtractor = officeExtractor,
        _storageDirectory = storageDirectory;

  Future<ChatAttachment> import(PickedAttachmentFile picked) async {
    final bytes = await _readBytes(picked);
    if (bytes.length > maxFileBytes) {
      throw DocumentImportException(
        'This file is too large. Please choose a file under 25 MB.',
      );
    }

    final fileName = picked.name;
    if (DocumentTypes.isUnsupportedLegacy(fileName)) {
      throw DocumentImportException(
        'This older Office format is not supported. Save it as .docx, .xlsx, or .pptx and try again.',
      );
    }

    if (DocumentTypes.isImage(fileName)) {
      return _importImage(picked, fileName);
    }
    if (DocumentTypes.isPdf(fileName)) {
      return _importPdf(fileName, bytes);
    }
    if (DocumentTypes.isWord(fileName)) {
      return _importOffice(fileName, ChatAttachmentKind.document, () {
        return _officeExtractor.extractDocx(bytes);
      });
    }
    if (DocumentTypes.isSheet(fileName)) {
      return _importOffice(fileName, ChatAttachmentKind.document, () {
        return _officeExtractor.extractXlsx(bytes);
      });
    }
    if (DocumentTypes.isSlide(fileName)) {
      return _importOffice(fileName, ChatAttachmentKind.document, () {
        return _officeExtractor.extractPptx(bytes);
      });
    }
    if (DocumentTypes.isText(fileName)) {
      return ChatAttachment(
        fileName: fileName,
        kind: ChatAttachmentKind.document,
        extractedText: _truncate(_decodeText(fileName, bytes)),
      );
    }

    throw DocumentImportException(
      'This file type is not supported. You can attach images, PDFs, Word, Excel, PowerPoint, or text files.',
    );
  }

  Future<Uint8List> _readBytes(PickedAttachmentFile picked) async {
    if (picked.bytes != null && picked.bytes!.isNotEmpty) {
      return picked.bytes!;
    }
    if (picked.path != null && picked.path!.isNotEmpty) {
      return File(picked.path!).readAsBytes();
    }
    throw DocumentImportException('The selected file could not be read.');
  }

  Future<ChatAttachment> _importImage(
    PickedAttachmentFile picked,
    String fileName,
  ) async {
    String? sourcePath = picked.path;
    File? temp;
    if (sourcePath == null || sourcePath.isEmpty) {
      if (picked.bytes == null) {
        throw DocumentImportException('The selected image could not be read.');
      }
      temp = File(path.join(
        Directory.systemTemp.path,
        'driftpaca-${DateTime.now().microsecondsSinceEpoch}-$fileName',
      ));
      await temp.writeAsBytes(picked.bytes!);
      sourcePath = temp.path;
    }

    try {
      final compressed = await _imageService.compressAndSave(sourcePath);
      if (compressed == null) {
        throw DocumentImportException(
          'The selected image could not be processed. Please try a different file.',
        );
      }
      return ChatAttachment(
        fileName: fileName,
        kind: ChatAttachmentKind.image,
        images: [compressed],
      );
    } finally {
      if (temp != null && await temp.exists()) {
        await temp.delete();
      }
    }
  }

  Future<ChatAttachment> _importPdf(String fileName, Uint8List bytes) async {
    late final PdfExtractedContent extracted;
    try {
      extracted = _pdfExtractor.extract(bytes);
    } on FormatException catch (error) {
      throw DocumentImportException(error.message);
    } catch (_) {
      throw DocumentImportException(
        'This PDF could not be read. Try exporting it again or sending screenshots of the pages.',
      );
    }

    final images = <File>[];
    for (final jpeg in extracted.jpegImages) {
      images.add(await _saveJpeg(jpeg));
    }

    final text = _truncate(extracted.text);
    if (text.trim().isEmpty && images.isEmpty) {
      throw DocumentImportException(
        'No text or images could be read from this PDF.',
      );
    }

    return ChatAttachment(
      fileName: fileName,
      kind: ChatAttachmentKind.pdf,
      extractedText: text.trim().isEmpty ? null : text,
      images: images,
      pageCount: images.isEmpty ? null : images.length,
    );
  }

  ChatAttachment _importOffice(
    String fileName,
    ChatAttachmentKind kind,
    String Function() extract,
  ) {
    try {
      final text = _truncate(extract());
      if (text.trim().isEmpty) {
        throw DocumentImportException(
          'No text could be read from $fileName.',
        );
      }
      return ChatAttachment(
        fileName: fileName,
        kind: kind,
        extractedText: text,
      );
    } on DocumentImportException {
      rethrow;
    } on FormatException catch (error) {
      throw DocumentImportException(error.message);
    } catch (_) {
      throw DocumentImportException(
        '$fileName could not be read. Try exporting it again as a newer Office file.',
      );
    }
  }

  String _decodeText(String fileName, Uint8List bytes) {
    final ext = DocumentTypes.extensionOf(fileName);
    String text;
    try {
      text = utf8.decode(bytes);
    } catch (_) {
      text = latin1.decode(bytes, allowInvalid: true);
    }
    if (ext == 'html' || ext == 'htm') {
      text = _stripHtml(text);
    } else if (ext == 'rtf') {
      text = _stripRtf(text);
    }
    return text;
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(
          RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style[^>]*>.*?</style>', caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _stripRtf(String rtf) {
    var text = rtf.replaceAll(RegExp(r'\\par[d]?'), '\n');
    text = text.replaceAll(RegExp(r"\\'[0-9a-fA-F]{2}"), ' ');
    text = text.replaceAll(RegExp(r'\\[a-zA-Z]+-?\d* ?'), '');
    text = text.replaceAll(RegExp(r'[{}]'), '');
    return text.replaceAll(RegExp(r'[ \t]+\n'), '\n').trim();
  }

  String _truncate(String text) {
    final trimmed = text.replaceAll('\u0000', '').trim();
    if (trimmed.length <= maxTextChars) return trimmed;
    return '${trimmed.substring(0, maxTextChars)}\n\n[Document text truncated]';
  }

  Future<File> _saveJpeg(Uint8List bytes) async {
    final dir = await _imagesDirectory();
    final file = File(path.join(
      dir.path,
      '${DateTime.now().microsecondsSinceEpoch}.jpg',
    ));
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<Directory> _imagesDirectory() async {
    if (_storageDirectory != null) {
      return _storageDirectory.create(recursive: true);
    }
    final documents = PathManager.instance.documentsDirectory;
    final imagesPath = path.join(documents.path, 'images');
    return Directory(imagesPath).create(recursive: true);
  }
}
