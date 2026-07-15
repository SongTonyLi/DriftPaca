import 'package:markdown/markdown.dart' as md;

class MatchedLatexBlockSyntax extends md.BlockSyntax {
  const MatchedLatexBlockSyntax();

  static final RegExp _delimiter = RegExp(r'^[ \t]*\$\$[ \t]*$');

  @override
  RegExp get pattern => _delimiter;

  @override
  bool canParse(md.BlockParser parser) {
    if (!_delimiter.hasMatch(parser.current.content)) return false;

    var offset = 1;
    while (true) {
      final line = parser.peek(offset);
      if (line == null) return false;
      if (_delimiter.hasMatch(line.content)) return true;
      offset++;
    }
  }

  @override
  md.Node parse(md.BlockParser parser) {
    parser.advance();
    final lines = <String>[];

    while (!parser.isDone && !_delimiter.hasMatch(parser.current.content)) {
      lines.add(parser.current.content);
      parser.advance();
    }

    if (!parser.isDone) parser.advance();

    final latex = md.Element.text('latex', lines.join('\n').trim());
    latex.attributes['MathStyle'] = 'display';
    return md.Element('p', [latex]);
  }
}
