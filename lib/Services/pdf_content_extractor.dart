import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Text plus JPEG images pulled out of a PDF so a chat model can read it.
class PdfExtractedContent {
  final String text;
  final List<Uint8List> jpegImages;

  const PdfExtractedContent({
    required this.text,
    this.jpegImages = const [],
  });
}

/// Best-effort PDF reader: content-stream text and DCTDecode (JPEG) images.
///
/// Encrypted documents are rejected. Modern object streams are expanded so
/// compressed PDFs still yield text. This is not a full renderer — layout is
/// flattened — but it is enough for a model to understand typical documents
/// and scanned pages stored as embedded JPEGs.
class PdfContentExtractor {
  const PdfContentExtractor();

  static const int maxImages = 12;
  static const int maxTextChars = 80000;

  PdfExtractedContent extract(Uint8List bytes) {
    if (bytes.length < 5 ||
        bytes[0] != 0x25 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x44 ||
        bytes[3] != 0x46) {
      throw const FormatException('Not a PDF file.');
    }

    final src = latin1.decode(bytes, allowInvalid: true);
    if (_trailerHasEncrypt(src)) {
      throw const FormatException('This PDF is encrypted and cannot be read.');
    }

    final objects = <String, _PdfObject>{};
    _collectObjects(src, objects);
    _expandObjectStreams(objects);

    final texts = <String>[];
    final images = <Uint8List>[];
    final seenImage = <String>{};

    for (final object in objects.values) {
      if (object.stream == null) continue;
      final dict = object.dict;
      final subtype = dict['/Subtype'];
      final type = dict['/Type'];
      final filter = _filterName(dict['/Filter']);

      final isImage = subtype == '/Image' ||
          (type == '/XObject' && subtype == '/Image') ||
          (filter == '/DCTDecode' && dict.containsKey('/Width'));
      if (isImage) {
        if (filter == '/DCTDecode' &&
            images.length < maxImages &&
            seenImage.add(object.id)) {
          final jpeg = _asJpeg(object.stream!);
          if (jpeg != null) images.add(jpeg);
        }
        continue;
      }

      if (type == '/ObjStm' || type == '/XRef' || type == '/Metadata') {
        continue;
      }

      final decoded = latin1.decode(object.stream!, allowInvalid: true);
      if (decoded.contains('Tj') ||
          decoded.contains('TJ') ||
          decoded.contains("'") ||
          decoded.contains('BT')) {
        final pageText = _extractTextFromContent(decoded);
        if (pageText.trim().isNotEmpty) texts.add(pageText);
      }
    }

    var text = texts.join('\n\n').trim();
    if (text.length > maxTextChars) {
      text = '${text.substring(0, maxTextChars)}\n\n[Document text truncated]';
    }

    return PdfExtractedContent(text: text, jpegImages: images);
  }

  bool _trailerHasEncrypt(String src) {
    final start = src.lastIndexOf('trailer');
    if (start < 0) {
      // Object-stream PDFs may put /Encrypt on the catalog; treat any
      // /Encrypt token near the end as encrypted.
      final tail = src.substring(src.length > 8000 ? src.length - 8000 : 0);
      return tail.contains('/Encrypt');
    }
    final end = src.indexOf('startxref', start);
    final trailer = end > start ? src.substring(start, end) : src.substring(start);
    return trailer.contains('/Encrypt');
  }

  void _collectObjects(String src, Map<String, _PdfObject> objects) {
    final objRe = RegExp(r'(\d+)\s+(\d+)\s+obj');
    for (final match in objRe.allMatches(src)) {
      final id = '${match.group(1)} ${match.group(2)}';
      var cursor = match.end;
      while (cursor < src.length && _isWs(src.codeUnitAt(cursor))) {
        cursor++;
      }
      if (cursor >= src.length) continue;

      final parsed = _parseValue(src, cursor);
      cursor = parsed.next;
      Map<String, dynamic> dict = const {};
      if (parsed.value is Map<String, dynamic>) {
        dict = parsed.value as Map<String, dynamic>;
      }

      Uint8List? stream;
      while (cursor < src.length && _isWs(src.codeUnitAt(cursor))) {
        cursor++;
      }
      if (src.startsWith('stream', cursor)) {
        cursor += 6;
        if (cursor < src.length && src.codeUnitAt(cursor) == 0x0d) cursor++;
        if (cursor < src.length && src.codeUnitAt(cursor) == 0x0a) cursor++;
        final length = _resolveLength(dict['/Length'], objects);
        int end;
        if (length != null && cursor + length <= src.length) {
          end = cursor + length;
        } else {
          end = src.indexOf('endstream', cursor);
          if (end < 0) continue;
        }
        final raw = Uint8List.fromList(latin1.encode(src.substring(cursor, end)));
        stream = _decodeStream(raw, dict);
      }

      objects[id] = _PdfObject(id: id, dict: dict, stream: stream, raw: parsed.value);
    }
  }

