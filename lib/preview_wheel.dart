// Isolated preview harness for the wheeler model selector.
//
//   flutter run -t lib/preview_wheel.dart            (simulator / device)
//   flutter run -d chrome -t lib/preview_wheel.dart  (localhost)
//
// Shows a stand-in welcome page; tapping the model chip PUSHES the wheeler as a
// subpage (exactly like the real app), which pops back with the chosen model —
// so the welcome page is preserved. Uses mock models (incl. same-brand dupes and
// unmapped fallbacks) and a light/dark/incognito toggle. No Ollama/Hive needed.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:llamaseek/Constants/brand_logos.dart';
import 'package:llamaseek/Constants/gradient_presets.dart';
import 'package:llamaseek/Models/model_capabilities.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Pages/model_select_page/model_select_page.dart';
import 'package:llamaseek/Utils/mode_palette.dart';

void main() => runApp(const PreviewApp());

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
      size: 4 * 1024 * 1024 * 1024,
      digest: name,
      parameterSize: params,
      family: family,
      quantizationLevel: 'Q4_K_M',
      format: 'gguf',
      contextLength: 32768,
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
  OllamaModel _selected = _mocks[4]; // gemma3:12b

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
      theme: ThemeData(
        colorScheme: palette.scheme,
        useMaterial3: true,
        fontFamily: 'PingFang SC',
        appBarTheme: const AppBarTheme(centerTitle: true),
      ),
      home: _WelcomeScreen(
        selected: _selected,
        mode: _mode,
        onModeChanged: (m) => setState(() => _mode = m),
        onPicked: (m) => setState(() => _selected = m),
      ),
    );
  }
}

/// Stand-in welcome page. The wheeler is reached by pushing it as a subpage, so
/// popping it returns here — the welcome page is never replaced.
class _WelcomeScreen extends StatelessWidget {
  final OllamaModel selected;
  final _Mode mode;
  final ValueChanged<_Mode> onModeChanged;
  final ValueChanged<OllamaModel> onPicked;
  const _WelcomeScreen({
    required this.selected,
    required this.mode,
    required this.onModeChanged,
    required this.onPicked,
  });

  Future<void> _pick(BuildContext context) async {
    final picked = await Navigator.of(context).push<OllamaModel>(
      PageRouteBuilder<OllamaModel>(
        transitionDuration: const Duration(milliseconds: 340),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, __, ___) => ModelSelectPage(
          models: _mocks,
          currentModelName: selected.name,
        ),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          child: child,
        ),
      ),
    );
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [cs.surface, cs.surfaceContainerHighest],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/llama.png',
                      height: 132, filterQuality: FilterQuality.medium),
                  const SizedBox(height: 22),
                  Text('DriftPaca',
                      style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                  const SizedBox(height: 6),
                  Text('welcome page · the selector opens as a subpage',
                      style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.55))),
                  const SizedBox(height: 34),
                  _ModelChip(model: selected, onTap: () => _pick(context)),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _ModeToggle(mode: mode, onChanged: onModeChanged),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The "current model" chip — tapping it opens the wheeler (like the app bar).
class _ModelChip extends StatelessWidget {
  final OllamaModel model;
  final VoidCallback onTap;
  const _ModelChip({required this.model, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brand = brandForModel(model);
    return Material(
      color: cs.surface.withValues(alpha: 0.7),
      shape: StadiumBorder(
        side: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: SvgPicture.asset(
                  brand.asset,
                  fit: BoxFit.contain,
                  colorFilter: brand.tinted
                      ? ColorFilter.mode(
                          cs.onSurface.withValues(alpha: 0.8), BlendMode.srcIn)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Text(model.name,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
              const SizedBox(width: 8),
              Icon(Icons.expand_more,
                  size: 18, color: cs.onSurface.withValues(alpha: 0.5)),
            ],
          ),
        ),
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
