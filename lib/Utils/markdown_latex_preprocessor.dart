String preprocessMarkdownLatex(String source) {
  return _MarkdownLatexPreprocessor(source).process();
}

bool looksLikeCurrencyProse(String content) {
  if (!_MarkdownLatexPreprocessor._currencyLeadPattern.hasMatch(content)) {
    return false;
  }
  if (content.contains(r'\text')) return false;
  if (!_MarkdownLatexPreprocessor._proseLikePunctuationPattern.hasMatch(content)) {
    return false;
  }
  return _MarkdownLatexPreprocessor._cjkIdeographPattern.hasMatch(content) ||
      _MarkdownLatexPreprocessor._multiLetterWordPattern.hasMatch(content);
}

class _MarkdownLatexPreprocessor {
  _MarkdownLatexPreprocessor(this.source);

  final String source;

  static final RegExp _fencePattern = RegExp(
    r'^((?: {0,3}>[ \t]?)* {0,3})(`{3,}|~{3,})(.*)$',
  );
  static final RegExp _latexTagPattern = RegExp(r'\\tag(\*)?\s*\{([^{}]*)\}');
  static final RegExp _currencyLeadPattern = RegExp(r'^\s*[\d,.]');
  static final RegExp _latexOperatorPattern = RegExp(r'[+=^_\\{}<>]|(?<!\*)\*(?!\*)');
  static final RegExp _approxTildePattern = RegExp(r'(?<!~)~(?!~)(?=[\$€£¥\d])');
  static final RegExp _proseLikePunctuationPattern = RegExp(r'[,;:，；：、。（）「」]');
  static final RegExp _cjkIdeographPattern = RegExp(r'[\u4E00-\u9FFF]');
  static final RegExp _multiLetterWordPattern = RegExp(r'[A-Za-z]{2,}');
  static final RegExp _afterStarsPattern = RegExp(r'(\*+)(?!\*)(?=\p{P})', unicode: true);
  static final RegExp _beforeStarsPattern = RegExp(r'(?<=\p{P})(?<!\*)(\*+)', unicode: true);
  static final RegExp _tableDelimiterCellPattern = RegExp(r'^:?-{3,}:?$');

  String process() {
    final lines = source.split('\n');
    final output = <String>[];
    final ordinary = <String>[];

    void flushOrdinary() {
      if (ordinary.isEmpty) return;
      output.addAll(_processText(ordinary.join('\n')).split('\n'));
      ordinary.clear();
    }

    var index = 0;
    while (index < lines.length) {
      final opening = _fencePattern.firstMatch(lines[index]);
      if (opening != null) {
        final close = _findClosingFence(lines, index, opening);
        if (close == null) {
          flushOrdinary();
          output.addAll(lines.sublist(index));
          break;
        }

        final info = opening[3]!.trim();
        final language = info.isEmpty ? '' : info.split(RegExp(r'\s+')).first.toLowerCase();
        final prefix = opening[1]!;

        if (prefix.trim().isNotEmpty || (language != 'markdown' && language != 'latex' && language != 'math')) {
          flushOrdinary();
          output.addAll(lines.sublist(index, close + 1));
          index = close + 1;
          continue;
        }

        flushOrdinary();
        final body = lines.sublist(index + 1, close).join('\n');
        if (language == 'markdown') {
          output.addAll('${preprocessMarkdownLatex(body)}\n'.split('\n'));
        } else {
          output.addAll(_normalizeMathFence(body).split('\n'));
        }
        index = close + 1;
        continue;
      }

      if (_isIndentedCodeLine(lines[index])) {
        flushOrdinary();
        output.add(lines[index]);
      } else {
        ordinary.add(lines[index]);
      }
      index++;
    }

    flushOrdinary();
    return output.join('\n');
  }

