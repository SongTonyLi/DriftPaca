import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'package:llamaseek/Models/model_capabilities.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/database_service.dart';
import 'package:llamaseek/Services/memory_service.dart';
import 'package:llamaseek/Services/ollama_service.dart';
import 'package:llamaseek/Widgets/model_selection_bottom_sheet.dart';

class _FakeDb extends DatabaseService {
  @override
  Future<void> open(String databaseFile) async {}

  @override
  Future<List<OllamaChat>> getAllChats() async => [];
}

class _FakeOllamaService extends OllamaService {
  _FakeOllamaService(this._models);

  final List<OllamaModel> _models;

  @override
  Future<List<OllamaModel>> listModels() async => _models;

  @override
  String? getCachedReadme(String modelName) => 'readme for $modelName';

  @override
  Future<String?> fetchModelReadme(String modelName) async =>
      'readme for $modelName';
}

class _FakeChatProvider extends ChatProvider {
  _FakeChatProvider(List<OllamaModel> models)
      : super(
          ollamaService: _FakeOllamaService(models),
          databaseService: _FakeDb(),
          memoryService: MemoryService(db: _FakeDb()),
        );
}

OllamaModel _mk(String name, String family) => OllamaModel(
      name: name,
      model: name,
      modifiedAt: DateTime(2024, 1, 1),
      size: 2 * 1024 * 1024 * 1024,
      digest: 'digest-$name',
      parameterSize: '8B',
      family: family,
      quantizationLevel: 'Q4_K_M',
      format: 'gguf',
      contextLength: 32768,
      capabilities: ModelCapabilities(
          completion: true, thinking: true, vision: false, tools: true),
    );

final _models = [
  _mk('qwen3:8b', 'qwen'),
  _mk('deepseek-r1:8b', 'deepseek'),
  _mk('llama3.2:3b', 'llama'),
];

Widget _host(Widget child) {
  return MaterialApp(
    home: ChangeNotifierProvider<ChatProvider>.value(
      value: _FakeChatProvider(_models),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('g09_sheet_test').path);
    await Hive.openBox('settings');
  });

  setUp(() => Hive.box('settings').clear());

  testWidgets(
      'ListView is driven by the sheet scrollController from DraggableScrollableSheet',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(
      ModelSelectionBottomSheet(
        title: 'Select model',
        scrollController: controller,
      ),
    ));
    await tester.pump();

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.controller, same(controller),
        reason:
            'the DraggableScrollableSheet scrollController must be attached to '
            'the inner ListView so the sheet can collapse and pull-to-refresh works');

    final scrollable = tester.widget<Scrollable>(find.byType(Scrollable).last);
    expect(scrollable.controller, same(controller));
  });

  testWidgets(
      'info-card transition reuses its curves across frames instead of '
      'allocating a fresh CurvedAnimation per frame', (tester) async {
    await tester.pumpWidget(_host(
      const ModelSelectionBottomSheet(title: 'Select model'),
    ));
    await tester.pump();

    final tile = find.text('qwen3:8b');
    expect(tile, findsWidgets);
    await tester.fling(tile.first, const Offset(-120, 0), 800);
    await tester.pump();

    // Sample the fade animation partway through the open transition and again
    // one frame later. A per-frame CurvedAnimation allocation (the leak) yields
    // a different object each frame; reusing a single owned instance keeps its
    // identity stable.
    await tester.pump(const Duration(milliseconds: 120));
    final firstOpacity = tester
        .widget<FadeTransition>(find.byType(FadeTransition).last)
        .opacity;
    await tester.pump(const Duration(milliseconds: 60));
    final secondOpacity = tester
        .widget<FadeTransition>(find.byType(FadeTransition).last)
        .opacity;
    expect(secondOpacity, same(firstOpacity),
        reason:
            'the transition must reuse one CurvedAnimation across frames rather '
            'than leaking a new listener-registered instance every frame');

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('SPECIFICATIONS'), findsOneWidget);

    // Opening and dismissing repeatedly must stay clean once the curves are
    // owned and disposed with the transition.
    for (var i = 0; i < 4; i++) {
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('SPECIFICATIONS'), findsNothing);

      await tester.fling(tile.first, const Offset(-120, 0), 800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('SPECIFICATIONS'), findsOneWidget);
    }

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
  });
}
