import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Utils/text_similarity.dart';

void main() {
  group('trigramJaccard', () {
    // Every query below is a VERBATIM query emitted by gpt-oss:120b during a
    // real multi-round run: it re-asked the same population question three
    // ways and the same medal-count question four ways, and the old
    // exact-match normalisation caught none of them. These pairs are the
    // reason this function exists, so they are asserted against the
    // threshold the ledger actually groups on — not an arbitrary constant.
    const nearDuplicates = <List<String>>[
      [
        'Washington D.C. population 2026 estimate',
        'Washington, D.C. population 2025'
      ],
      [
        'Washington D.C. population 2026 estimate',
        'Washington DC population 2026'
      ],
      ['Washington, D.C. population 2025', 'Washington DC population 2026'],
      [
        '2024 Summer Olympics medal table gold medals United States 39',
        '2024 Paris Olympics gold medals United States 39'
      ],
      [
        'Paris 2024 Summer Olympics gold medals USA count',
        'Paris 2024 Olympic gold medal count USA'
      ],
    ];

    test('groups every measured near-duplicate pair onto one sub-goal', () {
      for (final pair in nearDuplicates) {
        final ledger = ResearchLedger(objective: 'irrelevant');
        final first = ledger.upsert(pair[0]);
        final second = ledger.upsert(pair[1]);
        expect(
          identical(first, second),
          isTrue,
          reason: 'expected "${pair[1]}" to group onto "${pair[0]}" '
              '(score ${trigramJaccard(pair[0], pair[1]).toStringAsFixed(3)})',
        );
        expect(ledger.subGoals, hasLength(1));
      }
    });

    test('keeps genuinely different questions as separate sub-goals', () {
      const distinct = <List<String>>[
        // Negative controls spanning the same run: a different question
        // about the same city, and two unrelated topics.
        [
          'Washington DC population 2025',
          'Washington DC median income 2025'
        ],
        ['Vietnam GDP 2024', 'Thailand GDP 2024'],
        [
          'Washington D.C. population 2026 estimate',
          '2024 Summer Olympics most gold medals which country'
        ],
      ];
      for (final pair in distinct) {
        final ledger = ResearchLedger(objective: 'irrelevant');
        ledger.upsert(pair[0]);
        ledger.upsert(pair[1]);
        expect(
          ledger.subGoals,
          hasLength(2),
          reason: 'expected "${pair[0]}" and "${pair[1]}" to stay separate '
              '(score ${trigramJaccard(pair[0], pair[1]).toStringAsFixed(3)})',
        );
      }
    });

    // The normalizer used to collapse every non-ASCII character to a space,
    // so ANY pure-CJK query normalized to the empty string. Two completely
    // unrelated Chinese questions therefore scored 1.0, the ledger grouped
    // every one of them onto a single sub-goal, and _isLedgerBlocked
    // refused every search after the first — a Chinese user got exactly one
    // search per turn, forever, with the ledger reporting one sub-goal.
    test('keeps unrelated non-Latin queries apart', () {
      const unrelated = <List<String>>[
        ['越南目前的人口是多少', '法国的首都是哪座城市'],
        ['苹果公司的首席执行官是谁', '珠穆朗玛峰有多高'],
        ['東京の人口', '大阪の天気'],
        ['ما هو عدد سكان فيتنام', 'ما هي عاصمة فرنسا'],
      ];
      for (final pair in unrelated) {
        final score = trigramJaccard(pair[0], pair[1]);
        expect(score, lessThan(0.40),
            reason: '"${pair[0]}" vs "${pair[1]}" scored '
                '${score.toStringAsFixed(3)} — at or above the ledger\'s '
                'grouping threshold these become one sub-goal');

        final ledger = ResearchLedger(objective: 'irrelevant');
        ledger.upsert(pair[0]);
        ledger.upsert(pair[1]);
        expect(ledger.subGoals, hasLength(2));
      }
    });

    test('still groups genuine near-duplicates in a non-Latin script', () {
      // The mechanism has to keep working, not just stop over-firing.
      final ledger = ResearchLedger(objective: 'irrelevant');
      final first = ledger.upsert('越南目前的人口是多少');
      final second = ledger.upsert('越南目前的人口是多少人');
      expect(identical(first, second), isTrue,
          reason: 'score '
              '${trigramJaccard('越南目前的人口是多少', '越南目前的人口是多少人').toStringAsFixed(3)}');
    });

    test('a mixed-script query is not mistaken for a pure-script one', () {
      // "2026" alone used to be all that survived normalization here, so a
      // CJK question containing a year compared as if it were just that year.
      expect(trigramJaccard('2026年世界杯冠军是哪个国家', '2026年奥运会金牌最多的国家'),
          lessThan(0.75));
    });

    test('is symmetric and 1.0 for identical strings modulo case/whitespace', () {
      expect(trigramJaccard('Vietnam GDP', 'vietnam   gdp'), 1.0);
      expect(
        trigramJaccard('a b', 'c d'),
        trigramJaccard('c d', 'a b'),
      );
    });
  });

  group('properNounNames', () {
    // The user side of ResearchLedger's instance check. It answers one
    // question — "which things did the user NAME?" — and it has to answer
    // it conservatively, because a wrong "yes" splits one question into a
    // sub-goal per rewording, and each of those carries a fresh search
    // budget and a round that looks like it broadened coverage.
    test('reads the names out of a question that lists several', () {
      expect(
        properNounNames('What is the current population of Tokyo, Delhi, '
            'Shanghai and São Paulo? Give the figure for each.'),
        {'tokyo', 'delhi', 'shanghai', 'são paulo'},
        reason: 'four names the user typed, and the two-word one is ONE '
            'name rather than the two instances são and paulo',
      );
      expect(properNounNames('Compare NASA and ESA budgets.'), {'nasa', 'esa'},
          reason: 'the sentence-initial verb names nothing, and the '
              'lowercase noun after ESA ends its run');
    });

    test('reads nothing out of a question with a single subject', () {
      // One capitalised phrase is what the question is ABOUT. Splitting on
      // it would fragment one question, so a single run yields nothing —
      // and adjacent capitalised words are one run, which is what makes
      // "Vietnam GDP" and "Mount Everest" single subjects rather than two
      // names apiece.
      for (final single in [
        'What is Vietnam GDP?',
        'How is Apple doing this quarter?',
        "What was Vietnam's GDP in 2024?",
        'How tall is Mount Everest?',
        'What is the outlook for Brazilian inflation?',
        'How many people live in the Tokyo metropolitan area as of 2025?',
      ]) {
        expect(properNounNames(single), isEmpty,
            reason: '"$single" names one thing, so capitalisation carries no '
                'instance signal and every re-ask of it must still group');
      }
    });

    test('a number or a hyphen inside a name does not make it two names', () {
      // Measured over-splits of the previous shape of this function, where
      // a digit-run ended a run and a hyphen ended a segment. Each of
      // these questions names exactly ONE thing, so each must yield
      // nothing at all: with the name broken in half, its two halves read
      // as two names, that alone switched the whole instance split on, and
      // a model broadening and then narrowing the SAME question opened a
      // second sub-goal with a second search budget.
      for (final one in [
        'What happened to the Boeing 737 MAX, in detail?',
        "What is Coca-Cola's revenue?",
        'How does the CRISPR-Cas9 mechanism work?',
        'Explain the Mercedes-Benz EQS range',
        'When does the Windows 11 Pro support window close?',
      ]) {
        expect(properNounNames(one), isEmpty,
            reason: '"$one" names one thing; the number or hyphen inside '
                'that name is part of it, not the end of it');
      }
    });

    test('reads nothing out of a Title Case or shouted question', () {
      // Capitalisation only means something by CONTRAST. Where every word
      // is capitalised the user drew no distinction at all, so nothing in
      // the sentence is evidence of a name.
      //
      // Punctuation is the load-bearing half of this test. Run-merging
      // alone was supposed to collapse a shouted message to one run, but
      // ANY punctuation ends a run, so a single comma or dash split these
      // into two-plus runs of function words and handed every word of the
      // question the standing of a name the user had listed.
      for (final shouted in [
        'What Is The Current Population Of Tokyo And Delhi?',
        'WHAT IS THE CURRENT POPULATION OF TOKYO AND DELHI?',
        'WHAT IS THE POPULATION OF TOKYO, DELHI, AND SHANGHAI?',
        'What Is The Current Population Of Tokyo, Delhi And Shanghai?',
        'PLEASE RESEARCH THE POPULATION OF TOKYO - I NEED IT TODAY',
      ]) {
        expect(properNounNames(shouted), isEmpty, reason: shouted);
      }
    });

    test('reads nothing out of an uncased script', () {
      // No character in these is uppercase, so the name split cannot fire
      // for a Chinese, Japanese, Arabic, Hebrew or Thai question at all —
      // by construction, not by a script list that could go stale. Those
      // runs keep exactly the grouping trigramJaccard gives them.
      for (final uncased in [
        '东京和德里目前的人口分别是多少？',
        '東京と大阪の人口は？',
        'ما هو عدد سكان فيتنام وفرنسا',
        'ประชากรของโตเกียวและเดลี',
      ]) {
        expect(properNounNames(uncased), isEmpty, reason: uncased);
      }
    });

    test('is empty for text with nothing capitalised to read', () {
      expect(properNounNames(''), isEmpty);
      expect(properNounNames('irrelevant'), isEmpty);
      expect(properNounNames('what is the population of tokyo and delhi'),
          isEmpty,
          reason: 'an all-lowercase question names nothing this can see, so '
              'it groups exactly as it did before — the entity split closes '
              'the four-entity truncation for users who capitalise, and the '
              'accepted under-splits list says so');
    });
  });

  group('properNounNamesInChoices', () {
    // The same question — "which things did the user NAME?" — asked of
    // clarification options they TICKED rather than of a question they
    // typed. The merging, two-names and whole-phrase rules carry over;
    // the two rules that read a text as a sentence do not, because an
    // option is a label.
    test('reads the names out of the options the user ticked', () {
      expect(properNounNamesInChoices(const ['Tokyo', 'Delhi']),
          {'tokyo', 'delhi'},
          reason: 'a one-word option is a name, not a sentence opener — '
              'dropping its first word the way a typed question\'s is '
              'dropped would leave two ticked cities naming nothing, and '
              'collapse them onto one sub-goal');
      expect(properNounNamesInChoices(const ['São Paulo', 'Tokyo']),
          {'são paulo', 'tokyo'},
          reason: 'adjacent capitalised words are still one name, and it is '
              'still that whole name rather than its separate words');
      expect(
          properNounNamesInChoices(
              const ['Tokyo, Japan', 'Seoul, South Korea']),
          {'tokyo', 'japan', 'seoul', 'south korea'},
          reason: 'and a segment boundary still ends a run, so two ticked '
              '"City, Country" labels name four things — what has to be two '
              'is the ticked OPTIONS, and both of these name something');
      expect(properNounNamesInChoices(const ['NOMINAL', 'REAL']),
          {'nominal', 'real'},
          reason: 'a card of shouted labels shows no lowercase contrast '
              'anywhere, and requiring it here would erase every option the '
              'user ticked');
    });

    test('reads nothing out of a single ticked option', () {
      // The rule that keeps this from over-firing, and the reason it counts
      // ticked OPTIONS rather than the capitalised runs pooled out of them:
      // ticking is how a user lists things on a card, so one ticked option
      // is one thing however its label happens to be written. One name is
      // what the run is ABOUT, and splitting on it would fragment one
      // question into a sub-goal per rewording, each with a fresh search
      // budget.
      expect(properNounNamesInChoices(const ['Tokyo']), isEmpty);
      expect(
          properNounNamesInChoices(
              const ['The Phoenix Mercury basketball team']),
          isEmpty,
          reason: 'this one is a single run as well, its capitalised words '
              'being adjacent — but it is a single ticked option first, '
              'which is what decides it');

      // The cases that made the claim above false while it was counting
      // pooled runs. Every one of these is an ordinary option shape, and
      // parseResearchGoal hands an option's text through verbatim.
      for (final label in const [
        'Tokyo, Japan',
        'New York City, New York',
        'United States, measured in USD',
        'Both Tokyo and Delhi',
      ]) {
        expect(properNounNamesInChoices([label]), isEmpty,
            reason: '"$label" holds two capitalised runs, but the user '
                'ticked ONE option and so listed one thing. Read as two '
                'named instances, a "City, Country" pick made the model\'s '
                'own re-ask of its own lookup name an instance its sub-goal '
                'did not, so the re-ask stopped grouping and bought a second '
                'sub-goal and a second search budget — answering the card '
                'cost more than skipping it');
      }

      expect(properNounNamesInChoices(const ['Tokyo, Delhi']), isEmpty,
          reason: 'including the option that really does list two things: '
              'nothing available here tells "Tokyo, Delhi" apart from '
              '"Tokyo, Japan", so it fails closed by grouping — the same '
              'accepted under-split those two cities typed in lowercase '
              'already get, and the direction that costs a run nothing it '
              'had before');
      expect(properNounNamesInChoices(const []), isEmpty);
    });

    test('two ticked options must each name something', () {
      expect(properNounNamesInChoices(const ['Tokyo', 'all major cities']),
          isEmpty,
          reason: 'only one of the two ticked options names anything, so the '
              'user listed one thing and nothing here can split');
      expect(properNounNamesInChoices(const ['Tokyo', 'Tokyo, Japan']),
          {'tokyo', 'japan'},
          reason: 'while two options that do each name something clear the '
              'bar, and every run they hold between them counts');
    });

    test('digits are left to numericTokens', () {
      expect(properNounNamesInChoices(const ['2023', '2024']), isEmpty,
          reason: 'nothing in a bare year is capitalised; the ledger reads '
              'those through numericTokens, which has no two-of-them rule');
      expect(properNounNamesInChoices(const ['Q1 2025', 'Q4 2024']),
          {'q1', 'q4'},
          reason: 'a quarter label carries both kinds at once, and reading '
              'the capitalised half here costs nothing: the digits already '
              'split these two apart. The trailing year is dropped from the '
              'name so a query writing only "Q1" still names it');
    });

    test('a label opening with a capitalised article loses that word', () {
      // An option's first word is dropped only when the word after it
      // starts lowercase — the mark of a sentence-case phrase rather than
      // a name. Kept, that "The" stood as a name in its own right, and
      // every query using the word generically then named an instance its
      // sub-goal did not: the same over-split that reading a multi-word
      // name token by token used to cause.
      expect(
          properNounNamesInChoices(
              const ['The planet Mercury', 'The Phoenix Mercury team']),
          {'mercury', 'the phoenix mercury'},
          reason: '"The planet Mercury" is sentence-case around a name, so '
              'it names Mercury; "The Phoenix Mercury team" opens with a '
              'capitalised word and keeps it, because that is where the '
              'team\'s name starts');
    });
  });

  group('namesIn', () {
    test('matches a name only when the whole phrase is there, in order', () {
      const names = {'são paulo', 'tokyo'};
      expect(namesIn('current population of São Paulo', names), {'são paulo'});
      expect(namesIn('current population of Tokyo', names), {'tokyo'});
      expect(namesIn('current population', names), isEmpty);
      expect(namesIn('Paulo Coelho biography', names), isEmpty,
          reason: 'half of a two-word name is not that name — matching it '
              'token by token is what let an ordinary word inside a name '
              'split queries that only used the word generically');
      expect(namesIn('São Paulo and Tokyo compared', names),
          {'são paulo', 'tokyo'});
      expect(namesIn('anything at all', const <String>{}), isEmpty);
    });

    test('is case-blind and normalizes the query side identically', () {
      expect(namesIn('SAO Paulo'.toLowerCase(), const {'sao paulo'}),
          {'sao paulo'});
      expect(namesIn('the new york subway', const {'new york'}), {'new york'},
          reason: 'a model writes the name in whatever case it likes');
      expect(namesIn("Coca-Cola's market share", const {'coca cola'}), isEmpty,
          reason: 'an inflected name is an accepted miss: it names nothing '
              'and the query simply groups, which is the fail-closed '
              'direction');
      expect(namesIn('Coca-Cola market share', const {'coca cola'}),
          {'coca cola'},
          reason: 'and the hyphen inside a name is not a word boundary on '
              'either side of the comparison');
    });
  });
  group('wordTokens', () {
    test('normalizes the query side exactly as the user side is normalized', () {
      // Both sides of the instance comparison run through one tokenizer on
      // purpose: if the user's "Vietnam's" kept its apostrophe while a
      // model's "vietnams" did not, the two would never match and the
      // split would silently stop firing.
      expect(wordTokens("Vietnam's GDP in D.C. 2024"),
          {'vietnams', 'gdp', 'in', 'dc', '2024'},
          reason: 'apostrophes and periods are stripped inside a word, '
              'digits are kept as tokens of their own, and everything is '
              'lowercased');
      expect(wordTokens('current population of São Paulo'),
          {'current', 'population', 'of', 'são', 'paulo'},
          reason: 'case-blind on the query side: a model writes the city '
              'name however it likes');
      expect(wordTokens('Tokyo, Delhi — Shanghai; (São Paulo)'),
          {'tokyo', 'delhi', 'shanghai', 'são', 'paulo'},
          reason: 'punctuation separates tokens rather than joining them');
    });
  });

  group('queryCoverage', () {
    test('scores a short query higher against a chunk containing its terms', () {
      const query = 'Vietnam GDP 2024';
      const withTerms =
          "Vietnam's GDP in 2024 grew significantly according to reports, "
          'with strong export numbers across many sectors of the economy '
          'driving overall growth this year and beyond.';
      const withoutTerms =
          'The weather today in Hanoi is sunny with a high of 30 degrees '
          'celsius and light winds from the northeast, typical for this '
          'time of year in the region.';

      final withScore = queryCoverage(query, withTerms);
      final withoutScore = queryCoverage(query, withoutTerms);

      expect(withScore, greaterThan(withoutScore));
      expect(withScore, greaterThan(0.5));
      expect(withoutScore, 0.0);
    });
  });
}
