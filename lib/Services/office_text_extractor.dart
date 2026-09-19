import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Pulls plain text out of Office Open XML files (docx / xlsx / pptx).
class OfficeTextExtractor {
  const OfficeTextExtractor();

  String extractDocx(Uint8List bytes) {
    final xml = _zipEntry(bytes, 'word/document.xml');
    if (xml == null) {
      throw const FormatException('Not a valid .docx file.');
    }
    return _docxXmlToText(xml);
  }

  String extractXlsx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final shared = _sharedStrings(archive);
    final sheets = archive.files
        .where((f) =>
            f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml'))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (sheets.isEmpty && shared.isEmpty) {
      throw const FormatException('Not a valid .xlsx file.');
    }

    final out = StringBuffer();
    for (var i = 0; i < sheets.length; i++) {
      if (i > 0) out.write('\n\n');
      if (sheets.length > 1) out.writeln('--- Sheet ${i + 1} ---');
      out.write(_sheetToText(_decodeZipFile(sheets[i]), shared));
    }
    return out.toString().trim();
  }

  String extractPptx(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final slides = archive.files
        .where((f) =>
            f.name.startsWith('ppt/slides/slide') &&
            f.name.endsWith('.xml') &&
            !f.name.contains('/_rels/'))
        .toList()
      ..sort((a, b) => _slideNumber(a.name).compareTo(_slideNumber(b.name)));
    if (slides.isEmpty) {
      throw const FormatException('Not a valid .pptx file.');
    }

    final out = StringBuffer();
    for (var i = 0; i < slides.length; i++) {
      if (i > 0) out.write('\n\n');
      out.writeln('--- Slide ${i + 1} ---');
      out.write(_xmlTaggedText(_decodeZipFile(slides[i]), const ['a:t']));
    }
    return out.toString().trim();
  }

  String? _zipEntry(Uint8List bytes, String name) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = archive.files.cast<ArchiveFile?>().firstWhere(
          (f) => f?.name == name,
          orElse: () => null,
        );
    if (file == null) return null;
    return _decodeZipFile(file);
  }

  String _decodeZipFile(ArchiveFile file) {
    final content = file.readBytes();
    if (content == null) return '';
    return utf8.decode(content, allowMalformed: true);
  }

  String _docxXmlToText(String xml) {
    final withBreaks = xml
        .replaceAll(RegExp(r'</w:p>'), '\n')
        .replaceAll(RegExp(r'<w:tab[^/]*/>'), '\t')
        .replaceAll(RegExp(r'<w:br[^/]*/>'), '\n');
    return _xmlTaggedText(withBreaks, const ['w:t']).trim();
  }

  List<String> _sharedStrings(Archive archive) {
    final file = archive.files.cast<ArchiveFile?>().firstWhere(
          (f) => f?.name == 'xl/sharedStrings.xml',
          orElse: () => null,
        );
    if (file == null) return const [];
    final xml = _decodeZipFile(file);
    // Each <si> may contain several <t> runs.
    final items = <String>[];
    for (final si in RegExp(r'<si\b[^>]*>(.*?)</si>', dotAll: true).allMatches(xml)) {
      items.add(_xmlTaggedText(si.group(1) ?? '', const ['t']));
    }
    return items;
  }

  String _sheetToText(String xml, List<String> shared) {
    final rows = <String>[];
    for (final row in RegExp(r'<row\b[^>]*>(.*?)</row>', dotAll: true).allMatches(xml)) {
      final cells = <String>[];
      for (final cell in RegExp(r'<c\b([^>]*)>(.*?)</c>', dotAll: true)
          .allMatches(row.group(1) ?? '')) {
        final attrs = cell.group(1) ?? '';
        final body = cell.group(2) ?? '';
        final type = RegExp(r't="([^"]*)"').firstMatch(attrs)?.group(1);
        if (type == 's') {
          final index = int.tryParse(
                RegExp(r'<v>([^<]*)</v>').firstMatch(body)?.group(1) ?? '',
              ) ??
              -1;
          cells.add(index >= 0 && index < shared.length ? shared[index] : '');
        } else if (type == 'inlineStr') {
          cells.add(_xmlTaggedText(body, const ['t']));
        } else {
          cells.add(RegExp(r'<v>([^<]*)</v>').firstMatch(body)?.group(1) ?? '');
        }
      }
      final line = cells.join('\t').trimRight();
      if (line.trim().isNotEmpty) rows.add(line);
    }
    return rows.join('\n');
  }

  String _xmlTaggedText(String xml, List<String> tags) {
    final out = StringBuffer();
    final pattern = tags.map(RegExp.escape).join('|');
    final re = RegExp('<($pattern)(?:\\s[^>]*)?>(.*?)</\\1>', dotAll: true);
    for (final match in re.allMatches(xml)) {
      if (out.isNotEmpty) {
        // Adjacent runs in a paragraph stay glued; we only add a space when
        // the previous piece does not already end with whitespace.
        final prev = out.toString();
        if (prev.isNotEmpty && !RegExp(r'\s$').hasMatch(prev)) {
          // Word processing runs are usually one word-part; join without
          // inventing spaces — the source XML already has them in <w:t>.
        }
      }
      out.write(_unescapeXml(match.group(2) ?? ''));
    }
    return out.toString();
  }

  int _slideNumber(String name) {
    return int.tryParse(
          RegExp(r'slide(\d+)\.xml$').firstMatch(name)?.group(1) ?? '',
        ) ??
        0;
  }

  String _unescapeXml(String raw) {
    return raw
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll(RegExp(r'<[^>]+>'), '');
  }
}
