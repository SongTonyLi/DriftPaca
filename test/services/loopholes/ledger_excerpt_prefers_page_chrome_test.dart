/// Regression: the research ledger's supporting excerpt is the passage that
/// made the source win, not the top of the fetched page (its navigation
/// chrome).
///
/// Two decoupled defects had to be closed to get here, and this file pins
/// both because either one alone reopens the hole.
///
/// 1. A page was ranked against its own chunks.
///    `SearchAgent._executeToolCalls` built the candidate list as
///    `[...?r.chunks, r.pageContent, r.snippet]` — the whole extracted page
///    as one candidate alongside the chunks it was split into. Ranking is
///    `queryCoverage` (text_similarity.dart:69-79), asymmetric containment
///    with only the QUERY's trigram count as the denominator, so a superset
///    text can never score below any of its parts: `pageContent` (up to
///    `_maxPageContentLength` = 200,000 chars) beat every chunk unless one
///    single 1,500-char chunk happened to hold 100% of the query's
///    trigrams. Worse, candidates are pooled across ALL of a round's
///    results and ties break toward the earlier candidate, so several pages
///    saturating at 1.0 meant the evidence was simply the first result's.
///    `SearchAgent.excerptCandidates` now applies the precedence
///    `WebSearchService.formatResultsAsContext` already used for the same
///    data (web_search_service.dart:302-306) — chunks when the page was
///    chunked, else the page, else the snippet — so a page and its own
///    chunks are never siblings in one ranking.
///
/// 2. The scoring window and the returned window were decoupled.
///    `selectSupportingExcerpt` judged a candidate on its entire length and
///    then returned `best.substring(0, 220)` — the first 220 characters of
///    the winner, wherever the query's terms actually were. That is exactly
///    the failure `_maxPageContentLength`'s own doc comment
///    (web_search_service.dart:44-55) records as fixed for CHUNK ranking —
///    "the ranker was picking the best of several thousand characters of
///    nothing" — reintroduced one level down, and it survives fixing (1):
///    with only the page dropped, four of the five phrasings below still
///    quoted 220 characters that do not contain the answer. It now scores
///    the winner's boundary-aligned <=220-char windows and quotes the one
///    that earned the score, marking elided sides with `...`.
///
/// The excerpt this produces is what `ResearchLedger.recordEvidence` stores
/// for the life of the run, what `_checklistLine` renders on every `[x]`
/// line as `Excerpt: <untrusted-excerpt>…</untrusted-excerpt>` (declared
/// untrusted once per brief by `ResearchLedger.excerptWarning` — see
/// test/services/search_loop_loophole_test.dart), what `ChatProvider`
/// appends to the SYSTEM prompt every turn, and the only per-sub-goal
/// evidence text that survives `_compactStaleRounds`. Which bytes get
/// promoted is therefore still worth pinning: framing says the passage is
/// somebody's web page, not that it is the RIGHT passage.
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

