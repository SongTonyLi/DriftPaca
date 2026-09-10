/// Live end-to-end sweep of the research loop across several OpenRouter
/// models, run against the real web.
///
/// The existing `agentic_loop_live_test.dart` answers "does the loop work
/// on the one model we built it against". This answers a different and
/// harder question: which of the harness's convergence rules are model
/// -independent, and which are really a gpt-oss:120b behaviour the rules
/// were shaped around. A rule that only holds for one model is a loophole
/// for every other one.
///
/// Unlike that test, this one wires the agent the way ChatProvider does —
/// goal derivation, the clarification hook, the completeness gate, and the
/// real tool-policy system prompt — so what is under test is the shipped
/// harness rather than a stripped-down stand-in. The three prompts are
/// imported from chat_provider, not copied, so this cannot silently drift
/// from production.
///
/// Excluded from the normal gate: it costs money and hits the live web.
/// Run it explicitly:
///
///   ./tool/run_search_loop_sweep.sh
///
/// or directly:
///
///   OPENROUTER_API_KEY=... flutter test \
///     test/integration/openrouter_search_loop_live_test.dart
///
/// The key is read from the environment and must never be committed.
///
/// Env knobs:
///   OPENROUTER_API_KEY  required; the sweep skips entirely without it
///   OR_MODELS           comma-separated OpenRouter model ids (default: the
///                       four in [_defaultModels])
///   OR_PROBES           comma-separated probe ids (default: all of them)
///   OR_CELL_MINUTES     backstop per (model, probe) cell; must stay well
///                       above OR_TURN_IDLE_SECONDS (default: 6)
///   OR_TURN_IDLE_SECONDS
///                       SearchAgent.turnIdleBudget for the sweep — how long
///                       a turn may deliver nothing before the agent ends it
///                       (default: SearchAgent.defaultTurnIdleBudget)
///   OR_REPORT           where to write the JSON report
///                       (default: build/search_loop_sweep.json)
@Tags(['live'])
@Timeout(Duration(hours: 2))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Models/ollama_tool.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/ollama_service.dart';
import 'package:llamaseek/Services/search_agent.dart';
import 'package:llamaseek/Services/web_search_service.dart';
import 'package:llamaseek/Utils/coverage_gaps.dart';
import 'package:llamaseek/Utils/research_goal.dart';

final _apiKey = Platform.environment['OPENROUTER_API_KEY'] ?? '';

/// One per family the sweep is asked about. Flash/fast tier where the
/// family has one, so the comparison is between peers rather than between
/// a frontier model and a small one.
const _defaultModels = <String>[
  'moonshotai/kimi-k3',
  'google/gemini-3.8-flash',
  'deepseek/deepseek-v4-flash',
  'qwen/qwen3.8-flash',
];

List<String> get _models {
  final raw = Platform.environment['OR_MODELS'] ?? '';
  if (raw.trim().isEmpty) return _defaultModels;
  return [
    for (final m in raw.split(','))
      if (m.trim().isNotEmpty) m.trim()
  ];
}

/// A question chosen to put pressure on one specific part of the harness.
class _Probe {
  final String id;

  /// What about the loop this question is designed to stress.
  final String targets;
  final String question;

  /// Fewest searches a correct run needs. 0 means "a run that answers
  /// without searching is a finding, not a failure" — see [_Probe.single].
  final int minSearches;

  /// Substrings the answer must contain, case-insensitively, for the run to
  /// count as having actually answered the question. Each entry is a list of
  /// acceptable spellings for one required fact.
  final List<List<String>> mustMention;

  const _Probe({
    required this.id,
    required this.targets,
    required this.question,
    required this.minSearches,
    this.mustMention = const [],
  });
}

