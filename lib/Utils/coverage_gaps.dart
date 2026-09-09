/// Most gaps the completeness gate is allowed to reopen research for.
///
/// Over-decomposition is this feature's main regression risk: a gate that
/// returns six "gaps" for a simple question manufactures the 8-round
/// over-searching that `8e0b64b` fixed. Capping is cheaper and more
/// predictable than trying to prompt the behavior away.
const maxCoverageGaps = 3;

/// Markdown emphasis and code ticks, wherever in a line they appear.
final _emphasis = RegExp(r'[*_`~]');

/// An emphasis run sitting at the very start or the very end of a line.
final _wrappingEmphasis = RegExp(r'^[*_`~]+|[*_`~]+$');

/// A list bullet or number prefix.
///
/// The `*` alternative refuses a DOUBLED asterisk: `*` is simultaneously a
/// bullet character and an emphasis marker, but a bullet is never written
/// `**`, so a doubled one opens bold and belongs to [_unwrapEmphasis]
/// instead. Letting the bullet class eat one asterisk off `**NONE**` is how
/// the gate's own report that the draft was complete became a research gap
/// named `*NONE**`.
final _bulletPrefix = RegExp(r'^\s*(?:[-•]|\*(?!\*)|\d+[.)])\s*');

/// Removes an emphasis or code-tick run that wraps [text] — and only then.
///
/// A line the model decorated end to end (`**the 2027 winner**`) is shown to
/// the user, and restated to the model, as the gap rather than as its
/// markup. A line that merely CONTAINS emphasis (`**who won** and **when**`,
/// `**Winner** of the 2027 election`) keeps every marker it came with:
/// removing only the outermost half of each pair would strand `**` in the
/// middle of a ledger checklist item, which renders worse than the markdown
/// it was built from. The leftover test is what tells the two apart — if
/// anything emphasis-shaped survives the strip, the run was not a wrapper
/// and nothing should have been removed.
String _unwrapEmphasis(String text) {
  final unwrapped = text.replaceAll(_wrappingEmphasis, '');
  return _emphasis.hasMatch(unwrapped) ? text : unwrapped;
}

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
///
/// What the separator costs, named rather than left to be discovered: a gap
/// PHRASED as a negative sentence — `None: the population is missing`,
/// `none, the population of Delhi is missing`, `none — of the sources give a
/// date` — reads as the verdict and is swallowed. The gate prompt asks for
/// "the missing thing, one per line, with no other commentary"
/// (chat_provider.dart:90), so a real gap arrives as `the population of
/// Delhi`, not as a sentence opening with a negation and a colon. If that
/// ever stops holding, narrow THIS pattern — never [_reportsComplete]'s
/// tolerance of decoration, which cannot change a gap into a verdict.
final _noneWithReason = RegExp(
  r'^none\s*(?:[:;,]|[–—]|\s-|-\s|[.!?]\s)\s*\S',
  caseSensitive: false,
);

/// Strips the decoration a model wraps around a line, so the text underneath
/// is what the user is shown and what the model is asked to close.
String _cleanLine(String line) {
  // Emphasis is unwrapped on BOTH sides of the bullet strip, because the two
  // decorations nest either way round: `**NONE**` is resolved before the
  // bullet strip ever sees it, `- **a gap**` needs the bullet gone first,
  // and `**- a gap**` needs both passes.
  final unbulleted =
      _unwrapEmphasis(line.trim()).replaceFirst(_bulletPrefix, '');
  return _unwrapEmphasis(unbulleted).trim();
}

/// Whether [line] is the gate reporting the draft complete, rather than
/// naming something the draft missed.
///
/// Judged on a copy with every emphasis and code-tick character removed, NOT
/// on the line as it will be displayed. Decoration must never decide the
/// verdict, and [_cleanLine] alone cannot promise that: it can only unwrap a
/// run that sits at a line's very edge, so the ordinary markdown spelling
/// `**NONE**.` — the full stop OUTSIDE the bold — strands `**` in the middle
/// of the string, where both anchored patterns above reject it. That is the
/// original `*NONE**` failure one full stop away from the `**NONE.**` this
/// parser already read correctly, and it ends the same way: "the draft is
/// complete" opens a research gap, blanks the finished answer on the user's
/// screen (SearchAgent fires `onResetContent`, where ChatProvider clears
/// `streamingMessage.content`), and spends a corrective round rewriting it.
/// The same stranding hits every justified-and-emphasised verdict — `**NONE**
/// — every part is addressed`, `` `NONE` - all covered `` — which is exactly
/// what a model that bolds its verdict is likely to write.
///
/// Safe in the dangerous direction because the guard is the SEPARATOR after
/// the word, not the characters around it: `none of the sources…`,
/// `nonetheless…` and `none-the-less…` contain no emphasis characters at
/// all, so removing them cannot turn a genuine gap into a verdict.
bool _reportsComplete(String line) {
  final undecorated = line.replaceAll(_emphasis, '').trim();
  return _noneVerdict.hasMatch(undecorated) ||
      _noneWithReason.hasMatch(undecorated);
}

/// Parses the completeness gate's reply into the parts of the question the
/// drafted answer left unaddressed. Empty means complete.
///
/// Tolerant of the shapes a model actually emits — bare `NONE`, hyphen or
/// asterisk bullets, numbered lists, stray blank lines — because the gate
/// prompt asks for one gap per line but nothing enforces it. A `NONE`
/// anywhere in the reply wins outright, in any combination of: markdown
/// emphasis or code ticks around it, wherever the model closes them
/// (`**NONE**`, `**NONE.**`, `**NONE**.`, `` `NONE` ``); closing
/// punctuation; a justification on the same line (`_NONE_ — every part is
/// addressed`). A model that says NONE and then explains itself is reporting
/// completeness, not listing a gap, and no amount of decoration changes
/// that — [_reportsComplete] judges the line with its markup removed. The
/// whole reply is scanned for that verdict too: [maxCoverageGaps] bounds
/// what is RETURNED, never how far the scan reads, so a NONE that arrives
/// after the model's reasoning still wins.
///
/// Every tolerance here leans the same way on purpose: nothing downstream
/// re-checks the shape of a gap (`SearchAgent` only trims it and opens it
/// as a ledger sub-goal), and a gate that invents gaps is worse than no
/// gate — it spends rounds and can talk a good answer into being rewritten.
/// The one tolerance that leans the other way is named on [_noneWithReason].
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