/// The candidate list for a single result, taken from PRODUCTION rather
/// than restated here. This helper used to hand-copy the list literal out
/// of `search_agent.dart`, which is precisely how a test can keep passing
/// while the code it claims to describe moves: the copy is what the test
/// measures, not the shipped builder. Delegating means a future edit to
/// the real precedence rule is felt here immediately.
List<String> candidatesFor(WebSearchResult r) =>
    SearchAgent.excerptCandidates(r);

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
  group('the whole page is never ranked against its own chunks', () {
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
              'split from saturates at 1.0 — this is the property that '
              'makes the precedence rule necessary, not a bug in the score');
      expect(bestChunkScore, lessThan(pageScore),
          reason: 'no single 1500-char chunk holds 100% of the query\'s '
              'trigrams (best was $bestChunkScore), so a page offered '
              'alongside its own chunks would win outright and no chunk '
              'could ever be quoted; excerptCandidates keeps them apart');
    });

    test('the chosen excerpt is the passage that carries the answer', () {
      final result = buildResult();
      final excerpt = selectSupportingExcerpt(candidatesFor(result), _query);

      expect(excerpt, isNotNull);
      expect(excerpt!, contains(_figure),
          reason: 'the answering sentence is '
              '${result.pageContent!.indexOf(_figure)} chars into a '
              '${result.pageContent!.length}-char document; the excerpt is '
              'now the window that earned the score, not the winner\'s '
              'first 220 characters');
      expect(excerpt, isNot(startsWith('Jump to content')),
          reason: 'quoting from character 0 of a reference page is how the '
              'ledger used to record navigation chrome as evidence');
      expect(excerpt, isNot(contains('Main menu')),
          reason: 'no part of the sidebar survives into the record');
    });

    test('the returned text is what made the candidate win', () {
      final result = buildResult();
      final excerpt = selectSupportingExcerpt(candidatesFor(result), _query)!;

      final scoreOfWhatWasReturned = queryCoverage(_query, excerpt);
      final scoreOfOldHeadOfPage =
          queryCoverage(_query, result.pageContent!.substring(0, 220));

      expect(scoreOfWhatWasReturned, greaterThan(0.9),
          reason: 'the bytes actually stored as evidence score '
              '$scoreOfWhatWasReturned against the query that selected '
              'them — the ranking now describes the text it hands back');
      expect(scoreOfWhatWasReturned, greaterThan(scoreOfOldHeadOfPage),
          reason: 'the head of the page, which the old code returned, '
              'scores only $scoreOfOldHeadOfPage against the same query');
    });

    test('the whole-page candidate can no longer displace the answering chunk',
        () {
      final result = buildResult();
      final chunks = result.chunks!;

      final answerChunks = chunks
          .where((c) =>
              c.contains(_figure) && queryCoverage(_query, c) > 0.9)
          .toList();
      expect(answerChunks, isNotEmpty,
          reason: 'a chunk carrying the actual figure scores above 0.9 — it '
              'used to lose only because the superset it came from '
              'scored 1.0');

      expect(candidatesFor(result), isNot(contains(result.pageContent)),
          reason: 'chunks exist, so the page is not offered beside them');
      expect(
        selectSupportingExcerpt(candidatesFor(result), _query),
        selectSupportingExcerpt(<String>[...chunks, result.snippet], _query),
        reason: 'the production candidate list and a hand-built chunks-only '
            'list now agree — the inverse of what this file used to prove, '
            'where the single extra whole-page entry turned the evidence '
            'into sidebar links',
      );
    });
  });

  group('this is the normal case, not a knife-edge one', () {
    // The fix must not need the query tuned to the document either. Every
    // ordinary phrasing of the same user question has to land on the same
    // answering passage, including ones whose trigrams are nowhere near
    // packed into a single window.
    test('five natural phrasings of one question all yield the answering '
        'passage', () {
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
        expect(excerpt, contains(_figure),
            reason: 'query "$q": the chosen window scores '
                '${queryCoverage(q, excerpt)} against it, versus '
                '${queryCoverage(q, result.pageContent!.substring(0, 220))} '
                'for the head of the page the old code quoted');
        expect(excerpt, isNot(startsWith('Jump to content')));
      }
    });

    test('the result no longer depends on how closely the query is phrased',
        () {
      // Before the fix the only way a chunk beat the whole page was by
      // TYING its containment score, which took near-verbatim phrasing.
      // Both ends of that spectrum now land on the answer, so the tie is
      // no longer the escape hatch it used to be.
      const verbatimish = 'estimated population Tokyo metropolitan area 2025';
      const loosest = 'Tokyo population';
      final result = buildResult();

      for (final q in const [verbatimish, loosest]) {
        final excerpt = selectSupportingExcerpt(candidatesFor(result), q)!;
        expect(excerpt, contains(_figure),
            reason: 'query "$q" quotes the evidence; note the two windows '
                'are not the same bytes — the window is chosen per query, '
                'so this is not one fixed answer being returned twice');
        expect(excerpt, isNot(startsWith('Jump to content')));
      }
    });
  });

  group('the evidence reaches the ledger, the brief and the system prompt',
      () {
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

    test('the checklist line cites the source and quotes the answering '
        'passage', () async {
      final brief = await briefAfterOneSearch(buildResult());

      final line = brief
          .split('\n')
          .firstWhere((l) => l.startsWith('- [x]'), orElse: () => '');
      expect(line, isNotEmpty, reason: 'the round recorded evidence');
      expect(line, contains('Excerpt: <untrusted-excerpt>'),
          reason: 'the quoted evidence is fenced as untrusted page text');
      expect(line, contains(_figure),
          reason: 'the ledger line the model reads every turn presents the '
              'answering sentence as what source [1] said about "$_query"');
      expect(brief, contains(_figure),
          reason: 'so once _compactStaleRounds rewrites this round\'s raw '
              'tool text to a citation-only line, the model\'s surviving '
              'record of source [1] still carries the figure');
      expect(brief, isNot(contains('Jump to content')),
          reason: 'and none of the page\'s navigation chrome is presented '
              'as evidence anywhere in the brief');
    });
  });
}
