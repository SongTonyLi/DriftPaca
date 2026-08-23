// Trigram-based text similarity — pure character n-gram overlap, no ML.
// Used by ResearchLedger to group near-duplicate search queries onto the
// same research sub-goal and to rank excerpts by relevance to a query.

/// Normalizes text for trigram comparison: lowercase, strip apostrophes and
/// periods (so "D.C." / "DC" and "won't" / "wont" compare identically),
/// collapse remaining punctuation to a space, collapse whitespace.
String _normalizeForTrigrams(String s) {
  final stripped = s.toLowerCase().replaceAll("'", '').replaceAll('.', '');
  final spaced = stripped.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  return spaced.replaceAll(RegExp(r'\s+'), ' ').trim();
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