const _probes = <_Probe>[
  // The baseline the harness was built against: the second fact cannot be
  // named until the first is resolved, so one search cannot answer it.
  _Probe(
    id: 'multihop',
    targets: 'does the loop actually iterate, and does it stop because it '
        'converged rather than because a cap fired',
    question:
        'Which country won the most gold medals at the 2024 Summer Olympics, '
        'and what is the current population of that country\'s capital city?',
    minSearches: 2,
    mustMention: [
      ['united states', 'usa', 'u.s.', 'america'],
      ['washington'],
    ],
  ),
  // The sharpest structural probe. Four entities and no digits anywhere in
  // the question, so every "population of <city>" query trigram-matches the
  // last one and nothing in the string shape separates four cities from one
  // question reworded four times. What separates them is that the user NAMED
  // all four: ResearchLedger._isDifferentRequestedInstance reads the
  // capitalised names out of the question alongside the digit-runs it has
  // always read, so each city opens its own sub-goal with its own
  // per-sub-goal budget and its own checklist line. See
  // test/services/search_loop_loophole_test.dart for the offline proof.
  _Probe(
    id: 'breadth',
    targets: 'ledger sub-goal grouping, the per-sub-goal budget, and the '
        'two-per-round batch cap, all at once',
    question: 'What is the current population of Tokyo, Delhi, Shanghai and '
        'Sao Paulo? Give the figure for each city.',
    minSearches: 2,
    mustMention: [
      ['tokyo'],
      ['delhi'],
      ['shanghai'],
      ['sao paulo', 'são paulo'],
    ],
  ),
  // One lookup, plainly a current fact. Two things are being watched: that
  // the model searches at all (SearchAgent has no mechanism forcing a first
  // search, and the completeness gate is gated on searchCount > 0, so a run
  // that answers from memory bypasses every check the harness has), and that
  // a one-hop question converges in one round instead of being padded out.
  _Probe(
    id: 'single',
    targets: 'does a trivially-searchable question get searched at all, and '
        'does a one-hop run converge in one round',
    question: 'What is the current price of gold per troy ounce in US dollars?',
    minSearches: 0,
    mustMention: [
      ['gold'],
    ],
  ),
  // One half findable, one half impossible. The tool policy says to state
  // plainly what could not be established; the coverage gate's prompt says
  // "A draft that could not determine a fact is NOT complete". Those two
  // rules disagree, and this question is where they collide.
  _Probe(
    id: 'unfindable',
    targets: 'termination when part of the question cannot be answered, and '
        'whether the completeness gate re-opens it as a gap',
    question: 'Who won the 2024 Nobel Prize in Literature, and who will win '
        'the 2027 Nobel Prize in Literature?',
    minSearches: 1,
    mustMention: [
      ['han kang'],
    ],
  ),
];

List<_Probe> get _selectedProbes {
  final raw = Platform.environment['OR_PROBES'] ?? '';
  if (raw.trim().isEmpty) return _probes;
  final wanted = {
    for (final p in raw.split(','))
      if (p.trim().isNotEmpty) p.trim()
  };
  return [
    for (final p in _probes)
      if (wanted.contains(p.id)) p
  ];
}

/// Everything observed about one (model, probe) run.
class _RunReport {
  final String model;
  final String probe;

  String? error;

  /// The cell backstop fired — meaning the agent's OWN turn deadline
  /// ([SearchAgent.turnIdleBudget]) did not end the run first. That is
  /// itself the failure, not a measurement: a stalled provider is supposed
  /// to come back as `reason: stalled` inside the harness.
  bool hung = false;
  Duration elapsed = Duration.zero;

  String objective = '';
  List<String> subQuestions = const [];
  String? clarificationQuestion;
  List<String> clarificationOptions = const [];

  final queries = <String>[];
  final skips = <({String query, String reason})>[];
  int coverageChecks = 0;
  List<String> coverageGaps = const [];

  int searchCount = 0;
  int sourceCount = 0;
  String reason = '';
  bool cancelled = false;
  String answer = '';

  /// `[N]` markers in the answer whose N is not a real source id.
  List<int> danglingCitations = const [];
  List<int> usedCitations = const [];

  /// Citation shapes the source-formatting prompt explicitly forbids, found
  /// in the answer anyway.
  List<String> malformedCitations = const [];

  /// Required facts from [_Probe.mustMention] the answer never states.
  List<String> missingFacts = const [];

  _RunReport(this.model, this.probe);

