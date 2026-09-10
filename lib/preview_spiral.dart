// Isolated preview harness for the halftone token-spiral background.
//
//   flutter run -t lib/preview_spiral.dart            (simulator / device)
//   flutter run -d chrome -t lib/preview_spiral.dart  (localhost)
//
// Shows FloatingGradientBackground under a stand-in conversation so the field
// can be judged for motion and for text legibility in every mode, without
// Ollama/Hive. The bottom bar switches mode, colour preset, and toggles the
// generating / welcome states. On the web the same switches can be preset with
// query parameters, e.g. `?mode=dark&preset=2&generating=1&controls=0`, which
// is how the screenshots in docs/ are taken.
import 'package:flutter/material.dart';

import 'package:llamaseek/Constants/gradient_presets.dart';
import 'package:llamaseek/Utils/mode_palette.dart';
import 'package:llamaseek/Widgets/floating_gradient_background.dart';

void main() => runApp(const SpiralPreviewApp());

const _modeNames = {
  AppMode.normal: 'light',
  AppMode.dark: 'dark',
  AppMode.incognitoLight: 'incognito-light',
  AppMode.incognitoDark: 'incognito-dark',
};

class SpiralPreviewApp extends StatefulWidget {
  const SpiralPreviewApp({super.key});

  @override
  State<SpiralPreviewApp> createState() => _SpiralPreviewAppState();
}

class _SpiralPreviewAppState extends State<SpiralPreviewApp> {
  late AppMode _mode;
  late int _preset;
  late bool _generating;
  late bool _welcome;
  late bool _controls;

  @override
  void initState() {
    super.initState();
    final q = Uri.base.queryParameters;
    _mode = _modeNames.entries
        .firstWhere((e) => e.value == q['mode'], orElse: () => _modeNames.entries.first)
        .key;
    _preset = (int.tryParse(q['preset'] ?? '') ?? 0).clamp(0, kGradientPresets.length - 1);
    _generating = q['generating'] != '0';
    _welcome = q['welcome'] == '1';
    _controls = q['controls'] != '0';
  }

  @override
  Widget build(BuildContext context) {
    final palette = resolvePalette(kGradientPresets[_preset], _mode);
    final dark = _mode == AppMode.dark || _mode == AppMode.incognitoDark;
    final theme = ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: palette.scheme,
      scaffoldBackgroundColor: Colors.transparent,
      useMaterial3: true,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Stack(
        fit: StackFit.expand,
        children: [
          FloatingGradientBackground(
            meshA: palette.meshA,
            meshB: palette.meshB,
            canvas: palette.canvas,
            idleColor: palette.idle,
            isGenerating: _generating,
            isWelcome: _welcome,
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: _welcome ? const _WelcomeStandIn() : const _ConversationStandIn(),
                  ),
                  if (_controls) _buildControls(theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(ThemeData theme) {
    final on = theme.colorScheme.onSurface;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final e in _modeNames.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: _mode == e.key,
              onSelected: (_) => setState(() => _mode = e.key),
            ),
          DropdownButton<int>(
            value: _preset,
            items: [
              for (var i = 0; i < kGradientPresets.length; i++)
                DropdownMenuItem(value: i, child: Text('preset $i')),
            ],
            onChanged: (v) => setState(() => _preset = v ?? 0),
          ),
          FilterChip(
            label: const Text('generating'),
            selected: _generating,
            onSelected: (v) => setState(() => _generating = v),
          ),
          FilterChip(
            label: const Text('welcome'),
            selected: _welcome,
            onSelected: (v) => setState(() => _welcome = v),
          ),
          Text('${theme.brightness.name} · $_mode', style: TextStyle(color: on.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}

/// A stand-in for the empty welcome screen: greeting over the intro field.
class _WelcomeStandIn extends StatelessWidget {
  const _WelcomeStandIn();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Good evening', style: t.headlineMedium),
          const SizedBox(height: 8),
          Text('What shall we drift into today?', style: t.bodyLarge),
        ],
      ),
    );
  }
}

/// A stand-in conversation, laid out like the real chat: a user bubble on the
/// primary container and an assistant reply as plain text on the background —
/// the case the field most needs to stay legible under.
class _ConversationStandIn extends StatelessWidget {
  const _ConversationStandIn();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Explain how a language model turns a prompt into tokens, one at a time.',
              style: t.bodyLarge?.copyWith(color: scheme.onPrimaryContainer),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'A language model never sees your sentence as words. First a tokenizer '
          'splits the prompt into small pieces, roughly word fragments, and maps '
          'each to an integer id.\n\n'
          'Those ids become vectors, pass through the transformer layers, and out '
          'the far end comes a probability for every possible next token. One is '
          'sampled, appended to the sequence, and the whole thing runs again — '
          'which is why the reply arrives piece by piece rather than all at once.\n\n'
          'The spiral behind this text is doing the same thing: every dot is a '
          'token streaming out from the core.',
          style: t.bodyLarge?.copyWith(height: 1.45),
        ),
      ],
    );
  }
}
