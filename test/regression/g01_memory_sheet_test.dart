import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'package:llamaseek/Models/ephemeral_context.dart';
import 'package:llamaseek/Models/memory_topic.dart';
import 'package:llamaseek/Services/database_service.dart';
import 'package:llamaseek/Services/memory_service.dart';
import 'package:llamaseek/Widgets/memory_bottom_sheet.dart';

class _FakeDb extends DatabaseService {
  @override
  Future<List<MemoryTopic>> getAllTopics() async => [];

  @override
  Future<List<EphemeralContext>> getAllEphemeralContexts() async => [];
}

class _FakeMemoryService extends MemoryService {
  _FakeMemoryService() : super(db: _FakeDb());

  @override
  bool get isEnabled => true;

  @override
  bool get isUpdating => false;
}

MemorySection _profile(String label, String value) =>
    MemorySection(label: label, key: label.toLowerCase(), value: value);

Widget _host({
  required List<MemoryTopic> topics,
  List<EphemeralContext> ephemeral = const [],
  List<MemorySection>? profileSections,
  Future<void> Function(int id)? onDeleteTopic,
  int maxTotalTokens = 100000,
  bool disableAnimations = false,
  bool useFlatEditor = false,
}) {
  final service = _FakeMemoryService();
  return ChangeNotifierProvider<MemoryService>.value(
    value: service,
    child: MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showMemoryBottomSheet(
                    context,
                    title:
                        useFlatEditor ? 'Conversation Memory' : 'Agent Memory',
                    maxTotalTokens: maxTotalTokens,
                    sections: useFlatEditor
                        ? [_profile('Summary', 'Song')]
                        : const [],
                    onSave: (_) {},
                    profileSections: useFlatEditor
                        ? null
                        : profileSections ?? [_profile('Name', '')],
                    onSaveProfile: (_) {},
                    onSaveTopic: (topic) async => topic,
                    onDeleteTopic: onDeleteTopic ?? (_) async {},
                    onSaveEphemeral: (_) async {},
                    onDeleteEphemeral: (_) async {},
                    topics: topics,
                    ephemeralContexts: ephemeral,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('g01_mem_sheet_test').path);
    await Hive.openBox('settings');
  });

  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1200, 3600);
    view.devicePixelRatio = 3.0;
  });

  tearDown(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  testWidgets('deleting a newly-added topic (null id) removes it from the list',
      (tester) async {
    var deleteCalled = false;
    await tester.pumpWidget(_host(
      topics: [MemoryTopic(topicKey: 'Fresh topic', content: 'no id yet')],
      onDeleteTopic: (_) async => deleteCalled = true,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Topics (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Fresh topic'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Fresh topic'), findsNothing);
    expect(find.text('Topics (0)'), findsOneWidget);
    expect(deleteCalled, isFalse,
        reason: 'a topic with a null id cannot round-trip a DB delete');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissing the sheet mid-delete does not throw setState-after-dispose',
      (tester) async {
    final gate = Completer<void>();
    await tester.pumpWidget(_host(
      topics: [MemoryTopic(id: 7, topicKey: 'Stored topic', content: 'has id')],
      onDeleteTopic: (_) => gate.future,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Topics (1)'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pump();

    // Dismiss the sheet while the delete future is still in flight.
    Navigator.of(tester.element(find.text('open'))).pop();
    await tester.pumpAndSettle();

    // Complete the delete after the sheet is gone — the unguarded path
    // would call setState on a disposed State here.
    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('swiping off the Profile tab hides the profile token count',
      (tester) async {
    await tester.pumpWidget(_host(
      topics: const [],
      profileSections: [_profile('Name', 'Song lives in New York and codes Flutter.')],
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('tokens'), findsWidgets);

    // Swipe the TabBarView from Profile to Topics.
    await tester.fling(find.byType(TabBarView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.textContaining('tokens'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('over-limit warning is not rendered in raw orange in light mode',
      (tester) async {
    await tester.pumpWidget(_host(
      topics: const [],
      profileSections: [_profile('Name', 'Song lives in New York and codes Flutter every day.')],
      maxTotalTokens: 1,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final warning = tester.widget<Text>(
      find.textContaining('exceeds token limit'),
    );
    expect(warning.style!.color, isNot(Colors.orange));
    expect(tester.takeException(), isNull);
  });

  testWidgets('memory content switch skips animation with reduced motion',
      (tester) async {
    await tester.pumpWidget(_host(
      topics: const [],
      disableAnimations: true,
      useFlatEditor: true,
    ));
    await tester.tap(find.text('open'));
    await tester.pump();

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher).first,
    );
    expect(switcher.duration, Duration.zero);
  });
}
