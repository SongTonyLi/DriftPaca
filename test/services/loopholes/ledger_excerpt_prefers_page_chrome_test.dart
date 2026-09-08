/// Probe: the research ledger's supporting excerpt is the TOP of the fetched
/// page (navigation chrome), not the passage that made the page win.
///
/// `SearchAgent._executeToolCalls` (search_agent.dart:966-972) builds the
/// excerpt candidate list as `[...?r.chunks, r.pageContent, r.snippet]` —
/// the whole extracted page is ranked as one candidate alongside the chunks
/// it was split into. Ranking is `queryCoverage` (text_similarity.dart:74),
/// asymmetric containment with only the QUERY's trigram count as the
/// denominator, so a superset text can never score below any of its parts:
/// unless one single 1,500-char chunk happens to contain 100% of the query's
/// character trigrams, `pageContent` (up to `_maxPageContentLength` =
/// 200,000 chars) strictly beats every chunk. `selectSupportingExcerpt` then
/// returns `best.substring(0, 220)` (research_ledger.dart:463) — the first
/// 220 characters of the winner. For the page that just won on a sentence
/// several thousand characters in, those 220 characters are the site's
/// navigation sidebar.
///
/// The scoring window and the returned window are decoupled: the candidate
/// is judged on 200,000 chars and quoted from its first 220. That is exactly
/// the failure `_maxPageContentLength`'s own doc comment
/// (web_search_service.dart:44-55) says was fixed for CHUNK ranking — "the
/// ranker was picking the best of several thousand characters of nothing" —
/// reintroduced by adding the whole page back as a candidate.
///
/// The excerpt that loses this way is what `ResearchLedger.recordEvidence`
/// stores, what `_checklistLine` renders as `Excerpt: "…"` on every `[x]`
/// line, what `ChatProvider` appends to the SYSTEM prompt every turn, what
/// the research panel shows the user as that sub-goal's evidence, and the
/// only per-sub-goal evidence text that survives `_compactStaleRounds`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Services/search_agent.dart';
import 'package:llamaseek/Services/web_search_service.dart';
import 'package:llamaseek/Utils/text_similarity.dart';
import 'package:llamaseek/Utils/text_splitter.dart';

/// The query the model searched for, and the sub-goal it is filed under.
const _query = 'Tokyo metropolitan area population 2025 estimate';

/// The figure that actually answers [_query].
const _figure = '37,036,000';

/// A reference page's real opening: the wiki sidebar, before any prose.
const _navChrome =
    'Jump to content Main menu Main menu move to sidebar hide Navigation '
    'Main page Contents Current events Random article About Wikipedia '
    'Contact us Contribute Help Learn to edit Community portal Recent '
    'changes Upload file Search Search Appearance Donate Create account '
    'Log in Personal tools Donate Create account Log in Pages for logged '
    'out editors learn more Contributions Talk Toggle the table of '
    'contents 33 languages';

String _para(String seed, int repeats) =>
    List.filled(repeats, seed).join(' ').trim();

/// A reference-page-shaped extraction: nav chrome, prose, the answering
/// sentence a few thousand characters down, then more prose. Nothing here
/// is adversarial — no repeated keywords, no planted text. The only
/// property that matters is the ordinary one: the answer is not at the top,
/// and the query's character trigrams are spread across the article rather
/// than all packed into one 1,500-char window.
String buildPage() {
  final paras = <String>[
    _navChrome,
    _para(
        'The city grew rapidly during the Edo period and was renamed after '
        'the Meiji Restoration, when the imperial court moved east.',
        9),
    _para(
        'Rail lines built in the twentieth century pulled commuters inward '
        'from the surrounding prefectures every weekday morning.',
        9),
    '${_para('Reconstruction after the war reshaped the wards, and the 1964 '
        'games accelerated highway and subway building across the wards.', 8)}'
        ' As of 2025, the Tokyo metropolitan area population is estimated at '
        '$_figure residents.',
    _para(
        'Demographers publishing a 2025 estimate for the metropolitan area '
        'population rely on the national census and on annual registers.',
        8),
    '${_para('Transport, housing and water policy for the region are '
        'coordinated across the prefectural governments that share the '
        'basin.', 9)}'
        ' A decade earlier the resident population in 2015 was already the '
        'largest of any urban agglomeration on record.',
  ];
  return paras.join('\n\n');
}

