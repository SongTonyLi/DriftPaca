/// What a research run is doing right now.
///
/// Every value is a seam SearchAgent already had — a model call, a search,
/// a wait on the user — given a name so the UI can say what the run is
/// busy with instead of showing an undifferentiated spinner for the whole
/// run. The order of the values is the order a straightforward run passes
/// through them, which is also the order `search_agent_test.dart` asserts.
enum ResearchPhase {
  /// Before `deriveGoal` — a whole model request whose only visible effect
  /// used to be a ledger panel that appeared to be doing nothing.
  framingGoal,

  /// Inside `SearchAgent._clarify`, while `askClarification` waits. The one
  /// phase where the run is blocked on a person rather than a machine.
  awaitingClarification,

  /// At the start of every turn, before `streamTurn` yields anything.
  thinking,

  /// In `_executeToolCalls`, before each `search()` call.
  searching,

  /// A search's URLs are known and their pages are being fetched. The one
  /// phase SearchAgent cannot see — URL discovery happens inside the
  /// caller's `search` implementation — so ChatProvider's search closure
  /// reports it from `onUrlsKnown`.
  reading,

  /// Before `assessCoverage` — the isolated call that judges a drafted
  /// answer against the objective.
  checkingCoverage,

  /// With `onAnswerStart`: the model is streaming prose, not tool calls.
  drafting,

  /// With `onResearchDone`, whatever the termination reason.
  done,
}

extension ResearchPhaseLabel on ResearchPhase {
  /// Short present-tense description shown in the activity strip and the
  /// composer hint. Written for someone watching a run, not for a log.
  String get label => switch (this) {
        ResearchPhase.framingGoal => 'Framing the research goal',
        ResearchPhase.awaitingClarification => 'Waiting for your answer',
        ResearchPhase.thinking => 'Thinking',
        ResearchPhase.searching => 'Searching',
        ResearchPhase.reading => 'Reading sources',
        ResearchPhase.checkingCoverage => 'Checking the answer against the goal',
        ResearchPhase.drafting => 'Writing the answer',
        ResearchPhase.done => 'Done',
      };
}