  int? _findClosingFence(
    List<String> lines,
    int openingIndex,
    RegExpMatch opening,
  ) {
    final prefix = opening[1]!;
    final marker = opening[2]!;
    final markerChar = marker[0];

    for (var index = openingIndex + 1; index < lines.length; index++) {
      final match = _fencePattern.firstMatch(lines[index]);
      if (match == null || match[1] != prefix) continue;
      final candidate = match[2]!;
      if (candidate[0] == markerChar && candidate.length >= marker.length && match[3]!.trim().isEmpty) {
        return index;
      }
    }
    return null;
  }

  bool _isIndentedCodeLine(String line) {
    return line.startsWith('\t') || RegExp(r'^ {4}').hasMatch(line);
  }

  String _normalizeMathFence(String body) {
    final trailingNewline = body.isEmpty ? '' : '\n';
    final trimmed = body.trim();
    if (trimmed.startsWith(r'\(') && trimmed.endsWith(r'\)')) {
      final inner = trimmed.substring(2, trimmed.length - 2);
      return '\$${_rewriteLatexTags(inner)}\$$trailingNewline';
    }
    if (trimmed.startsWith(r'\[') && trimmed.endsWith(r'\]')) {
      final inner = trimmed.substring(2, trimmed.length - 2);
      return '\$\$${_rewriteLatexTags(inner)}\$\$$trailingNewline';
    }
    if (_isCompleteMathExpression(trimmed)) {
      return '$trimmed$trailingNewline';
    }
    return '\$\$\n${_rewriteLatexTags(trimmed)}\n\$\$';
  }

  bool _isCompleteMathExpression(String text) {
    if (text.length < 2) return false;
    if (text.startsWith(r'$$') && text.endsWith(r'$$') && text.length > 4) {
      return true;
    }
    if (text.startsWith(r'$') && text.endsWith(r'$') && text.length > 2) {
      return true;
    }
    if (text.startsWith(r'\(') && text.endsWith(r'\)')) return true;
    if (text.startsWith(r'\[') && text.endsWith(r'\]')) return true;
    return false;
  }

  String _processText(String text) {
    final protectedCode = _protectInlineCode(text);
    final protectedLinks = _protectMarkdownLinkDestinations(protectedCode.text);
    var result = _normalizeLatexDelimiters(protectedLinks.text);
    result = _escapeUnmatchedDisplayDelimiterLines(result);
    result = result.replaceAll(_approxTildePattern, r'\~');
    result = _processDollars(result);
    result = _escapeTableMathPipes(result);
    result = _fixEmphasisFlanking(result);
    return protectedCode.restore(protectedLinks.restore(result));
  }

  _ProtectedText _protectInlineCode(String text) {
    var tokenPrefix = '\u{E000}markdown-code-';
    while (text.contains(tokenPrefix)) {
      tokenPrefix = '\u{E000}$tokenPrefix';
    }

    final values = <String>[];
    final output = StringBuffer();
    var index = 0;

    while (index < text.length) {
      if (text[index] != '`' || _isEscaped(text, index)) {
        output.write(text[index]);
        index++;
        continue;
      }

      final runLength = _countRun(text, index, '`');
      final close = _findMatchingBacktickRun(text, index + runLength, runLength);
      if (close == null) {
        final value = text.substring(index);
        final token = '$tokenPrefix${values.length}\u{E001}';
        values.add(value);
        output.write(token);
        break;
      }

      final end = close + runLength;
      final value = text.substring(index, end);
      final inner = text.substring(index + runLength, close);
      if (_containsOnlyMarkdownLinks(inner)) {
        output.write(inner);
      } else {
        final token = '$tokenPrefix${values.length}\u{E001}';
        values.add(value);
        output.write(token);
      }
      index = end;
    }

    return _ProtectedText(output.toString(), tokenPrefix, values);
  }