  void _expandObjectStreams(Map<String, _PdfObject> objects) {
    final extras = <String, _PdfObject>{};
    for (final object in objects.values) {
      if (object.dict['/Type'] != '/ObjStm' || object.stream == null) continue;
      final n = _asInt(object.dict['/N']) ?? 0;
      final first = _asInt(object.dict['/First']) ?? 0;
      final body = latin1.decode(object.stream!, allowInvalid: true);
      if (n <= 0 || first <= 0 || first > body.length) continue;

      final header = body.substring(0, first);
      final nums = RegExp(r'\d+')
          .allMatches(header)
          .map((m) => int.tryParse(m.group(0)!) ?? 0)
          .toList();
      for (var i = 0; i + 1 < nums.length && i / 2 < n; i += 2) {
        final objNum = nums[i];
        final offset = nums[i + 1];
        final start = first + offset;
        if (start < 0 || start >= body.length) continue;
        final end = (i + 3 < nums.length)
            ? first + nums[i + 3]
            : body.length;
        final slice = body.substring(start, end.clamp(start, body.length));
        final parsed = _parseValue(slice, 0);
        Map<String, dynamic> dict = const {};
        Uint8List? stream;
        if (parsed.value is Map<String, dynamic>) {
          dict = parsed.value as Map<String, dynamic>;
          var cursor = parsed.next;
          while (cursor < slice.length && _isWs(slice.codeUnitAt(cursor))) {
            cursor++;
          }
          if (slice.startsWith('stream', cursor)) {
            cursor += 6;
            if (cursor < slice.length && slice.codeUnitAt(cursor) == 0x0d) {
              cursor++;
            }
            if (cursor < slice.length && slice.codeUnitAt(cursor) == 0x0a) {
              cursor++;
            }
            final length = _asInt(dict['/Length']);
            final streamEnd = length != null
                ? (cursor + length).clamp(0, slice.length)
                : slice.indexOf('endstream', cursor);
            if (streamEnd > cursor) {
              final raw = Uint8List.fromList(
                latin1.encode(slice.substring(cursor, streamEnd)),
              );
              stream = _decodeStream(raw, dict);
            }
          }
        }
        extras['$objNum 0'] = _PdfObject(
          id: '$objNum 0',
          dict: dict,
          stream: stream,
          raw: parsed.value,
        );
      }
    }
    objects.addAll(extras);
  }

  int? _resolveLength(dynamic value, Map<String, _PdfObject> objects) {
    final direct = _asInt(value);
    if (direct != null) return direct;
    if (value is _PdfRef) {
      final target = objects[value.id];
      return _asInt(target?.raw);
    }
    return null;
  }

  Uint8List? _decodeStream(Uint8List raw, Map<String, dynamic> dict) {
    var data = raw;
    final filters = _filterList(dict['/Filter']);
    for (final filter in filters) {
      switch (filter) {
        case '/FlateDecode':
        case '/Fl':
          try {
            data = Uint8List.fromList(const ZLibDecoder().decodeBytes(data));
          } catch (_) {
            try {
              data = Uint8List.fromList(
                const ZLibDecoder().decodeBytes(data, raw: true),
              );
            } catch (_) {
              return null;
            }
          }
        case '/ASCIIHexDecode':
        case '/AHx':
          data = _decodeAsciiHex(latin1.decode(data, allowInvalid: true));
        case '/ASCII85Decode':
        case '/A85':
          data = _decodeAscii85(latin1.decode(data, allowInvalid: true));
        case '/DCTDecode':
        case '/DCT':
          // JPEG payload — leave as-is.
          break;
        default:
          // Unsupported filter (CCITT, JBIG2, JPX, …).
          if (filter == '/DCTDecode') break;
          return data;
      }
    }
    return data;
  }

