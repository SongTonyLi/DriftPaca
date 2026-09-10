import 'dart:async';
import 'package:llamaseek/Models/page_fetch_outcome.dart';

/// Bounds the entire page batch, including queued work. Outcomes are immutable
/// snapshots in discovery order; late HTTP completions cannot update the UI.
class PageFetchScheduler {
  final int concurrency;
  final int targetPages;
  final Duration budget;

  const PageFetchScheduler({this.concurrency = 3, this.targetPages = 8, this.budget = const Duration(seconds: 10)})
      : assert(concurrency > 0),
        assert(targetPages >= 0);

  Future<Map<String, PageFetchOutcome>> run(
    List<String> candidates, {
    required Future<PageFetchOutcome> Function(String url, Duration remaining, Future<void> cancelled) fetch,
    bool Function()? isCancelled,
    void Function(String url)? onStarted,
    void Function(String url, PageFetchOutcome outcome)? onCompleted,
  }) {
    final urls = candidates.toSet().toList();
    final done = Completer<Map<String, PageFetchOutcome>>();
    final stop = Completer<void>();
    final watch = Stopwatch()..start();
    final outcomes = <String, PageFetchOutcome>{};
    final active = <String>{};
    var next = 0;
    var successes = 0;
    Timer? deadline;
    Timer? poll;

    void finish([PageFetchState? reason]) {
      if (done.isCompleted) return;
      deadline?.cancel();
      poll?.cancel();
      if (reason != null) {
        for (final url in active) {
          outcomes[url] = PageFetchOutcome(state: reason, elapsed: watch.elapsed);
        }
      }
      // Mark terminal BEFORE callbacks/transport cancellation can complete work.
      done.complete(Map<String, PageFetchOutcome>.unmodifiable({
        for (final url in urls)
          if (outcomes.containsKey(url)) url: outcomes[url]!,
      }));
      stop.complete();
      if (reason != null) {
        for (final url in active) {
          onCompleted?.call(url, outcomes[url]!);
        }
      }
    }

    void pump() {
      if (done.isCompleted) return;
      if (isCancelled?.call() == true) {
        finish(PageFetchState.cancelled);
        return;
      }
      if (watch.elapsed >= budget) {
        finish(PageFetchState.budgetExpired);
        return;
      }
      while (active.length < concurrency && next < urls.length && successes + active.length < targetPages) {
        final url = urls[next++];
        active.add(url);
        onStarted?.call(url);
        // Future.sync also contains synchronous transport failures.
        Future.sync(() => fetch(url, budget - watch.elapsed, stop.future))
            .catchError((Object error) => PageFetchOutcome(state: PageFetchState.networkError, elapsed: watch.elapsed))
            .then((outcome) {
          if (done.isCompleted) return;
          active.remove(url);
          outcomes[url] = outcome;
          if (outcome.isSuccess) successes++;
          onCompleted?.call(url, outcome);
          pump();
        });
      }
      if (active.isEmpty) finish();
    }

    deadline = Timer(budget, () => finish(PageFetchState.budgetExpired));
    if (isCancelled != null) {
      poll = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (isCancelled()) finish(PageFetchState.cancelled);
      });
    }
    pump();
    return done.future;
  }
}
