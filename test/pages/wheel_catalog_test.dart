import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/model_capabilities.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Pages/model_select_page/wheel_catalog.dart';

OllamaModel _mk(String name, String family) => OllamaModel(
      name: name,
      model: name,
      modifiedAt: DateTime(2024, 1, 1),
      size: 0,
      digest: name,
      parameterSize: '',
      family: family,
      format: 'openrouter',
      capabilities: const ModelCapabilities(completion: true),
    );

void main() {
  test('small catalogs still use one wheel node per brand',
      () {
    final models = [
      _mk('qwen3:8b', 'qwen'),
      _mk('qwen3:14b', 'qwen'),
      _mk('llama3.2:3b', 'llama'),
    ];

    final catalog = WheelCatalog.fromModels(models, selectedName: 'qwen3:14b');

    expect(catalog.entries, hasLength(2));
    expect(catalog.entries.map((e) => e.brandKey), ['qwen', 'llama']);
    expect(catalog.entries.first.models.map((m) => m.name), [
      'qwen3:8b',
      'qwen3:14b',
    ]);
    expect(catalog.dockedModel.name, 'qwen3:14b');
    expect(catalog.entries.first.brand.label, 'Qwen');
    expect(catalog.entries.first.node.label, 'Qwen');
  });

  test('large OpenRouter catalogs collapse to one node per brand',
      () {
    final models = [
      for (var i = 0; i < 12; i++) _mk('openai/gpt-$i', 'openai'),
      for (var i = 0; i < 12; i++) _mk('anthropic/claude-$i', 'anthropic'),
      for (var i = 0; i < 12; i++) _mk('x-ai/grok-$i', 'x-ai'),
      for (var i = 0; i < 8; i++) _mk('mistralai/mistral-$i', 'mistral'),
    ];
    expect(models, hasLength(44));

    final catalog = WheelCatalog.fromModels(models);

    expect(catalog.entries, hasLength(4));
    expect(catalog.entries.map((e) => e.brandKey), [
      'openai',
      'anthropic',
      'grok',
      'mistral',
    ]);
    expect(catalog.entries.first.models, hasLength(12));
    expect(catalog.entries[2].brandKey, 'grok');
    expect(catalog.entries[2].models, hasLength(12));
  });

  test('selecting a brand keeps the previously docked model of that brand',
      () {
    final models = [
      for (var i = 0; i < 10; i++) _mk('openai/gpt-$i', 'openai'),
      for (var i = 0; i < 10; i++) _mk('anthropic/claude-$i', 'anthropic'),
    ];
    final catalog = WheelCatalog.fromModels(models, selectedName: 'anthropic/claude-4');

    expect(catalog.selectedIndex, 1);
    expect(catalog.dockedModel.name, 'anthropic/claude-4');
    expect(catalog.siblingsOfDocked.map((m) => m.name), contains('anthropic/claude-0'));
    expect(catalog.siblingsOfDocked, hasLength(10));
  });
}