  List<String> _filterList(dynamic filter) {
    if (filter is String) return [filter];
    if (filter is List) {
      return [
        for (final item in filter)
          if (item is String) item,
      ];
    }
    return const [];
  }

  String? _filterName(dynamic filter) {
    final list = _filterList(filter);
    return list.isEmpty ? null : list.last;
  }

  Uint8List? _asJpeg(Uint8List bytes) {
    if (bytes.length < 3) return null;
    if (bytes[0] == 0xff && bytes[1] == 0xd8) return bytes;
    final start = _indexOfJpegSoi(bytes);
    if (start < 0) return null;
    return Uint8List.sublistView(bytes, start);
  }

  int _indexOfJpegSoi(Uint8List bytes) {
    for (var i = 0; i < bytes.length - 1; i++) {
      if (bytes[i] == 0xff && bytes[i + 1] == 0xd8) return i;
    }
    return -1;
  }

  String _extractTextFromContent(String content) {
    final out = StringBuffer();
    final tj = RegExp(r'\[(.*?)\]\s*TJ', dotAll: true);
    final tjSingle = RegExp(r"(\((?:\\.|[^\\)])*\)|<[^>]+>)\s*Tj");
    final quote = RegExp(r"(\((?:\\.|[^\\)])*\)|<[^>]+>)\s*'");
    final tStar = RegExp(r'T\*');

    var cursor = 0;
    final events = <({int pos, String text, bool newline})>[];

    for (final match in tStar.allMatches(content)) {
      events.add((pos: match.start, text: '', newline: true));
    }
    for (final match in tj.allMatches(content)) {
      events.add((
        pos: match.start,
        text: _textFromTjArray(match.group(1) ?? ''),
        newline: false,
      ));
    }
    for (final match in tjSingle.allMatches(content)) {
      events.add((
        pos: match.start,
        text: _decodePdfStringToken(match.group(1) ?? ''),
        newline: false,
      ));
    }
    for (final match in quote.allMatches(content)) {
      events.add((
        pos: match.start,
        text: _decodePdfStringToken(match.group(1) ?? ''),
        newline: true,
      ));
    }

    events.sort((a, b) => a.pos.compareTo(b.pos));
    for (final event in events) {
      if (event.pos < cursor) continue;
      cursor = event.pos;
      if (event.newline && out.isNotEmpty) out.write('\n');
      out.write(event.text);
    }

    return out.toString().replaceAll(RegExp(r'[ \t]+\n'), '\n').trim();
  }

  String _textFromTjArray(String body) {
    final out = StringBuffer();
    var i = 0;
    while (i < body.length) {
      final ch = body.codeUnitAt(i);
      if (_isWs(ch)) {
        i++;
        continue;
      }
      if (ch == 0x28 || ch == 0x3c) {
        final parsed = _parseValue(body, i);
        i = parsed.next;
        if (parsed.value is String) out.write(parsed.value);
        continue;
      }
      // Kerning / spacing number. Large negative values are word gaps.
      final numMatch = RegExp(r'[+\-]?\d+(?:\.\d+)?').matchAsPrefix(body, i);
      if (numMatch != null) {
        final offset = double.tryParse(numMatch.group(0)!) ?? 0;
        if (offset < -120) out.write(' ');
        i = numMatch.end;
        continue;
      }
      i++;
    }
    return out.toString();
  }

  String _decodePdfStringToken(String token) {
    final parsed = _parseValue(token, 0);
    return parsed.value is String ? parsed.value as String : '';
  }