  _ProtectedText _protectMarkdownLinkDestinations(String text) {
    var tokenPrefix = '\u{E002}markdown-link-';
    while (text.contains(tokenPrefix)) {
      tokenPrefix = '\u{E002}$tokenPrefix';
    }

    final values = <String>[];
    final output = StringBuffer();
    var index = 0;

    while (index < text.length) {
      if (text[index] != '[' || _isEscaped(text, index)) {
        output.write(text[index]);
        index++;
        continue;
      }

      final labelEnd = _findBalancedEnd(text, index, '[', ']');
      if (labelEnd == null || labelEnd + 1 >= text.length || text[labelEnd + 1] != '(') {
        output.write(text[index]);
        index++;
        continue;
      }

      final destinationEnd = _findBalancedEnd(text, labelEnd + 1, '(', ')');
      if (destinationEnd == null) {
        output.write(text[index]);
        index++;
        continue;
      }

      final isDollarWrapped =
          index > 0 && text[index - 1] == r'$' && destinationEnd + 1 < text.length && text[destinationEnd + 1] == r'$';
      if (isDollarWrapped) {
        output.write(text.substring(index, destinationEnd + 1));
        index = destinationEnd + 1;
        continue;
      }

      output.write(text.substring(index, labelEnd + 1));
      final value = text.substring(labelEnd + 1, destinationEnd + 1);
      final token = '$tokenPrefix${values.length}\u{E001}';
      values.add(value);
      output.write(token);
      index = destinationEnd + 1;
    }

    return _ProtectedText(output.toString(), tokenPrefix, values);
  }

  int? _findMatchingBacktickRun(String text, int start, int runLength) {
    var index = start;
    while (index < text.length) {
      if (text[index] != '`') {
        index++;
        continue;
      }
      final candidateLength = _countRun(text, index, '`');
      if (candidateLength == runLength) return index;
      index += candidateLength;
    }
    return null;
  }

  String _normalizeLatexDelimiters(String text) {
    final output = StringBuffer();
    var index = 0;

    while (index < text.length) {
      if (text.startsWith(r'\[', index)) {
        final close = text.indexOf(r'\]', index + 2);
        if (close >= 0) {
          final inner = text.substring(index + 2, close);
          if (inner.contains('\n')) {
            output.write('\n\n\$\$\n${_rewriteLatexTags(inner.trim())}\n\$\$\n\n');
          } else {
            output.write('\$\$${_rewriteLatexTags(inner)}\$\$');
          }
          index = close + 2;
          continue;
        }
      }

      if (text.startsWith(r'\(', index)) {
        final close = text.indexOf(r'\)', index + 2);
        if (close >= 0 && !text.substring(index + 2, close).contains('\n')) {
          final inner = text.substring(index + 2, close);
          output.write('\$${_rewriteLatexTags(inner)}\$');
          index = close + 2;
          continue;
        }
      }

      output.write(text[index]);
      index++;
    }

    return output.toString();
  }

  String _escapeUnmatchedDisplayDelimiterLines(String text) {
    final lines = text.split('\n');
    final delimiterIndexesByPrefix = <String, List<int>>{};

    for (var index = 0; index < lines.length; index++) {
      final line = _containerLine(lines[index]);
      if (!RegExp(r'^[ \t]*\$\$[ \t]*$').hasMatch(line.content)) {
        continue;
      }
      delimiterIndexesByPrefix.putIfAbsent(line.prefix, () => []).add(index);
    }

    for (final indexes in delimiterIndexesByPrefix.values) {
      if (indexes.length.isEven) continue;
      final index = indexes.last;
      lines[index] = lines[index].replaceFirst(r'$$', r'\$\$');
    }

    return lines.join('\n');
  }