  /// Skip reasons bucketed by the harness rule that produced them, so the
  /// report can say WHICH rule fired rather than just how often something
  /// was refused.
  Map<String, int> get skipKinds {
    final counts = <String, int>{};
    for (final s in skips) {
      counts.update(_classifySkip(s.reason), (v) => v + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  Map<String, dynamic> toJson() => {
        'model': model,
        'probe': probe,
        if (error != null) 'error': error,
        'hung': hung,
        'elapsedSeconds': elapsed.inMilliseconds / 1000.0,
        'objective': objective,
        'subQuestions': subQuestions,
        'clarificationQuestion': clarificationQuestion,
        'clarificationOptions': clarificationOptions,
        'queries': queries,
        'skips': [
          for (final s in skips) {'query': s.query, 'reason': s.reason}
        ],
        'skipKinds': skipKinds,
        'coverageChecks': coverageChecks,
        'coverageGaps': coverageGaps,
        'searchCount': searchCount,
        'sourceCount': sourceCount,
        'terminationReason': reason,
        'cancelled': cancelled,
        'usedCitations': usedCitations,
        'danglingCitations': danglingCitations,
        'malformedCitations': malformedCitations,
        'missingFacts': missingFacts,
        'answer': answer,
      };
}

String _classifySkip(String reason) {
  if (reason.contains('already asked something very close')) return 'ledgerDupe';
  if (reason.contains('at most')) return 'roundBatchCapped';
  if (reason.contains('budget for this question')) return 'overBudget';
  if (reason.contains('No query provided')) return 'emptyQuery';
  if (reason.contains('Duplicate of another query')) return 'intraTurnDupe';
  if (reason.contains('rate-limiting')) return 'searchUnavailable';
  return 'other';
}

final _citation = RegExp(r'\[(\d{1,3})\]');

/// The forms `WebSearchService.formatResultsAsContext` explicitly tells the
/// model never to emit. Each one renders as literal text instead of a link,
/// so a model that uses them has cited nothing as far as the app is
/// concerned — which the harness currently never checks.
final _malformedCitationForms = <String, RegExp>{
  'fullwidth-brackets': RegExp(r'【\s*\d+'),
  'grouped-ids': RegExp(r'\[\s*\d+\s*[,，、]\s*\d+'),
  'labelled': RegExp(r'\[\s*(?:id|src|source|来源)\s*[:：]', caseSensitive: false),
  'parenthesised': RegExp(r'\(\s*(?:see\s+)?sources?\s+\d+\s*\)',
      caseSensitive: false),
  'backticked': RegExp(r'`\[\d+\]`'),
};

/// How long one (model, probe) cell may run before the sweep abandons it.
/// A BACKSTOP that must never fire: the agent bounds its own silent turns
/// now ([_turnIdleBudget]), so a cell that trips this has outlived the
/// deadline that was supposed to end it, and the assertion below fails it.
///
/// Six minutes by default. The only constraint that matters is that it stays
/// comfortably above the turn budget — a run may legitimately spend several
/// slow-but-alive turns, and each one gets its own idle window. Raise it with
/// OR_CELL_MINUTES for a model with a long time-to-first-token:
/// qwen3.8-flash on Alibaba can spend minutes queued behind
/// `: OPENROUTER PROCESSING` and then stream reasoning-only deltas for
/// minutes more, which is slow rather than stalled — the agent's idle
/// deadline is re-armed by every delta and so tells those apart.
final _cellBudget = Duration(
    minutes:
        int.tryParse(Platform.environment['OR_CELL_MINUTES'] ?? '') ?? 6);

/// The turn deadline the sweep runs the agent with, mirrored from
/// production's default rather than re-derived. Lower it with
/// OR_TURN_IDLE_SECONDS to make a stalling provider surface as
/// `reason: stalled` sooner.
final _turnIdleBudget = Duration(
    seconds: int.tryParse(
            Platform.environment['OR_TURN_IDLE_SECONDS'] ?? '') ??
        SearchAgent.defaultTurnIdleBudget.inSeconds);

final _reports = <_RunReport>[];

/// Collects a stream into one string, giving up after [budget]. Mirrors
/// ChatProvider._collectWithin, which is private.
///
/// The deadline is a real [Timer], not a check inside `await for`, for the
/// reason production's version documents: a stalled request delivers no
/// chunks by definition, so a per-chunk deadline cannot fire on exactly
/// the requests it exists to bound. An earlier version of this helper got
/// that wrong and hung a sweep cell for 17 minutes.
Future<String?> _collectWithin(
    Stream<OllamaMessage> stream, Duration budget) async {
  final buffer = StringBuffer();
  final finished = Completer<bool>();
  final timer = Timer(budget, () {
    if (!finished.isCompleted) finished.complete(false);
  });
  final subscription = stream.listen(
    (chunk) => buffer.write(chunk.content),
    onError: (_) {
      if (!finished.isCompleted) finished.complete(false);
    },
    onDone: () {
      if (!finished.isCompleted) finished.complete(true);
    },
    cancelOnError: true,
  );
  final completed = await finished.future;
  timer.cancel();
  await subscription.cancel();
  if (!completed) return null;
  final text = buffer.toString().trim();
  return text.isEmpty ? null : text;
}

Future<_RunReport> _runProbe(String model, _Probe probe) async {
  final report = _RunReport(model, probe.id);
  final started = DateTime.now();

  final ollama = OllamaService()
    ..isOpenRouterMode = true
    ..apiKey = _apiKey;

  final chat = OllamaChat(
    model: model,
    systemPrompt: toolPolicyInstruction(),
  );

  try {
    final agent = SearchAgent(
      // Cloud/OpenRouter never sends num_ctx, so production takes the
      // undivided defaults here — mirrored rather than re-derived.
      transcriptBudgetChars: SearchAgent.defaultTranscriptBudgetChars,
      minRawRounds: SearchAgent.defaultMinRawRounds,
      turnIdleBudget: _turnIdleBudget,
      deriveGoal: (userQuestion) async {
        final goalChat = OllamaChat(
          model: model,
          systemPrompt: goalDerivationInstruction(),
        );
        final reply = await _collectWithin(
          ollama.chatStream(
            [OllamaMessage(userQuestion, role: OllamaMessageRole.user)],
            chat: goalChat,
          ),
          const Duration(seconds: 60),
        );
        return reply == null ? null : parseResearchGoal(reply);
      },
      askClarification: (clarification) async {
        // Recorded, then skipped. A clarification on any of these four
        // questions is itself the finding — none of them is ambiguous —
        // and a sweep that blocked on one would just hang.
        report.clarificationQuestion = clarification.question;
        report.clarificationOptions = List.of(clarification.options);
        return const [];
      },
      assessCoverage: (request) async {
        report.coverageChecks++;
        final gateChat = OllamaChat(
          model: model,
          systemPrompt: coverageGateInstruction(),
        );
        final reply = await _collectWithin(
          ollama.chatStream(
            [
              OllamaMessage(
                'Question:\n${request.objective}\n\n'
                'Draft answer:\n${request.draftAnswer}',
                role: OllamaMessageRole.user,
              )
            ],
            chat: gateChat,
          ),
          const Duration(seconds: 60),
        );
        if (reply == null) return const [];
        final gaps = parseCoverageGaps(reply);
        report.coverageGaps = [...report.coverageGaps, ...gaps];
        return gaps;
      },
      streamTurn: (request) {
        final turnChat = request.researchBrief.isEmpty
            ? chat
            : OllamaChat(
                id: chat.id,
                model: chat.model,
                title: chat.title,
                systemPrompt:
                    '${chat.systemPrompt}\n\n${request.researchBrief}',
                options: chat.options,
              );
        return ollama.chatStream(
          request.history,
          chat: turnChat,
          extraMessages: request.transcript,
          tools: request.toolsEnabled
              ? const [OllamaToolDefinition.webSearch]
              : null,
        );
      },
      search: (req) => WebSearchService()
          .searchAndExtract(req.query, excludeUrls: req.excludeUrls),
    );

    // A BACKSTOP, not the sweep's real bound. The agent ends its own silent
    // turns now (SearchAgent.turnIdleBudget, wired above), so a provider
    // that opens a stream and goes quiet comes back here as an ordinary
    // outcome with `reason: stalled` — measured rather than waited out.
    //
    // This `.timeout` is kept only to stop one pathological cell eating the
    // whole sweep, and it is expected never to fire: a cell that trips it is
    // recorded as `hung` and asserted against below, because it means the
    // in-harness deadline failed. The abandoned future is still left
    // dangling, which is exactly why tripping this is a regression and not a
    // measurement.
    final outcome = await agent
        .run(
      history: [OllamaMessage(probe.question, role: OllamaMessageRole.user)],
      listener: SearchAgentListener(
        onSearchStart: report.queries.add,
        onSearchSkipped: (q, reason) =>
            report.skips.add((query: q, reason: reason)),
        onLedgerUpdate: (objective, snapshot) {
          report.objective = objective;
          report.subQuestions = [for (final g in snapshot) g.query];
        },
      ),
    )
        .timeout(_cellBudget, onTimeout: () {
      report.hung = true;
      throw TimeoutException(
          'the run outlived its own turn deadline — '
          'SearchAgent.turnIdleBudget (${_turnIdleBudget.inSeconds}s) did '
          'not fire inside ${_cellBudget.inMinutes} minutes',
          _cellBudget);
    });

    report.searchCount = outcome.searchCount;
    report.sourceCount = outcome.sourceUrls.length;
    report.reason = outcome.reason.name;
    report.cancelled = outcome.cancelled;
    report.answer = outcome.content;

    final cited = <int>{};
    for (final m in _citation.allMatches(outcome.content)) {
      cited.add(int.parse(m.group(1)!));
    }
    report.usedCitations = cited.toList()..sort();
    report.danglingCitations = [
      for (final id in report.usedCitations)
        if (!outcome.sourceUrls.containsKey(id)) id
    ];
    report.malformedCitations = [
      for (final entry in _malformedCitationForms.entries)
        if (entry.value.hasMatch(outcome.content)) entry.key
    ];

    final haystack = outcome.content.toLowerCase();
    report.missingFacts = [
      for (final alternatives in probe.mustMention)
        if (!alternatives.any(haystack.contains)) alternatives.first
    ];
  } catch (e) {
    report.error = e.toString();
  }

  report.elapsed = DateTime.now().difference(started);
  return report;
}

String _matrix(List<_RunReport> reports) {
  final buffer = StringBuffer();
  buffer.writeln();
  buffer.writeln('=' * 108);
  buffer.writeln('SEARCH LOOP SWEEP');
  buffer.writeln('=' * 108);
  buffer.writeln('${'model'.padRight(28)}${'probe'.padRight(12)}'
      '${'srch'.padLeft(5)}${'skip'.padLeft(5)}${'src'.padLeft(5)}'
      '${'gate'.padLeft(5)}${'secs'.padLeft(6)}  ${'termination'.padRight(20)}'
      'flags');
  buffer.writeln('-' * 108);
  for (final r in reports) {
    final flags = <String>[
      if (r.hung) 'HUNG',
      if (r.error != null && !r.hung) 'ERROR',
      if (r.reason == 'stalled') 'stalled',
      if (r.error == null && r.searchCount == 0) 'no-search',
      if (r.missingFacts.isNotEmpty) 'missing:${r.missingFacts.length}',
      if (r.danglingCitations.isNotEmpty)
        'dangling:${r.danglingCitations.join("/")}',
      if (r.malformedCitations.isNotEmpty)
        'badcite:${r.malformedCitations.join("/")}',
      if (r.usedCitations.isEmpty && r.sourceCount > 0) 'uncited',
      if (r.clarificationQuestion != null) 'clarify',
      for (final e in r.skipKinds.entries) '${e.key}:${e.value}',
    ];
    buffer.writeln('${r.model.padRight(28)}${r.probe.padRight(12)}'
        '${r.searchCount.toString().padLeft(5)}'
        '${r.skips.length.toString().padLeft(5)}'
        '${r.sourceCount.toString().padLeft(5)}'
        '${r.coverageChecks.toString().padLeft(5)}'
        '${r.elapsed.inSeconds.toString().padLeft(6)}  '
        '${(r.error != null ? "-" : r.reason).padRight(20)}'
        '${flags.join(" ")}');
  }
  buffer.writeln('=' * 108);
  return buffer.toString();
}

void main() {
  final skipReason = _apiKey.isEmpty
      ? 'OPENROUTER_API_KEY not set — run ./tool/run_search_loop_sweep.sh to '
          'exercise the live sweep'
      : null;

  group('search loop sweep', () {
    for (final model in _models) {
      for (final probe in _selectedProbes) {
        test('$model / ${probe.id}', () async {
          final report = await _runProbe(model, probe);
          _reports.add(report);

          // ignore: avoid_print
          print('\n--- $model / ${probe.id} ---');
          // ignore: avoid_print
          print('  targets: ${probe.targets}');
          if (report.error != null) {
            // ignore: avoid_print
            print('  ERROR: ${report.error}');
          }
          // ignore: avoid_print
          print('  goal: ${report.objective}');
          for (final q in report.subQuestions) {
            // ignore: avoid_print
            print('    - $q');
          }
          if (report.clarificationQuestion != null) {
            // ignore: avoid_print
            print('  clarification asked: ${report.clarificationQuestion} '
                '${report.clarificationOptions}');
          }
          for (var i = 0; i < report.queries.length; i++) {
            // ignore: avoid_print
            print('  search ${i + 1}: ${report.queries[i]}');
          }
          for (final s in report.skips) {
            // ignore: avoid_print
            print('  skipped [${_classifySkip(s.reason)}]: ${s.query}');
          }
          if (report.coverageGaps.isNotEmpty) {
            // ignore: avoid_print
            print('  coverage gaps: ${report.coverageGaps}');
          }
          // ignore: avoid_print
          print('  searches=${report.searchCount} sources=${report.sourceCount} '
              'reason=${report.reason} elapsed=${report.elapsed.inSeconds}s');
          // ignore: avoid_print
          print('  citations=${report.usedCitations} '
              'dangling=${report.danglingCitations} '
              'malformed=${report.malformedCitations}');
          // ignore: avoid_print
          print('  answer: ${report.answer.replaceAll("\n", " ")}');

          // Pace the sweep: DuckDuckGo throttles a client that runs many
          // searches back to back, and a throttled run ends as
          // searchUnavailable, which would read as a harness finding when
          // it is really this test's own footprint.
          await Future.delayed(const Duration(seconds: 20));

          // Per-cell assertions. Kept few and behavioural — the sweep's
          // value is the report, and a cell that fails should mean the loop
          // genuinely misbehaved for this model, not that a fact moved.
          // Asserted before `error`, which the backstop's TimeoutException
          // also sets: "run threw" would be the true but useless account of
          // a cell whose real fault is that nothing inside the harness ended
          // it.
          expect(report.hung, isFalse,
              reason: 'the cell backstop fired — the agent failed to end its '
                  'own stalled turn, so a silent provider still hangs the '
                  'run instead of returning reason: stalled');
          expect(report.error, isNull, reason: 'run threw');
          // Unchanged on purpose: a genuinely silent provider now trips
          // these one turn budget after it goes quiet, with
          // reason: stalled, instead of holding the sweep for 16 minutes.
          expect(report.cancelled, isFalse);
          expect(report.answer.trim(), isNotEmpty,
              reason: 'run produced no answer at all');
          if (report.reason != SearchTerminationReason.searchUnavailable.name) {
            expect(report.searchCount,
                greaterThanOrEqualTo(probe.minSearches),
                reason: 'expected at least ${probe.minSearches} searches');
            expect(report.danglingCitations, isEmpty,
                reason: 'answer cites source ids that do not exist — the '
                    'markers render as dead links');
          }
        }, skip: skipReason);
      }
    }

    test('report', () async {
      final path = Platform.environment['OR_REPORT'] ??
          'build/search_loop_sweep.json';
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
        'generatedAt': DateTime.now().toIso8601String(),
        'models': _models,
        'probes': [
          for (final p in _selectedProbes)
            {'id': p.id, 'targets': p.targets, 'question': p.question}
        ],
        'runs': [for (final r in _reports) r.toJson()],
      }));
      // ignore: avoid_print
      print(_matrix(_reports));
      // ignore: avoid_print
      print('report written to $path');
    }, skip: skipReason);
  });
}
