import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Services/pdf_content_extractor.dart';

void main() {
  const extractor = PdfContentExtractor();

  test('extracts literal Tj text from a simple PDF', () {
    final pdf = _simplePdf("BT /F1 12 Tf 10 100 Td (Hello PDF World) Tj ET");
    final extracted = extractor.extract(pdf);
    expect(extracted.text, contains('Hello PDF World'));
    expect(extracted.jpegImages, isEmpty);
  });

  test('joins TJ array strings and treats large negative offsets as spaces', () {
    final pdf = _simplePdf("BT [(Hello) -200 (World)] TJ ET");
    final extracted = extractor.extract(pdf);
    expect(extracted.text, contains('Hello'));
    expect(extracted.text, contains('World'));
    expect(extracted.text, contains('Hello World'));
  });

  test('extracts an embedded DCTDecode JPEG', () {
    final jpeg = Uint8List.fromList(const [
      0xff, 0xd8, 0xff, 0xdb, 0x00, 0x43, 0x00, 0x01,
      0xff, 0xd9,
    ]);
    final pdf = _jpegPdf(jpeg);
    final extracted = extractor.extract(pdf);
    expect(extracted.jpegImages, isNotEmpty);
    expect(extracted.jpegImages.first[0], 0xff);
    expect(extracted.jpegImages.first[1], 0xd8);
  });

  test('rejects encrypted PDFs', () {
    final pdf = latin1.encode(
      '%PDF-1.1\n'
      '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
      'trailer\n<< /Size 2 /Root 1 0 R /Encrypt 3 0 R >>\n'
      'startxref\n0\n%%EOF\n',
    );
    expect(
      () => extractor.extract(Uint8List.fromList(pdf)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects non-PDF bytes', () {
    expect(
      () => extractor.extract(Uint8List.fromList(utf8.encode('not a pdf'))),
      throwsA(isA<FormatException>()),
    );
  });
}

Uint8List _simplePdf(String contentStream) {
  final length = contentStream.length;
  final src = '%PDF-1.1\n'
      '1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n'
      '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
      '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R >>\nendobj\n'
      '4 0 obj\n<< /Length $length >>\nstream\n'
      '$contentStream\n'
      'endstream\nendobj\n'
      'trailer\n<< /Size 5 /Root 1 0 R >>\n'
      'startxref\n0\n%%EOF\n';
  return Uint8List.fromList(latin1.encode(src));
}

Uint8List _jpegPdf(Uint8List jpeg) {
  final stream = latin1.decode(jpeg, allowInvalid: true);
  final src = '%PDF-1.1\n'
      '1 0 obj\n<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpeg.length} >>\n'
      'stream\n'
      '$stream\n'
      'endstream\nendobj\n'
      'trailer\n<< /Size 2 /Root 1 0 R >>\n'
      'startxref\n0\n%%EOF\n';
  return Uint8List.fromList(latin1.encode(src));
}