  String _processDollars(String text) {
    final output = StringBuffer();
    var index = 0;

    while (index < text.length) {
      if (text[index] != r'$' || _isEscaped(text, index)) {
        output.write(text[index]);
        index++;
        continue;
      }

      if (text.startsWith(r'$$', index)) {
        if (_isBareDisplayDelimiterAt(text, index)) {
          output.write(r'$$');
          index += 2;
          continue;
        }
        final close = _findUnescaped(text, r'$$', index + 2);
        if (close >= 0) {
          final inner = text.substring(index + 2, close);
          output.write('\$\$${_rewriteLatexTags(inner)}\$\$');
          index = close + 2;
          continue;
        }
        output.write(r'$$');
        index += 2;
        continue;
      }

      final wrappedLinkEnd = _findDollarWrappedLinksEnd(text, index + 1);
      if (wrappedLinkEnd != null) {
        output.write(text.substring(index + 1, wrappedLinkEnd));
        index = wrappedLinkEnd + 1;
        continue;
      }

      final close = _findUnescaped(text, r'$', index + 1);
      final candidate = close < 0 ? text.substring(index + 1) : text.substring(index + 1, close);

      if (_currencyLeadPattern.hasMatch(candidate)) {
        if (close < 0 || _looksLikeCurrency(candidate)) {
          output.write(r'\$');
          index++;
          continue;
        }
      }

      if (close >= 0) {
        output.write('\$${_rewriteLatexTags(candidate)}\$');
        index = close + 1;
        continue;
      }

      output.write(r'$');
      index++;
    }

    return output.toString();
  }

  bool _isBareDisplayDelimiterAt(String text, int index) {
    final lineStart = index == 0 ? 0 : text.lastIndexOf('\n', index - 1) + 1;
    final nextNewline = text.indexOf('\n', index);
    final lineEnd = nextNewline < 0 ? text.length : nextNewline;
    final line = _containerLine(text.substring(lineStart, lineEnd));
    return line.content.trim() == r'$$';
  }

  bool _looksLikeCurrency(String content) {
    final stripped = content.replaceAll('**', '').replaceAll(r'\~', '').trim();
    if (!_latexOperatorPattern.hasMatch(stripped)) return true;
    return looksLikeCurrencyProse(content);
  }

  String _rewriteLatexTags(String text) {
    return text.replaceAllMapped(_latexTagPattern, (match) {
      final body = match[2] ?? '';
      return match[1] != null ? '\\quad{$body}' : '\\quad($body)';
    });
  }

  int? _findDollarWrappedLinksEnd(String text, int start) {
    var index = start;
    var linkCount = 0;

    while (index < text.length && text[index] == '[') {
      final end = _findMarkdownLinkEnd(text, index);
      if (end == null) return null;
      linkCount++;
      index = end;
    }

    if (linkCount == 0 || index >= text.length || text[index] != r'$') {
      return null;
    }
    return index;
  }

  bool _containsOnlyMarkdownLinks(String text) {
    if (text.isEmpty) return false;
    var index = 0;
    while (index < text.length) {
      if (text[index] != '[') return false;
      final end = _findMarkdownLinkEnd(text, index);
      if (end == null) return false;
      index = end;
    }
    return true;
  }

  int? _findMarkdownLinkEnd(String text, int start) {
    final labelEnd = _findBalancedEnd(text, start, '[', ']');
    if (labelEnd == null || labelEnd + 1 >= text.length || text[labelEnd + 1] != '(') {
      return null;
    }
    final destinationEnd = _findBalancedEnd(text, labelEnd + 1, '(', ')');
    return destinationEnd == null ? null : destinationEnd + 1;
  }

  int? _findBalancedEnd(
    String text,
    int start,
    String open,
    String close,
  ) {
    if (start >= text.length || text[start] != open) return null;
    var depth = 0;
    for (var index = start; index < text.length; index++) {
      if (_isEscaped(text, index)) continue;
      if (text[index] == open) {
        depth++;
      } else if (text[index] == close) {
        depth--;
        if (depth == 0) return index;
      }
    }
    return null;
  }

