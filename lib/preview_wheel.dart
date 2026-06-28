// Isolated preview harness for the wheeler model selector.
//
//   flutter run -d chrome -t lib/preview_wheel.dart
//
// Runs ModelSelectPage over the live mesh with a mock model list (including
// same-brand duplicates and unmapped fallbacks) and a light/dark/incognito
// toggle, with no Ollama connection / Hive / provider stack required.
import 'package:flutter/material.dart';

import 'package:llamaseek/Constants/gradient_presets.dart';
import 'package:llamaseek/Models/model_capabilities.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Pages/model_select_page/model_select_page.dart';
import 'package:llamaseek/Utils/mode_palette.dart';

void main() => runApp(const PreviewApp());

final GlobalKey<ScaffoldMessengerState> _messengerKey =
    GlobalKey<ScaffoldMessengerState>();

OllamaModel _mk(
  String name,
  String family,
  String params, {
  bool think = false,
  bool vision = false,
  bool tools = false,
}) =>
    OllamaModel(
      name: name,
      model: name,
      modifiedAt: DateTime.now(),
      size: 0,
      digest: name,
      parameterSize: params,
      family: family,
      capabilities: ModelCapabilities(
        completion: true,
        thinking: think,
        vision: vision,
        tools: tools,
      ),
    );

final List<OllamaModel> _mocks = [
  _mk('qwen3:8b', 'qwen', '8B', think: true, tools: true),
  _mk('qwen2.5-coder:7b', 'qwen', '7B', tools: true),
  _mk('deepseek-r1:8b', 'deepseek', '8B', think: true),
  _mk('deepseek-v3.1:671b', 'deepseek', '671B', tools: true),
  _mk('gemma3:12b', 'gemma', '12B', vision: true, tools: true),
  _mk('gemma3:27b', 'gemma', '27B', vision: true, tools: true),
  _mk('mistral-small3.2:24b', 'mistral', '24B', vision: true, tools: true),
  _mk('kimi-k2:1t', 'kimi', '1T', tools: true),
  _mk('minimax-m2', 'minimax', '', think: true, tools: true),
  _mk('nemotron:70b', 'nemotron', '70B', tools: true),
  _mk('glm-4.6', 'glm', '', think: true, tools: true),
  _mk('gemini-2.5-flash', 'gemini', '', vision: true, tools: true),
  _mk('essential-web:8b', 'essential', '8B'),
  _mk('llama3.2-vision:11b', 'llama', '11B', vision: true), // → Ollama fallback
  _mk('phi4:14b', 'phi', '14B', tools: true), // → Ollama fallback
];

enum _Mode { light, dark, incognito }

class PreviewApp extends StatefulWidget {
  const PreviewApp({super.key});
  @override
  State<PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<PreviewApp> {
  _Mode _mode = _Mode.light;

  AppMode get _appMode => switch (_mode) {
        _Mode.light => AppMode.normal,
        _Mode.dark => AppMode.dark,
        _Mode.incognito => AppMode.incognitoDark,
      };

  @override
  Widget build(BuildContext context) {
    final palette = resolvePalette(kGradientPresets[0], _appMode);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      theme: ThemeData(
        colorScheme: palette.scheme,
        useMaterial3: true,
        fontFamily: 'PingFang SC',
        appBarTheme: const AppBarTheme(centerTitle: true),
      ),
      home: Stack(
        children: [
          ModelSelectPage(
            models: _mocks,
            currentModelName: 'gemma3:12b',
            onConfirm: (m) => _messengerKey.currentState
              ?..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: Text('Selected ${m.name}'),
                duration: const Duration(milliseconds: 1400),
              )),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _ModeToggle(
                  mode: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final _Mode mode;
  final ValueChanged<_Mode> onChanged;
  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget btn(_Mode m, IconData icon) {
      final on = m == mode;
      return IconButton(
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        onPressed: () => onChanged(m),
        icon: Icon(icon,
            color: on ? cs.primary : cs.onSurface.withValues(alpha: 0.45)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(_Mode.light, Icons.light_mode_outlined),
          btn(_Mode.dark, Icons.dark_mode_outlined),
          btn(_Mode.incognito, Icons.visibility_off_outlined),
        ],
      ),
    );
  }
}
