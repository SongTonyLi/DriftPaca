import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:llamaseek/Constants/gradient_presets.dart';
import 'package:llamaseek/Utils/gradient_settings.dart';
import 'package:llamaseek/Utils/motion.dart';

class ThemesSettings extends StatefulWidget {
  const ThemesSettings({super.key});

  @override
  State<ThemesSettings> createState() => _ThemesSettingsState();
}

class _ThemesSettingsState extends State<ThemesSettings> {
  final _settingsBox = Hive.box('settings');

  // Curated palette offered when customizing each of the two colors.
  static const _customPalette = [
    Color(0xFF4FB4FF), Color(0xFFFF73B3), Color(0xFFFF5D8F), Color(0xFFFFA23A),
    Color(0xFF7C5CFF), Color(0xFF49D6C8), Color(0xFF34C759), Color(0xFFBEE36B),
    Color(0xFFFF8A3D), Color(0xFFFFD24C), Color(0xFF5B7CFA), Color(0xFFB06CFF),
  ];

  GradientPair get _pair => readGradientPair(_settingsBox);
  int? get _brightness => _settingsBox.get('brightness') as int?;

  bool _isSelectedPreset(GradientPair preset) => _pair == preset;

  Future<void> _pickCustom(bool isFirst) async {
    final picked = await showModalBottomSheet<Color>(
      context: context,
      builder: (_) => _PalettePicker(palette: _customPalette),
    );
    if (picked == null) return;
    final current = _pair;
    await writeGradientPair(
      _settingsBox,
      isFirst ? GradientPair(picked, current.c2) : GradientPair(current.c1, picked),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context, 'Appearance'),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int?>(
            segments: const [
              ButtonSegment(value: 1, icon: Icon(Icons.light_mode_rounded, size: 18), label: Text('Light')),
              ButtonSegment(value: 0, icon: Icon(Icons.dark_mode_rounded, size: 18), label: Text('Dark')),
              ButtonSegment(value: null, icon: Icon(Icons.contrast_rounded, size: 18), label: Text('Auto')),
            ],
            selected: {_brightness},
            onSelectionChanged: (selection) {
              _settingsBox.put('brightness', selection.first);
              setState(() {});
            },
          ),
        ),
        const SizedBox(height: 28),
        _sectionLabel(context, 'Background'),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (var i = 0; i < kGradientPresets.length; i++)
              _GradientSwatch(
                key: ValueKey('gradient-preset-$i'),
                pair: kGradientPresets[i],
                isSelected: _isSelectedPreset(kGradientPresets[i]),
                onTap: () async {
                  await writeGradientPair(_settingsBox, kGradientPresets[i]);
                  if (mounted) setState(() {});
                },
              ),
          ],
        ),
        const SizedBox(height: 24),
        _sectionLabel(context, 'Custom'),
        const SizedBox(height: 14),
        Row(
          children: [
            _CustomDot(
              key: const ValueKey('gradient-custom-1'),
              color: _pair.c1,
              label: 'Color 1',
              onTap: () => _pickCustom(true),
            ),
            const SizedBox(width: 20),
            _CustomDot(
              key: const ValueKey('gradient-custom-2'),
              color: _pair.c2,
              label: 'Color 2',
              onTap: () => _pickCustom(false),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0.3,
          ),
    );
  }
}

class _GradientSwatch extends StatelessWidget {
  final GradientPair pair;
  final bool isSelected;
  final VoidCallback onTap;

  const _GradientSwatch({
    super.key,
    required this.pair,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: motionDuration(
          context,
          const Duration(milliseconds: 200),
        ),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [pair.c1, pair.c2],
          ),
          border: isSelected
              ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2.5)
              : null,
          boxShadow: isSelected
              ? [BoxShadow(color: pair.c1.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 1)]
              : null,
        ),
        child: isSelected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
            : null,
      ),
    );
  }
}

class _CustomDot extends StatelessWidget {
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _CustomDot({
    super.key,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
              ),
            ),
            child: const Icon(Icons.edit_rounded, color: Colors.white, size: 16),
          ),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _PalettePicker extends StatelessWidget {
  final List<Color> palette;
  const _PalettePicker({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        alignment: WrapAlignment.center,
        children: [
          for (final c in palette)
            GestureDetector(
              onTap: () => Navigator.of(context).pop(c),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(shape: BoxShape.circle, color: c),
              ),
            ),
        ],
      ),
    );
  }
}
