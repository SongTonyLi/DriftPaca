import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Extensions/matched_latex_block_syntax.dart';
import 'package:markdown/markdown.dart' as md;

void main() {
  List<md.Node> parse(String source) {
    final extensionSet = md.ExtensionSet(
      [
        ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
        const MatchedLatexBlockSyntax(),
      ],
      md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
    );
    final document = md.Document(extensionSet: extensionSet);
    return document.parseLines(source.split('\n'));
  }

  List<md.Element> latexElements(Iterable<md.Node> nodes) {
    final result = <md.Element>[];

    void visit(md.Node node) {
      if (node is md.Element) {
        if (node.tag == 'latex') result.add(node);
        node.children?.forEach(visit);
      }
    }

    nodes.forEach(visit);
    return result;
  }

  String textContent(Iterable<md.Node> nodes) {
    return nodes.map((node) => node.textContent).join('\n');
  }

  test('unmatched display opener remains literal with following prose', () {
    final nodes = parse(
      '\$\$\n'
      'x = 1\n'
      'Following explanation remains readable.',
    );

    expect(latexElements(nodes), isEmpty);
    expect(textContent(nodes), contains(r'$$'));
    expect(
      textContent(nodes),
      contains('Following explanation remains readable.'),
    );
  });

  test('single dollar line remains literal with following prose', () {
    final nodes = parse(
      'Currency symbol:\n'
      '\$\n'
      'Following explanation remains readable.',
    );

    expect(latexElements(nodes), isEmpty);
    expect(textContent(nodes), contains(r'$'));
    expect(
      textContent(nodes),
      contains('Following explanation remains readable.'),
    );
  });

  test('matched display block creates one display latex element', () {
    final nodes = parse(
      '\$\$\n'
      'x = 1\n'
      '\$\$\n'
      'After.',
    );

    final latex = latexElements(nodes);
    expect(latex, hasLength(1));
    expect(latex.single.attributes['MathStyle'], 'display');
    expect(latex.single.textContent, 'x = 1');
    expect(textContent(nodes), contains('After.'));
  });

  test('consecutive display blocks remain separate', () {
    final nodes = parse(
      '\$\$\n'
      'x = 1\n'
      '\$\$\n'
      'Between.\n'
      '\$\$\n'
      'y = 2\n'
      '\$\$',
    );

    final latex = latexElements(nodes);
    expect(latex, hasLength(2));
    expect(latex.map((element) => element.textContent), ['x = 1', 'y = 2']);
    expect(textContent(nodes), contains('Between.'));
  });
}
