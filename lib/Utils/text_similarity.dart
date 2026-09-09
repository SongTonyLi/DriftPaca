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

/// The distinct digit-runs in [text] — the years, versions and quarters
/// that pick out WHICH instance of a question is being asked ("2024",
/// "18", "1" in "Q1"). Used by ResearchLedger to tell "the same question
/// about a different year" apart from a rewording of one question, which
/// [trigramJaccard] alone cannot do: it measures string SHAPE, and
/// swapping one token changes almost no trigrams, so "US inflation rate
/// 2023" scores 0.905 against "...2024" — higher than any real paraphrase
/// pair the near-duplicate threshold was calibrated on, which topped out
/// at 0.69.
Set<String> numericTokens(String text) =>
    {for (final m in _digitRun.allMatches(text)) m[0]!};

final _digitRun = RegExp(r'\d+');

/// Strips the marks that sit INSIDE a word — apostrophes and periods — so
/// "Vietnam's" tokenizes as one token and "D.C." as "DC". The same rule
/// [_normalizeForTrigrams] applies, widened to the curly apostrophe a
/// phone keyboard produces, so a name typed on a phone still matches the
/// straight-quoted form a model writes back.
String _stripWordMarks(String s) =>
    s.replaceAll("'", '').replaceAll('\u2019', '').replaceAll('.', '');

final _wordRun = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// The word tokens of [text] in order, case preserved. The single
/// tokenizer behind both [wordTokens] and [properNounTokens]: the two
/// sides of an instance comparison must normalize identically, or a name
/// the user wrote as "Vietnam's" would never match the "vietnams" a model
/// puts in its query and the split they feed would silently stop firing.
List<String> _tokens(String text) =>
    [for (final m in _wordRun.allMatches(_stripWordMarks(text))) m[0]!];

/// The distinct lowercased word tokens of [text]. This is the QUERY side
/// of ResearchLedger's instance check: a model writes "tokyo" for a city
/// the user typed as "Tokyo", so this side is case-blind and applies none
/// of [properNounTokens]' capitalisation rules — it only asks which of the
/// names the user already established appear here.
Set<String> wordTokens(String text) =>
    {for (final t in _tokens(text)) t.toLowerCase()};

/// Sentence boundaries for [properNounTokens]: past one of these, a
/// capital is orthography rather than evidence of a name.
final _sentenceBreak = RegExp(r'[.!?\n]+');

/// Ends a run of capitalised words WITHIN a sentence — every punctuation
/// mark that is not part of a word (comma, dash, colon, quote, paren).
/// Apostrophes are excluded because they sit inside names ("Côte
/// d'Ivoire") and [_stripWordMarks] removes them anyway.
final _segmentBreak = RegExp(r"[^\p{L}\p{N}\s'\u2019]+", unicode: true);

/// Whether [token] is capitalised in a way that could name something: at
/// least two characters, starting with a character that HAS a distinct
/// lowercase form and is not in it. Digits and uncased scripts are false
/// by construction, which is what keeps a CJK, Arabic, Hebrew or Thai
/// question out of [properNounTokens] without a script list to maintain.
bool _isCapitalised(String token) {
  if (token.length < 2) return false;
  final c = token[0];
  return c.toUpperCase() == c && c.toLowerCase() != c;
}

/// The capitalised words the user used to NAME the several things they
/// asked about — the entity counterpart of [numericTokens], and empty
/// unless the question really does list two or more names.
///
/// This exists because [trigramJaccard] measures string SHAPE. Four
/// queries built from one template ("current population of ⟨city⟩")
/// differ by a single token, so they score 0.58–0.67 against each other —
/// far above the ledger's grouping threshold — and file as ONE sub-goal.
/// [numericTokens] already overrides that for instances a user pins with
/// digits (years, versions, quarters), but a question naming four cities
/// has no digits anywhere in it, so it had no override at all and lost
/// three quarters of itself: the four lookups shared one search budget,
/// no round after the first covered new ground, and the single checklist
/// line named one city while citing every city's sources.
///
/// Two rules keep this from over-firing, and they are the whole safety
/// argument:
///
///   * adjacent capitalised tokens merge into ONE run, so "São Paulo" is
///     a single name and a Title Case or SHOUTED message is one run from
///     end to end;
///   * fewer than two DISTINCT runs yields nothing.
///
/// Together they mean capitalisation counts as instance-naming only when
/// the user actually listed several names. A lone capitalised phrase is
/// the question's SUBJECT ("What is Vietnam GDP?"), not one of a set, and
/// splitting on a subject that some queries name and others don't would
/// fragment one question into a sub-goal per rewording — precisely the
/// model-thrash failure the instance override exists to STOP (see
/// ResearchLedger._isDifferentRequestedInstance). Over-splitting is the
/// dangerous direction: every extra sub-goal carries a fresh per-sub-goal
/// budget and makes its round look like it broadened coverage, so a
/// wrongly-split run never trips the stall counter and burns its whole
/// search budget. Every ambiguous case therefore fails closed, by
/// grouping.
///
/// The first token of each sentence is skipped for the same reason:
/// "What", "Give" and "Compare" are capitalised by position, not because
/// they name anything.
///
/// Deliberately accepted under-splits, each of which falls back to the
/// grouping behaviour that was there before rather than to a wrong split:
///
///   * a name that opens a sentence is dropped ("Tokyo or Delhi — which
///     is bigger?" yields only Delhi);
///   * a period inside a name breaks the sentence, so what follows it
///     reads as sentence-initial ("Washington D.C. and Boston");
///   * a question written in an uncased script (CJK, Arabic, Hebrew,
///     Thai) yields nothing, since no character in it is uppercase —
///     those runs keep exactly the grouping they have today.
Set<String> properNounTokens(String text) =>
    _namesFromRuns(_capitalisedRuns(text, skipOpeningWord: true));

