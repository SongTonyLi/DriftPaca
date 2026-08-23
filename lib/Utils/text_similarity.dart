// Trigram-based text similarity — pure character n-gram overlap, no ML.
// Used by ResearchLedger to group near-duplicate search queries onto the
// same research sub-goal and to rank excerpts by relevance to a query.

/// Matches anything that is not a letter, a digit, or whitespace, in ANY
/// script. Unicode-aware on purpose: the previous form was `[^a-z0-9\s]`,
/// which treated every non-ASCII character as punctuation and deleted it.
///
/// That was catastrophic rather than merely lossy. A pure-CJK query
/// normalized to the empty string, so `_trigrams` returned `{''}` for all of
/// them and any two unrelated Chinese questions scored a perfect 1.0 —
/// "越南目前的人口是多少" and "法国的首都是哪座城市" among them. ResearchLedger
/// then grouped every non-Latin query onto one sub-goal and SearchAgent
/// refused every search after the first as a near-duplicate, so a Chinese,
/// Japanese, Korean, Arabic, Hebrew or Thai user got exactly one search per
/// turn no matter what they asked.
final _nonWordPattern = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);

final _whitespacePattern = RegExp(r'\s+');

/// Normalizes text for trigram comparison: lowercase, strip apostrophes and
/// periods (so "D.C." / "DC" and "won't" / "wont" compare identically),
/// collapse remaining punctuation to a space, collapse whitespace.
String _normalizeForTrigrams(String s) {
  final stripped = s.toLowerCase().replaceAll("'", '').replaceAll('.', '');
  final spaced = stripped.replaceAll(_nonWordPattern, ' ');
  return spaced.replaceAll(_whitespacePattern, ' ').trim();
}

/// The set of 3-character sliding-window trigrams for [s]. Strings shorter
/// than 3 characters after normalization (including the empty string)
/// become a single-element set containing the whole normalized string, so
/// short queries still compare meaningfully instead of producing a set no
/// other string can ever intersect.
Set<String> _trigrams(String s) {
  final normalized = _normalizeForTrigrams(s);
  if (normalized.length < 3) return {normalized};
  return {
    for (var i = 0; i <= normalized.length - 3; i++)
      normalized.substring(i, i + 3),
  };
}

/// Symmetric similarity in [0, 1]: how much two strings' trigram sets
/// overlap, regardless of length. Used to spot near-duplicate/refined
/// search queries.
double trigramJaccard(String a, String b) {
  final ta = _trigrams(a);
  final tb = _trigrams(b);
  final union = ta.union(tb);
  if (union.isEmpty) return 0.0;
  return ta.intersection(tb).length / union.length;
}

/// Asymmetric containment in [0, 1]: how much of [query]'s trigrams appear
/// in [text]. Unlike [trigramJaccard], a long [text] doesn't dilute the
/// score just because it has many trigrams of its own — only [query]'s own
/// trigram count is the denominator. Used to rank candidate excerpts/chunks
/// by relevance to a short query.
double queryCoverage(String query, String text) {
  final tq = _trigrams(query);
  final tt = _trigrams(text);
  if (tq.isEmpty) return 0.0;
  return tq.intersection(tt).length / tq.length;
}