  _Parsed _parseValue(String src, int start) {
    var i = start;
    while (i < src.length && _isWs(src.codeUnitAt(i))) {
      i++;
    }
    if (i >= src.length) return _Parsed(null, i);

    final ch = src.codeUnitAt(i);
    if (ch == 0x3c && i + 1 < src.length && src.codeUnitAt(i + 1) == 0x3c) {
      return _parseDict(src, i + 2);
    }
    if (ch == 0x3c) {
      return _parseHexString(src, i + 1);
    }
    if (ch == 0x28) {
      return _parseLiteralString(src, i + 1);
    }
    if (ch == 0x5b) {
      return _parseArray(src, i + 1);
    }
    if (ch == 0x2f) {
      final name = _parseName(src, i);
      return _Parsed(name.value, name.next);
    }
    if (src.startsWith('true', i) && _endsToken(src, i + 4)) {
      return _Parsed(true, i + 4);
    }
    if (src.startsWith('false', i) && _endsToken(src, i + 5)) {
      return _Parsed(false, i + 5);
    }
    if (src.startsWith('null', i) && _endsToken(src, i + 4)) {
      return _Parsed(null, i + 4);
    }

    final numMatch = RegExp(r'[+\-]?\d+(?:\.\d+)?').matchAsPrefix(src, i);
    if (numMatch != null) {
      final afterNum = numMatch.end;
      final ref = RegExp(r'\s+(\d+)\s+R').matchAsPrefix(src, afterNum);
      if (ref != null) {
        return _Parsed(
          _PdfRef('${numMatch.group(0)} ${ref.group(1)}'),
          afterNum + ref.end - afterNum,
        );
      }
      final raw = numMatch.group(0)!;
      if (raw.contains('.')) {
        return _Parsed(double.tryParse(raw) ?? raw, afterNum);
      }
      return _Parsed(int.tryParse(raw) ?? raw, afterNum);
    }

    return _Parsed(null, i + 1);
  }

  _Parsed _parseDict(String src, int start) {
    final dict = <String, dynamic>{};
    var i = start;
    while (i < src.length) {
      while (i < src.length && _isWs(src.codeUnitAt(i))) {
        i++;
      }
      if (i + 1 < src.length &&
          src.codeUnitAt(i) == 0x3e &&
          src.codeUnitAt(i + 1) == 0x3e) {
        return _Parsed(dict, i + 2);
      }
      if (i >= src.length || src.codeUnitAt(i) != 0x2f) {
        i++;
        continue;
      }
      final name = _parseName(src, i);
      final value = _parseValue(src, name.next);
      dict[name.value as String] = value.value;
      i = value.next;
    }
    return _Parsed(dict, i);
  }

  _Parsed _parseArray(String src, int start) {
    final list = <dynamic>[];
    var i = start;
    while (i < src.length) {
      while (i < src.length && _isWs(src.codeUnitAt(i))) {
        i++;
      }
      if (i < src.length && src.codeUnitAt(i) == 0x5d) {
        return _Parsed(list, i + 1);
      }
      final value = _parseValue(src, i);
      if (value.next == i) {
        i++;
        continue;
      }
      list.add(value.value);
      i = value.next;
    }
    return _Parsed(list, i);
  }

  _Parsed _parseName(String src, int start) {
    var i = start + 1;
    while (i < src.length) {
      final ch = src.codeUnitAt(i);
      if (_isWs(ch) ||
          ch == 0x2f ||
          ch == 0x28 ||
          ch == 0x29 ||
          ch == 0x3c ||
          ch == 0x3e ||
          ch == 0x5b ||
          ch == 0x5d ||
          ch == 0x7b ||
          ch == 0x7d ||
          ch == 0x25) {
        break;
      }
      i++;
    }
    return _Parsed('/${src.substring(start + 1, i)}', i);
  }