  String _escapeTableMathPipes(String text) {
    final lines = text.split('\n');
    final tableRows = <int>{};

    for (var index = 1; index < lines.length; index++) {
      final delimiter = _containerLine(lines[index]);
      final header = _containerLine(lines[index - 1]);
      if (delimiter.prefix != header.prefix || !_isTableDelimiter(delimiter.content) || !header.content.contains('|')) {
        continue;
      }

      tableRows
        ..add(index - 1)
        ..add(index);
      for (var row = index + 1; row < lines.length; row++) {
        final candidate = _containerLine(lines[row]);
        if (candidate.prefix != delimiter.prefix ||
            candidate.content.trim().isEmpty ||
            !candidate.content.contains('|')) {
          break;
        }
        tableRows.add(row);
      }
    }

    for (final index in tableRows) {
      final line = _containerLine(lines[index]);
      lines[index] = '${line.prefix}${_escapeMathPipes(line.content)}';
    }
    return lines.join('\n');
  }

  bool _isTableDelimiter(String content) {
    var trimmed = content.trim();
    if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
    if (trimmed.endsWith('|')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    final cells = trimmed.split('|').map((cell) => cell.trim()).toList();
    return cells.isNotEmpty && cells.every(_tableDelimiterCellPattern.hasMatch);
  }

  _ContainerLine _containerLine(String line) {
    final match = RegExp(r'^((?: {0,3}>[ \t]?)*)(.*)$').firstMatch(line)!;
    return _ContainerLine(match[1]!, match[2]!);
  }

  String _escapeMathPipes(String line) {
    final output = StringBuffer();
    var index = 0;

    while (index < line.length) {
      if (line[index] != r'$' || _isEscaped(line, index)) {
        output.write(line[index]);
        index++;
        continue;
      }

      final delimiterLength = line.startsWith(r'$$', index) ? 2 : 1;
      final delimiter = delimiterLength == 2 ? r'$$' : r'$';
      final close = _findUnescaped(line, delimiter, index + delimiterLength);
      if (close < 0) {
        output.write(line.substring(index));
        break;
      }

      final inner = line.substring(index + delimiterLength, close);
      output
        ..write(delimiter)
        ..write(_replaceRawPipes(inner))
        ..write(delimiter);
      index = close + delimiterLength;
    }

    return output.toString();
  }

  String _replaceRawPipes(String text) {
    final output = StringBuffer();
    var index = 0;
    while (index < text.length) {
      if (text[index] != '|' || _isEscaped(text, index)) {
        output.write(text[index]);
        index++;
        continue;
      }
      if (index + 1 < text.length && text[index + 1] == '|') {
        output.write(r'\Vert ');
        index += 2;
      } else {
        output.write(r'\vert ');
        index++;
      }
    }
    return output.toString();
  }

  String _fixEmphasisFlanking(String text) {
    var result = text.replaceAllMapped(
      _afterStarsPattern,
      (match) => '${match[1]}\u200B',
    );
    result = result.replaceAllMapped(
      _beforeStarsPattern,
      (match) => '\u200B${match[1]}',
    );
    return result;
  }

  int _findUnescaped(String text, String value, int start) {
    var index = start;
    while (index <= text.length - value.length) {
      final found = text.indexOf(value, index);
      if (found < 0) return -1;
      if (!_isEscaped(text, found)) return found;
      index = found + value.length;
    }
    return -1;
  }

  bool _isEscaped(String text, int index) {
    var slashCount = 0;
    for (var cursor = index - 1; cursor >= 0 && text[cursor] == r'\'; cursor--) {
      slashCount++;
    }
    return slashCount.isOdd;
  }

  int _countRun(String text, int start, String character) {
    var end = start;
    while (end < text.length && text[end] == character) {
      end++;
    }
    return end - start;
  }
}

class _ProtectedText {
  const _ProtectedText(this.text, this.tokenPrefix, this.values);

  final String text;
  final String tokenPrefix;
  final List<String> values;

  String restore(String source) {
    var result = source;
    for (var index = 0; index < values.length; index++) {
      result = result.replaceAll(
        '$tokenPrefix$index\u{E001}',
        values[index],
      );
    }
    return result;
  }
}

class _ContainerLine {
  const _ContainerLine(this.prefix, this.content);

  final String prefix;
  final String content;
}
