import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llamaseek/Models/model_capabilities.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Pages/model_select_page/model_select_page.dart';

OllamaModel _mk(
  String name,
  String family, {
  bool think = false,
  bool vision = false,
  bool tools = false,
}) =>
    OllamaModel(
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
          completion: true, thinking: think, vision: vision, tools: tools),
    );

final _models = [
  _mk('qwen3:8b', 'qwen', think: true, tools: true),
  _mk('deepseek-r1:8b', 'deepseek', think: true),
  _mk('llama3.2:3b', 'llama', vision: true),
];

void _phoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(440, 940);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('builds, flips to the info window, and selects', (tester) async {
    _phoneSurface(tester);
    OllamaModel? picked;
    await tester.pumpWidget(MaterialApp(
      home: ModelSelectPage(
        models: _models,
        currentModelName: 'qwen3:8b',
        onConfirm: (m) => picked = m,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    // The current model is docked and the confirm pill is present.
    expect(find.text('Use this model'), findsOneWidget);
    expect(find.text('qwen3:8b'), findsWidgets);

    // Tap the info button → flip to the original info window.
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('SPECIFICATIONS'), findsOneWidget);
    expect(find.text('Select Model'), findsOneWidget);

    // Select from the info window.
    await tester.tap(find.text('Select Model'));
    await tester.pump();
    expect(picked, isNotNull);
    expect(picked!.name, 'qwen3:8b');
  });

  testWidgets('search filters the wheel and shows a no-match state',
      (tester) async {
    _phoneSurface(tester);
    await tester.pumpWidget(MaterialApp(
      home: ModelSelectPage(models: _models),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField), 'deepseek');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('deepseek-r1:8b'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('No models match'), findsOneWidget);
  });
}