  _Parsed _parseLiteralString(String src, int start) {
    final out = StringBuffer();
    var i = start;
    var depth = 1;
    while (i < src.length && depth > 0) {
      final ch = src.codeUnitAt(i);
      if (ch == 0x5c && i + 1 < src.length) {
        i++;
        final esc = src.codeUnitAt(i);
        switch (esc) {
          case 0x6e:
            out.write('\n');
          case 0x72:
            out.write('\r');
          case 0x74:
            out.write('\t');
          case 0x62:
            out.write('\b');
          case 0x66:
            out.write('\f');
          case 0x28:
            out.write('(');
          case 0x29:
            out.write(')');
          case 0x5c:
            out.write('\\');
          default:
            if (esc >= 0x30 && esc <= 0x37) {
              var oct = String.fromCharCode(esc);
              var consumed = 1;
              while (consumed < 3 &&
                  i + consumed < src.length &&
                  src.codeUnitAt(i + consumed) >= 0x30 &&
                  src.codeUnitAt(i + consumed) <= 0x37) {
                oct += src[i + consumed];
                consumed++;
              }
              out.writeCharCode(int.parse(oct, radix: 8));
              i += consumed - 1;
            }
        }
        i++;
        continue;
      }
      if (ch == 0x28) depth++;
      if (ch == 0x29) {
        depth--;
        if (depth == 0) {
          i++;
          break;
        }
      }
      if (depth > 0) out.writeCharCode(ch);
      i++;
    }
    return _Parsed(_maybeUtf16(out.toString()), i);
  }

  _Parsed _parseHexString(String src, int start) {
    final end = src.indexOf('>', start);
    if (end < 0) return _Parsed('', src.length);
    var hex = src.substring(start, end).replaceAll(RegExp(r'\s'), '');
    if (hex.length.isOdd) hex += '0';
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return _Parsed(_maybeUtf16(latin1.decode(bytes, allowInvalid: true)), end + 1);
  }

  String _maybeUtf16(String raw) {
    if (raw.length >= 2 &&
        raw.codeUnitAt(0) == 0xfe &&
        raw.codeUnitAt(1) == 0xff) {
      final out = StringBuffer();
      for (var i = 2; i + 1 < raw.length; i += 2) {
        out.writeCharCode((raw.codeUnitAt(i) << 8) | raw.codeUnitAt(i + 1));
      }
      return out.toString();
    }
    return raw;
  }

  Uint8List _decodeAsciiHex(String src) {
    final hex = src.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    final padded = hex.length.isOdd ? '${hex}0' : hex;
    final out = Uint8List(padded.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(padded.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  Uint8List _decodeAscii85(String src) {
    var s = src.trim();
    if (s.startsWith('<~')) s = s.substring(2);
    if (s.endsWith('~>')) s = s.substring(0, s.length - 2);
    final out = <int>[];
    var tuple = 0;
    var count = 0;
    for (var i = 0; i < s.length; i++) {
      final ch = s.codeUnitAt(i);
      if (_isWs(ch)) continue;
      if (ch == 0x7a && count == 0) {
        out.addAll(const [0, 0, 0, 0]);
        continue;
      }
      if (ch < 33 || ch > 117) continue;
      tuple = tuple * 85 + (ch - 33);
      count++;
      if (count == 5) {
        out.add((tuple >> 24) & 0xff);
        out.add((tuple >> 16) & 0xff);
        out.add((tuple >> 8) & 0xff);
        out.add(tuple & 0xff);
        tuple = 0;
        count = 0;
      }
    }
    if (count > 0) {
      for (var i = count; i < 5; i++) {
        tuple = tuple * 85 + 84;
      }
      final bytes = [
        (tuple >> 24) & 0xff,
        (tuple >> 16) & 0xff,
        (tuple >> 8) & 0xff,
        tuple & 0xff,
      ];
      out.addAll(bytes.sublist(0, count - 1));
    }
    return Uint8List.fromList(out);
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  bool _isWs(int ch) =>
      ch == 0x00 || ch == 0x09 || ch == 0x0a || ch == 0x0c || ch == 0x0d || ch == 0x20;

  bool _endsToken(String src, int i) =>
      i >= src.length || _isWs(src.codeUnitAt(i)) || '/<>[](){}'.contains(src[i]);
}

class _PdfObject {
  final String id;
  final Map<String, dynamic> dict;
  final Uint8List? stream;
  final dynamic raw;

  _PdfObject({
    required this.id,
    required this.dict,
    required this.stream,
    required this.raw,
  });
}

class _PdfRef {
  final String id;
  _PdfRef(this.id);
}

class _Parsed {
  final dynamic value;
  final int next;
  _Parsed(this.value, this.next);
}