/// The names in a list of discrete choices the user TICKED — the
/// clarification-card counterpart of [properNounTokens], reading text the
/// user selected rather than typed (see ResearchLedger.clarificationPicks).
///
/// Both of [properNounTokens]' safety rules apply unchanged, across the
/// whole list rather than per choice: adjacent capitalised tokens are one
/// name ("São Paulo"), and fewer than two distinct names yields nothing —
/// so ticking a single option can never split anything, exactly as a lone
/// capitalised phrase in a typed question cannot.
///
/// What differs is the sentence-initial skip, and it has to. An option is
/// a LABEL, not a sentence: "Tokyo" is capitalised because it names a
/// city, not because it opens one. Dropping its first word — the right
/// call for the "What"/"Give"/"Compare" that open a typed question —
/// erases one-word options entirely, so a card offering
/// "Tokyo"/"Delhi"/"Shanghai" and answered with two of them would name
/// nothing at all and the two cities the user explicitly chose would
/// collapse onto one sub-goal, which is the failure the name split exists
/// to stop.
///
/// Accepted residual, in the same fail-closed spirit as the rest of this
/// mechanism: an option opening with a capitalised article or common noun
/// ("The planet Mercury") offers that word as a name token too. Reaching
/// the two-distinct-names bar takes two ticked options in the first place,
/// and the alternative — skipping every option's first word — costs
/// precisely the one-word options this exists for. A ticked string is the
/// user's own explicit choice, incidental words and all.
Set<String> properNounTokensInChoices(Iterable<String> choices) =>
    _namesFromRuns([
      for (final choice in choices)
        ..._capitalisedRuns(choice, skipOpeningWord: false),
    ]);

/// The runs of adjacent capitalised tokens in [text], in order. Shared by
/// [properNounTokens] and [properNounTokensInChoices] so both sides use one
/// definition of what a name looks like; they differ only in
/// [skipOpeningWord], which drops the first word of each sentence (see
/// [properNounTokens] for why, and [properNounTokensInChoices] for why a
/// ticked option is exempt).
List<List<String>> _capitalisedRuns(String text,
    {required bool skipOpeningWord}) {
  final runs = <List<String>>[];
  for (final sentence in text.split(_sentenceBreak)) {
    var sentenceStarted = !skipOpeningWord;
    for (final segment in sentence.split(_segmentBreak)) {
      var run = <String>[];
      for (final token in _tokens(segment)) {
        if (!sentenceStarted) {
          sentenceStarted = true;
          continue;
        }
        if (_isCapitalised(token)) {
          run.add(token);
        } else if (run.isNotEmpty) {
          runs.add(run);
          run = <String>[];
        }
      }
      // A segment boundary ends a run as surely as a lowercase word does:
      // "Tokyo, Delhi" is two names, not one.
      if (run.isNotEmpty) runs.add(run);
    }
  }
  return runs;
}

/// The lowercased tokens of [runs], but only once [runs] holds two or more
/// DISTINCT names — the "fewer than two runs yields nothing" rule both
/// callers rest on. Flattened to tokens rather than kept as phrases
/// because the query side matches token by token ([wordTokens]) and a
/// model may write only half of a multi-word name.
Set<String> _namesFromRuns(List<List<String>> runs) {
  final phrases = {
    for (final run in runs) run.map((t) => t.toLowerCase()).join(' '),
  };
  if (phrases.length < 2) return const {};
  return {
    for (final run in runs)
      for (final token in run) token.toLowerCase(),
  };
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