/// The candidate list exactly as search_agent.dart:966-972 builds it for a
/// single result: every chunk, then the whole page, then the snippet.
List<String> candidatesFor(WebSearchResult r) => <String?>[
      ...?r.chunks,
      r.pageContent,
      r.snippet,
    ].whereType<String>().toList();

WebSearchResult buildResult() {
  final page = buildPage();
  return WebSearchResult(
    title: 'Greater Tokyo Area - Wikipedia',
    snippet: 'The Greater Tokyo Area is the most populous metropolitan area.',
    url: 'https://en.wikipedia.invalid/wiki/Greater_Tokyo_Area',
    pageContent: page,
    // Set by WebSearchService.searchAndExtract with exactly these knobs
    // (web_search_service.dart:178-183) whenever pageContent is non-empty,
    // so in production `chunks` and `pageContent` are ALWAYS both present.
    chunks: splitText(page, chunkSize: 1500, overlap: 200),
  );
}

void main() {
  group('whole-page candidate wins the ranking, then is quoted from the top',
      () {
    test('pageContent strictly outscores every chunk it was split from', () {
      final result = buildResult();
      final page = result.pageContent!;
      final chunks = result.chunks!;

      final pageScore = queryCoverage(_query, page);
      final bestChunkScore =
          chunks.map((c) => queryCoverage(_query, c)).reduce(
                (a, b) => a > b ? a : b,
              );

      expect(pageScore, 1.0,
          reason: 'queryCoverage only counts how many of the QUERY\'s '
              'trigrams appear in the text, so the superset every chunk was '
              'split from saturates at 1.0');
      expect(bestChunkScore, lessThan(pageScore),
          reason: 'no single 1500-char chunk holds 100% of the query\'s '
              'trigrams (best was $bestChunkScore), so pageContent wins the '
              'ranking outright — selectSupportingExcerpt breaks ties toward '
              'the earlier candidate, and the whole page needs no tie');
    });

    test('the chosen excerpt is the navigation sidebar, not the evidence', () {
      final result = buildResult();
      final excerpt = selectSupportingExcerpt(candidatesFor(result), _query);

      expect(excerpt, isNotNull);
      expect(excerpt!, startsWith('Jump to content Main menu'),
          reason: 'the winner is pageContent and selectSupportingExcerpt '
              'returns best.substring(0, 220) — the first 220 chars of a '
              '${result.pageContent!.length}-char document, which for a '
              'reference page is chrome');
      expect(excerpt, isNot(contains(_figure)),
          reason: 'the sentence that made this candidate win the ranking is '
              '${result.pageContent!.indexOf(_figure)} chars in, far outside '
              'the 220-char window that is actually quoted — the scoring '
              'window and the returned window are decoupled');
    });

    test('the returned text is nearly irrelevant to the query that picked it',
        () {
      final result = buildResult();
      final excerpt = selectSupportingExcerpt(candidatesFor(result), _query)!;

      final scoreOfWinner = queryCoverage(_query, result.pageContent!);
      final scoreOfWhatWasReturned = queryCoverage(_query, excerpt);

      expect(scoreOfWinner, 1.0);
      expect(scoreOfWhatWasReturned, lessThan(0.35),
          reason: 'the candidate was selected on a score of $scoreOfWinner '
              'but the bytes actually stored as evidence score '
              '$scoreOfWhatWasReturned against the same query — the ranking '
              'says nothing about the text it hands back');
    });

    test('a strictly better excerpt was available and was passed over', () {
      final result = buildResult();
      final chunks = result.chunks!;

      final answerChunks = chunks
          .where((c) =>
              c.contains(_figure) && queryCoverage(_query, c) > 0.9)
          .toList();
      expect(answerChunks, isNotEmpty,
          reason: 'a chunk carrying the actual figure scored above 0.9 — it '
              'lost only because the superset it came from scored 1.0');

      // Isolate the cause: same ranker, same query, same candidates, with
      // ONLY the whole-page entry removed from the list.
      final withoutWholePage = selectSupportingExcerpt(
        <String>[...chunks, result.snippet],
        _query,
      );
      expect(withoutWholePage, contains(_figure),
          reason: 'drop pageContent from search_agent.dart:966-972 and the '
              'very same call returns an excerpt that quotes the answer; the '
              'single extra candidate is what turns the evidence into '
              'sidebar links');
    });
  });

  group('this is the normal case, not a knife-edge one', () {
    // The defect does not need the query to be tuned: pageContent's score
    // is >= every chunk's by construction (chunk trigrams are a subset of
    // the page's), so a chunk only survives by TYING, which needs the
    // query's whole trigram set packed inside one 1,500-char window.
    // Ordinary phrasings of the same user question don't do that.
    test('five natural phrasings of one question all yield the sidebar', () {
      const phrasings = [
        'Tokyo metropolitan area population 2025 estimate',
        'population of the Tokyo metropolitan area in 2025',
        'how many people live in the Tokyo metropolitan area',
        'Greater Tokyo population estimate',
        'Tokyo population',
      ];
      final result = buildResult();

      for (final q in phrasings) {
        final excerpt = selectSupportingExcerpt(candidatesFor(result), q)!;
        expect(excerpt, startsWith('Jump to content'),
            reason: 'query "$q": pageContent scored '
                '${queryCoverage(q, result.pageContent!)} against a best '
                'chunk of ${result.chunks!.map((c) => queryCoverage(q, c)).reduce((a, b) => a > b ? a : b)}, '
                'so the excerpt is the top of the document');
        expect(excerpt, isNot(contains(_figure)));
      }
    });

    test('the escape hatch is a chunk that TIES, which needs near-verbatim '
        'phrasing', () {
      // Stated so the boundary is on record rather than implied: when one
      // chunk does contain every trigram the page does, ties break toward
      // the earlier candidate and the chunk wins. That is the only way the
      // whole-page candidate loses.
      const verbatimish = 'estimated population Tokyo metropolitan area 2025';
      final result = buildResult();
      final best = result.chunks!
          .map((c) => queryCoverage(verbatimish, c))
          .reduce((a, b) => a > b ? a : b);

      expect(best, queryCoverage(verbatimish, result.pageContent!),
          reason: 'a chunk matched the whole page\'s score exactly');
      expect(selectSupportingExcerpt(candidatesFor(result), verbatimish),
          contains(_figure),
          reason: 'and only then does the ledger quote the evidence');
    });
  });

  group('the sidebar reaches the ledger, the brief and the system prompt', () {
    /// Drives a real SearchAgent for one search round and returns the
    /// research brief handed to the SECOND turn — the one that has seen the
    /// search results. ChatProvider appends this string to the system
    /// prompt (chat_provider.dart:1166).
    Future<String> briefAfterOneSearch(WebSearchResult result) async {
      final briefs = <String>[];
      var turn = 0;
      final agent = SearchAgent(
        streamTurn: (request) async* {
          briefs.add(request.researchBrief);
          if (turn++ == 0) {
            yield OllamaMessage('',
                role: OllamaMessageRole.assistant,
                toolCalls: const [
                  OllamaToolCall(
                      name: 'web_search', arguments: {'query': _query}),
                ]);
          } else {
            yield OllamaMessage('done', role: OllamaMessageRole.assistant);
          }
        },
        search: (_) async => [result],
      );

      await agent.run(
        history: [
          OllamaMessage('How many people live in the Tokyo metropolitan '
              'area as of 2025?', role: OllamaMessageRole.user)
        ],
        listener: const SearchAgentListener(),
      );
      return briefs.last;
    }

    test('the checklist line cites the source and quotes the sidebar',
        () async {
      final brief = await briefAfterOneSearch(buildResult());

      final line = brief
          .split('\n')
          .firstWhere((l) => l.startsWith('- [x]'), orElse: () => '');
      expect(line, isNotEmpty, reason: 'the round recorded evidence');
      expect(line, contains('Excerpt: "Jump to content Main menu'),
          reason: 'the ledger line the model reads every turn presents the '
              'wiki sidebar as what source [1] said about "$_query"');
      expect(brief, isNot(contains(_figure)),
          reason: 'the figure the page actually contains never enters the '
              'brief, so once _compactStaleRounds rewrites this round\'s raw '
              'tool text to a citation-only line, the model\'s surviving '
              'record of source [1] is navigation chrome');
    });
  });
}
