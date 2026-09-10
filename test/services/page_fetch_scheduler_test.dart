import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/page_fetch_outcome.dart';
import 'package:llamaseek/Services/page_fetch_scheduler.dart';

PageFetchOutcome ok() =>
    const PageFetchOutcome(state: PageFetchState.extracted, elapsed: Duration.zero, text: 'evidence');

void main() {
  testWidgets('replaces failures within concurrency and restores candidate order', (tester) async {
    final pending = <String, Completer<PageFetchOutcome>>{};
    final result = const PageFetchScheduler(concurrency: 2, targetPages: 2).run(['a', 'b', 'c', 'd'],
        fetch: (url, timeout, cancel) => (pending[url] = Completer<PageFetchOutcome>()).future);
    expect(pending.keys, ['a', 'b']);
    pending['b']!.complete(ok());
    await tester.pump();
    expect(pending.keys, ['a', 'b']);
    pending['a']!
        .complete(const PageFetchOutcome(state: PageFetchState.httpError, elapsed: Duration.zero, httpStatus: 403));
    await tester.pump();
    expect(pending.keys, ['a', 'b', 'c']);
    pending['c']!.complete(ok());
    await tester.pump();
    final outcomes = await result;
    expect(outcomes.keys, ['a', 'b', 'c']);
    expect(outcomes.values.where((o) => o.isSuccess), hasLength(2));
  });

  testWidgets('deadline retains completed evidence and ignores late completion', (tester) async {
    final pending = <String, Completer<PageFetchOutcome>>{};
    final callbacks = <String>[];
    final result = const PageFetchScheduler(budget: Duration(seconds: 1)).run(['a', 'b', 'c', 'd'],
        fetch: (url, timeout, cancel) => (pending[url] = Completer<PageFetchOutcome>()).future,
        onCompleted: (url, outcome) => callbacks.add(url));
    pending['a']!.complete(ok());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final outcomes = await result;
    expect(outcomes['a']!.isSuccess, isTrue);
    expect(outcomes['b']!.state, PageFetchState.budgetExpired);
    final count = callbacks.length;
    pending['b']!.complete(ok());
    await tester.pump();
    expect(callbacks, hasLength(count));
    expect(outcomes['b']!.state, PageFetchState.budgetExpired);
  });

  testWidgets('cancellation terminates active fetches and never starts queued work', (tester) async {
    var cancelled = false;
    var starts = 0;
    final result = const PageFetchScheduler(concurrency: 1).run(['a', 'b'],
        isCancelled: () => cancelled,
        fetch: (url, timeout, cancel) {
          starts++;
          return Completer<PageFetchOutcome>().future;
        });
    cancelled = true;
    await tester.pump(const Duration(milliseconds: 100));
    expect((await result)['a']!.state, PageFetchState.cancelled);
    expect(starts, 1);
  });
}
