import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Services/office_text_extractor.dart';

void main() {
  const extractor = OfficeTextExtractor();

  test('extracts paragraph text from a docx zip', () {
    final bytes = _zip({
      'word/document.xml':
          '<?xml version="1.0"?><w:document><w:body><w:p><w:r><w:t>Hello</w:t></w:r><w:r><w:t> World</w:t></w:r></w:p><w:p><w:r><w:t>Second</w:t></w:r></w:p></w:body></w:document>',
    });
    expect(extractor.extractDocx(bytes), contains('Hello World'));
    expect(extractor.extractDocx(bytes), contains('Second'));
  });

  test('extracts shared-string cells from a xlsx zip', () {
    final bytes = _zip({
      'xl/sharedStrings.xml':
          '<?xml version="1.0"?><sst><si><t>Name</t></si><si><t>Ada</t></si></sst>',
      'xl/worksheets/sheet1.xml':
          '<?xml version="1.0"?><worksheet><sheetData>'
          '<row><c t="s"><v>0</v></c><c t="s"><v>1</v></c></row>'
          '<row><c><v>42</v></c></row>'
          '</sheetData></worksheet>',
    });
    final text = extractor.extractXlsx(bytes);
    expect(text, contains('Name'));
    expect(text, contains('Ada'));
    expect(text, contains('42'));
  });

  test('extracts slide text from a pptx zip', () {
    final bytes = _zip({
      'ppt/slides/slide1.xml':
          '<?xml version="1.0"?><p:sld><p:txBody><a:p><a:r><a:t>Title</a:t></a:r></p:p></p:txBody></p:sld>',
      'ppt/slides/slide2.xml':
          '<?xml version="1.0"?><p:sld><p:txBody><a:p><a:r><a:t>Body copy</a:t></a:r></p:p></p:txBody></p:sld>',
    });
    final text = extractor.extractPptx(bytes);
    expect(text, contains('Slide 1'));
    expect(text, contains('Title'));
    expect(text, contains('Body copy'));
  });
}

Uint8List _zip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((name, contents) {
    final data = utf8.encode(contents);
    archive.addFile(ArchiveFile(name, data.length, data));
  });
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}
