/// Most gaps the completeness gate is allowed to reopen research for.
///
/// Over-decomposition is this feature's main regression risk: a gate that
/// returns six "gaps" for a simple question manufactures the 8-round
/// over-searching that `8e0b64b` fixed. Capping is cheaper and more
/// predictable than trying to prompt the behavior away.
const maxCoverageGaps = 3;

final _bulletPrefix = RegExp(r'^\s*(?:[-*•]|\d+[.)])\s*');
final _nonePattern = RegExp(r'^none[.!]?$', caseSensitive: false);

/// Parses the completeness gate's reply into the parts of the question the
/// drafted answer left unaddressed. Empty means complete.
///
/// Tolerant of the shapes a model actually emits — bare `NONE`, hyphen or
/// asterisk bullets, numbered lists, stray blank lines — because the gate
/// prompt asks for one gap per line but nothing enforces it. A `NONE`
/// anywhere in the reply wins outright: a model that says "NONE" and then
/// explains itself is reporting completeness, not listing a gap.
List<String> parseCoverageGaps(String raw) {
  final gaps = <String>[];
  for (final line in raw.split('\n')) {
    final stripped = line.replaceFirst(_bulletPrefix, '').trim();
    if (stripped.isEmpty) continue;
    if (_nonePattern.hasMatch(stripped)) return const [];
    gaps.add(stripped);
    if (gaps.length == maxCoverageGaps) break;
  }
  return gaps;
}
