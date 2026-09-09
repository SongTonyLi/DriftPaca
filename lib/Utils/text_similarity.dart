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

/// Strips the marks that sit INSIDE a word — apostrophes (straight and
/// curly) and periods — so "Vietnam's" tokenizes as one token and "D.C."
/// as "DC".
///
/// Deliberately the ONE place that rule lives. Both the instance check
/// ([wordTokens], [properNounNames]) and the similarity score
/// ([_normalizeForTrigrams]) run through it, because two near-identical
/// normalizers is how "both sides must normalize identically" quietly
/// rots: while the trigram side stripped only the straight apostrophe, a
/// name typed on a phone keyboard tokenized the same on both instance
/// sides but scored as a different string.
String _stripWordMarks(String s) =>
    s.replaceAll("'", '').replaceAll('\u2019', '').replaceAll('.', '');

/// Normalizes text for trigram comparison: lowercase, strip the marks that
/// sit inside a word (so "D.C." / "DC" and "won't" / "wont" compare
/// identically), collapse remaining punctuation to a space, collapse
/// whitespace.
String _normalizeForTrigrams(String s) {
  final stripped = _stripWordMarks(s.toLowerCase());
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

final _wordRun = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// The word tokens of [text] in order, case preserved. The single
/// tokenizer behind both [wordTokens] and [properNounNames]: the two
/// sides of an instance comparison must normalize identically, or a name
/// the user wrote as "Vietnam's" would never match the "vietnams" a model
/// puts in its query and the split they feed would silently stop firing.
List<String> _tokens(String text) =>
    [for (final m in _wordRun.allMatches(_stripWordMarks(text))) m[0]!];

/// The distinct lowercased word tokens of [text]. This is the QUERY side
/// of ResearchLedger's instance check: a model writes "tokyo" for a city
/// the user typed as "Tokyo", so this side is case-blind and applies none
/// of [properNounNames]' capitalisation rules — it only asks which of the
/// names the user already established appear here.
Set<String> wordTokens(String text) =>
    {for (final t in _tokens(text)) t.toLowerCase()};

/// Sentence boundaries for [properNounNames]: past one of these, a
/// capital is orthography rather than evidence of a name.
final _sentenceBreak = RegExp(r'[.!?\n]+');

/// Ends a run of capitalised words WITHIN a sentence — every punctuation
/// mark that is not part of a word (comma, dash, colon, quote, paren).
/// Apostrophes are excluded because they sit inside names ("Côte
/// d'Ivoire") and [_stripWordMarks] removes them anyway; a hyphen INSIDE a
/// word is removed before this ever runs (see [_joinHyphenatedWords]).
final _segmentBreak = RegExp(r"[^\p{L}\p{N}\s'\u2019]+", unicode: true);

/// A hyphen with a word character on both sides of it. It belongs to the
/// word rather than separating two of them, so it is replaced by a space
/// before the segment split and the name it joins stays ONE run.
///
/// Read as a separator instead, it cut single names in half — and two
/// halves of one name look exactly like two names, which is enough to
/// switch the whole instance split on for a question that only ever named
/// one thing. Measured: "What is Coca-Cola's 2024 revenue?" yielded the
/// two "names" coca and colas, "Explain the Mercedes-Benz EQS range"
/// yielded mercedes and benz/eqs, and "How does the CRISPR-Cas9 mechanism
/// work?" yielded crispr and cas9 — so a model broadening and then
/// narrowing one of those questions opened a second sub-goal with a
/// second search budget.
final _intraWordHyphen =
    RegExp(r'([\p{L}\p{N}])[-\u2010\u2011](?=[\p{L}\p{N}])', unicode: true);

String _joinHyphenatedWords(String text) =>
    text.replaceAllMapped(_intraWordHyphen, (m) => '${m[1]} ');

/// Whether [token] is capitalised in a way that could name something: at
/// least two characters, starting with a character that HAS a distinct
/// lowercase form and is not in it. Digits and uncased scripts are false
/// by construction, which is what keeps a CJK, Arabic, Hebrew or Thai
/// question out of [properNounNames] without a script list to maintain.
bool _isCapitalised(String token) {
  if (token.length < 2) return false;
  final c = token[0];
  return c.toUpperCase() == c && c.toLowerCase() != c;
}

/// Whether [token] opens with a lowercase letter — the counter-evidence
/// [_capitalisedRuns] needs before it reads any capital as a name (see
/// the contrast rule there).
bool _isLowercaseInitial(String token) {
  final c = token[0];
  return c.toLowerCase() == c && c.toUpperCase() != c;
}

final _digitsOnly = RegExp(r'^\d+$');

/// The names the user used to NAME the several things they asked about —
/// the entity counterpart of [numericTokens] — each as its own lowercased,
/// space-joined phrase, and empty unless the question really does list two
/// or more of them.
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
/// Four rules keep this from over-firing, and they are the whole safety
/// argument:
///
///   * a sentence that shows no CONTRAST — no word in it starts
///     lowercase — names nothing, because there capitalisation is a
///     typing style rather than a distinction the user drew;
///   * adjacent capitalised tokens merge into ONE run, and neither an
///     internal number ("Boeing 737 MAX") nor a hyphen inside a word
///     ("Mercedes-Benz") breaks that run;
///   * fewer than two DISTINCT runs yields nothing;
///   * a run stays a PHRASE. "New York" is one name, not the two names
///     new and york, and only a query naming it in full names it at all
///     (see [namesIn]).
///
/// Together they mean capitalisation counts as instance-naming only when
/// the user actually listed several names. Each rule closes a measured
/// hole in the previous shape of this function, where runs were built
/// from punctuation and per-token capitalisation alone and then flattened
/// to tokens:
///
///   * without the contrast rule, ANY punctuation defeated run-merging in
///     a shouted or Title Case message — "WHAT IS THE POPULATION OF
///     TOKYO, DELHI, AND SHANGHAI?" produced the eight "names" is, the,
///     population, of, tokyo, delhi, and, shanghai, so the plain re-ask
///     "the current population of Tokyo" (0.862 against the sub-goal it
///     belonged to) opened a second sub-goal on the word the;
///   * without the number and hyphen rules, a SINGLE name containing
///     either one split into two runs by itself and switched the whole
///     mechanism on for a question that named one thing;
///   * without phrases, a common word sitting inside a multi-word name
///     became an instance on its own: "Compare Tokyo and New York
///     populations" made new an instance, so the canonical rewording
///     "Tokyo population new estimate" (0.519) split off a sub-goal of
///     its own, and a title starting with "The" did the same to every
///     query that used the word.
///
/// A lone capitalised phrase is the question's SUBJECT ("What is Vietnam
/// GDP?"), not one of a set, and splitting on a subject that some queries
/// name and others don't would fragment one question into a sub-goal per
/// rewording — precisely the model-thrash failure the instance override
/// exists to STOP (see ResearchLedger._isDifferentRequestedInstance).
/// Over-splitting is the dangerous direction: every extra sub-goal
/// carries a fresh per-sub-goal budget and makes its round look like it
/// broadened coverage, so a wrongly-split run never trips the stall
/// counter and burns its whole search budget. Every ambiguous case
/// therefore fails closed, by grouping.
///
/// The first token of each sentence is skipped for the same reason:
/// "What", "Give" and "Compare" are capitalised by position, not because
/// they name anything.
///
/// Deliberately accepted under-splits, each of which falls back to the
/// grouping behaviour that was there before rather than to a wrong split:
///
///   * an ALL-LOWERCASE question names nothing this can see, so "what is
///     the population of tokyo, delhi and shanghai" still collapses onto
///     one sub-goal. This mechanism closes the four-entity truncation for
///     users who capitalise, and only for them;
///   * a brand spelled with a lowercase initial (iPhone, eBay, iOS) is
///     invisible for the same reason, as is any name in a question typed
///     entirely in capitals;
///   * a name that opens a sentence is dropped ("Tokyo or Delhi — which
///     is bigger?" yields only Delhi);
///   * a period inside a name breaks the sentence, so what follows it
///     reads as sentence-initial ("Washington D.C. and Boston");
///   * a query naming only part of a name, or its possessive ("São
///     Paulo's population"), does not name it — [namesIn] matches the
///     whole phrase or nothing;
///   * a question written in an uncased script (CJK, Arabic, Hebrew,
///     Thai) yields nothing, since no character in it is uppercase —
///     those runs keep exactly the grouping they have today.
Set<String> properNounNames(String text) =>
    _namesFrom(_capitalisedRuns(text, typedProse: true));

/// The names in a list of discrete choices the user TICKED — the
/// clarification-card counterpart of [properNounNames], reading text the
/// user selected rather than typed (see ResearchLedger.clarificationPicks).
///
/// [properNounNames]' merging and whole-phrase rules apply unchanged, so
/// "São Paulo" is one name rather than the two names são and paulo, and
/// only a query carrying that whole phrase names it (see [namesIn]).
///
/// Its "unless the user listed two of them" rule applies too, but counted
/// over the CHOICES rather than over the runs pooled out of them: at least
/// two ticked options must each name something, or this yields nothing.
/// Ticking is how a user lists things on a card, so two ticked options are
/// two things and ONE ticked option is one thing — however many
/// capitalised runs its label happens to contain.
///
/// Counted over the pooled runs instead, as it was until this bar moved, a
/// single ticked "Tokyo, Japan" named the two instances tokyo and japan. A
/// sub-goal opened as "Tokyo market size 2024" then names only tokyo, so
/// the model's own re-ask of that same lookup ("market size in Tokyo,
/// Japan", trigram 0.467 — well above the ledger's grouping threshold)
/// named an instance its sub-goal did not, stopped grouping, and bought a
/// second sub-goal with a second search budget. Answering the card cost
/// twice what skipping it cost, which is the exact failure
/// ResearchLedger.clarificationPicks exists to prevent rather than to
/// cause — and "City, Country", "Name (qualifier)" and "X — Y" are all
/// ordinary option shapes, which parseResearchGoal passes through
/// verbatim.
///
/// What differs from [properNounNames] is the two rules that read a text
/// as a SENTENCE, and they have to. An option is a LABEL: "Tokyo" is
/// capitalised because it names a city, not because it opens a sentence,
/// and a card whose options are all one-word names shows no lowercase
/// contrast at all. Applying the contrast rule would erase the whole card,
/// and applying the sentence-initial skip unconditionally would erase
/// every one-word option — so a user offered "Tokyo"/"Delhi"/"Shanghai"
/// who ticked two of them would name nothing, and the two cities they
/// explicitly chose would collapse onto one sub-goal, which is the failure
/// the name split exists to stop.
///
/// A label's opening word is therefore dropped only when the word after
/// it starts lowercase — the mark of a sentence-case phrase rather than a
/// name. "The planet Mercury" loses its "The" and names Mercury; "São
/// Paulo", "Tokyo" and "Q1 2025" keep every word they have. Kept
/// unconditionally, that "The" stood as a name of its own, and any query
/// using the word generically then named an instance its sub-goal did not
/// — the same over-split that reading a multi-word name token by token
/// used to cause.
///
/// Deliberately accepted under-split, in the same fail-closed direction
/// [properNounNames] takes: a single option that really does list two
/// things ("Tokyo, Delhi", ticked from a card offering combinations) names
/// nothing, because no rule available here tells it apart from the far
/// commoner "Tokyo, Japan" — one thing, qualified. Those two queries group
/// exactly as they would have with no card at all, which is the direction
/// that costs a run nothing it had before.
Set<String> properNounNamesInChoices(Iterable<String> choices) {
  final runs = <List<String>>[];
  var naming = 0;
  for (final choice in choices) {
    final own = _capitalisedRuns(choice, typedProse: false);
    if (own.isEmpty) continue;
    naming++;
    runs.addAll(own);
  }
  if (naming < 2) return const {};
  // [_namesFrom]'s own two-distinct-names bar still applies on top, so two
  // ticked options that name one and the same thing name nothing either.
  return _namesFrom(runs);
}

/// Which of [names] — phrases from [properNounNames] or
/// [properNounNamesInChoices] — [text] actually names.
///
/// A name matches only when ALL of its tokens appear in [text]
/// consecutively and in order. Matching token by token instead is what let
/// a common word inside a multi-word name split ordinary rewordings: with
/// "New York" reduced to new and york, the query "Tokyo population new
/// estimate" named an instance its sub-goal did not and opened one of its
/// own. Requiring the whole phrase is the fail-closed direction — a model
/// that abbreviates ("NYC") or inflects ("São Paulo's") names nothing here
/// and its query simply groups.
Set<String> namesIn(String text, Set<String> names) {
  if (names.isEmpty) return const {};
  final tokens = [for (final t in _tokens(text)) t.toLowerCase()];
  return {
    for (final name in names)
      if (_containsInOrder(tokens, name.split(' '))) name,
  };
}

/// Whether [name]'s tokens appear consecutively, in order, in [tokens].
bool _containsInOrder(List<String> tokens, List<String> name) {
  for (var i = 0; i + name.length <= tokens.length; i++) {
    var matched = true;
    for (var j = 0; j < name.length; j++) {
      if (tokens[i + j] != name[j]) {
        matched = false;
        break;
      }
    }
    if (matched) return true;
  }
  return false;
}

/// The runs of adjacent capitalised tokens in [text], in order. Shared by
/// [properNounNames] and [properNounNamesInChoices] so both sides use one
/// definition of what a name looks like; they differ only in
/// [typedProse], which reads [text] as sentences the user wrote — skipping
/// each sentence's first word and requiring the sentence to show
/// lowercase contrast — rather than as a label the user ticked (see
/// [properNounNames] for why, and [properNounNamesInChoices] for why a
/// ticked option is exempt from both).
List<List<String>> _capitalisedRuns(String text, {required bool typedProse}) {
  final runs = <List<String>>[];
  for (final sentence in _joinHyphenatedWords(text).split(_sentenceBreak)) {
    final all = _tokens(sentence);
    // Capitalisation is a CONTRAST signal: it says the writer marked
    // these words out from the ones around them. A sentence with no
    // lowercase word in it draws no such distinction, so nothing in it
    // is evidence of a name. Merging adjacent capitals was supposed to
    // cover this on its own, but any punctuation ends a run — one comma
    // in a shouted question was enough to make every function word in it
    // an instance the user had supposedly named.
    if (typedProse && !all.any(_isLowercaseInitial)) continue;
    // A typed sentence always opens with an orthographic capital. A
    // ticked label opens with one only when it reads as a sentence-case
    // phrase rather than a name — "The planet Mercury" does, "São Paulo"
    // and "Tokyo" do not — and the word after it is what says which:
    // dropping every label's first word erases one-word options, keeping
    // every label's first word leaves "The" standing as a name of its own.
    var opened =
        !(typedProse || (all.length >= 2 && _isLowercaseInitial(all[1])));
    for (final segment in sentence.split(_segmentBreak)) {
      var run = <String>[];
      for (final token in _tokens(segment)) {
        if (!opened) {
          opened = true;
          continue;
        }
        if (_isCapitalised(token)) {
          run.add(token);
        } else if (run.isNotEmpty && _digitsOnly.hasMatch(token)) {
          // A number inside a name is part of it ("Boeing 737 MAX",
          // "Windows 11 Pro"), not the end of one. Ending the run here
          // made a single product name look like two names.
          run.add(token);
        } else if (run.isNotEmpty) {
          runs.add(_withoutTrailingDigits(run));
          run = <String>[];
        }
      }
      // A segment boundary ends a run as surely as a lowercase word does:
      // "Tokyo, Delhi" is two names, not one.
      if (run.isNotEmpty) runs.add(_withoutTrailingDigits(run));
    }
  }
  return runs;
}

/// Drops the numbers left dangling at the END of a run. A number only
/// joins a run to stay inside a name; trailing, it is a separate instance
/// [numericTokens] already reads, and keeping it would narrow the name to
/// one spelling — "population of Tokyo 2024" would name "tokyo 2024" and
/// no query that omitted the year would match it.
List<String> _withoutTrailingDigits(List<String> run) {
  var end = run.length;
  while (end > 1 && _digitsOnly.hasMatch(run[end - 1])) {
    end--;
  }
  return run.sublist(0, end);
}

/// The lowercased phrases of [runs], but only once [runs] holds two or
/// more DISTINCT names — the "unless the user listed two of them" rule, in
/// the form [properNounNames] rests on it. [properNounNamesInChoices]
/// counts ticked options before it gets here, and rests on both bars.
Set<String> _namesFrom(List<List<String>> runs) {
  final names = {
    for (final run in runs) run.map((t) => t.toLowerCase()).join(' '),
  };
  if (names.length < 2) return const {};
  return names;
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
