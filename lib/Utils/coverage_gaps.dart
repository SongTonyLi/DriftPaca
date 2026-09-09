/// Most gaps the completeness gate is allowed to reopen research for.
///
/// Over-decomposition is this feature's main regression risk: a gate that
/// returns six "gaps" for a simple question manufactures the 8-round
/// over-searching that `8e0b64b` fixed. Capping is cheaper and more
/// predictable than trying to prompt the behavior away.
const maxCoverageGaps = 3;

/// Wrapping markdown emphasis and code ticks.
///
/// Stripped both BEFORE and AFTER [_bulletPrefix] because `*` is
/// simultaneously an emphasis marker and a bullet character, and the bullet
/// class can only eat one of them. A gate that replied `**NONE**` lost
/// exactly one asterisk to the bullet strip; the residue `*NONE**` failed
/// the verdict test, and the gate's own report that the draft was complete
/// was opened as a research gap literally named `*NONE**` — wiping the
/// finished answer off the user's screen to chase it.
///
/// Two passes, in that order, because the two strips protect each other:
/// `**NONE**` is resolved by the first pass alone, while `- **bold gap**`
/// needs the bullet strip in the middle (pass 1 takes the trailing `**`,
/// the bullet strip takes `- `, pass 2 takes the leading `**`).
final _wrappingEmphasis = RegExp(r'^[*_`~]+|[*_`~]+$');

final _bulletPrefix = RegExp(r'^\s*(?:[-*•]|\d+[.)])\s*');

/// The verdict alone on its line, give or take closing punctuation.
final _noneVerdict = RegExp(r'^none[.!?…]*$', caseSensitive: false);

/// The same verdict with the model's own justification appended —
/// `NONE — every part is addressed`.
///
/// A punctuation separator is REQUIRED, and a plain ASCII hyphen
/// additionally needs whitespace on one side, so that a genuine gap which
/// merely begins with the word ("none of the sources give the 2027 winner",
/// "none-the-less the college is missing") is still a gap. That direction
/// matters more than this one: wrongly reading a gap as the verdict costs
/// the user the research the gate exists to trigger, where wrongly reading
/// the verdict as a gap costs a round.
final _noneWithReason = RegExp(
  r'^none\s*(?:[:;,]|[–—]|\s-|-\s|[.!?]\s)\s*\S',
  caseSensitive: false,
);

/// Strips the decoration a model wraps around a line so the text underneath
/// can be judged — and, if it survives as a gap, shown to the user without
/// its markup.
String _cleanLine(String line) => line
    .trim()
    .replaceAll(_wrappingEmphasis, '')
    .replaceFirst(_bulletPrefix, '')
    .replaceAll(_wrappingEmphasis, '')
    .trim();

/// Whether [line] is the gate reporting the draft complete, rather than
/// naming something the draft missed.
bool _reportsComplete(String line) =>
    _noneVerdict.hasMatch(line) || _noneWithReason.hasMatch(line);

/// Parses the completeness gate's reply into the parts of the question the
/// drafted answer left unaddressed. Empty means complete.
///
/// Tolerant of the shapes a model actually emits — bare `NONE`, markdown
/// emphasis (`**NONE**`, `` `NONE` ``), hyphen or asterisk bullets,
/// numbered lists, stray blank lines — because the gate prompt asks for one
/// gap per line but nothing enforces it. A `NONE` anywhere in the reply
/// wins outright, whether it stands alone or the model justified it on the
/// same line: a model that says "NONE" and then explains itself is
/// reporting completeness, not listing a gap. The whole reply is scanned
/// for that verdict — [maxCoverageGaps] bounds what is RETURNED, never how
/// far the scan reads, so a NONE that arrives after the model's reasoning
/// still wins.
///
/// Every tolerance here leans the same way on purpose: nothing downstream
/// re-checks the shape of a gap (`SearchAgent` only trims it and opens it
/// as a ledger sub-goal), and a gate that invents gaps is worse than no
/// gate — it spends rounds and can talk a good answer into being rewritten.
///
/// Deliberately English-only: the parser keys on the literal "NONE", which
/// the gate prompt asks for in English regardless of the question's
/// language (see the CJK case in
/// test/integration/coverage_gate_live_test.dart). Matching non-English
/// negations here would widen exactly the direction this parser must not
/// widen — silently declaring an incomplete answer complete.
List<String> parseCoverageGaps(String raw) {
  final gaps = <String>[];
  for (final line in raw.split('\n')) {
    final stripped = _cleanLine(line);
    if (stripped.isEmpty) continue;
    if (_reportsComplete(stripped)) return const [];
    if (gaps.length < maxCoverageGaps) gaps.add(stripped);
  }
  return gaps;
}
