import 'package:flutter/material.dart';

import 'welcome_scaffold.dart';

/// The incognito-mode welcome: a private, "off the record" panel built on the
/// shared [WelcomeScaffold]. An editorial `· PRIVATE SESSION ·` label, the
/// "Incognito Mode" title, the privacy facts as a scannable icon list, and the
/// model-select CTA — all on the fixed indigo incognito accent.
class IncognitoWelcome extends StatelessWidget {
  static const Color _accent = Color(0xFF6C63FF);

  final String? selectedModelName;
  final VoidCallback onSelectModel;

  const IncognitoWelcome({
    super.key,
    required this.selectedModelName,
    required this.onSelectModel,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return WelcomeScaffold(
      accent: _accent,
      eyebrow: 'PRIVATE SESSION',
      title: 'Incognito Mode',
      details: _facts(onSurface),
      ctaLabel: selectedModelName ?? 'Select a model to start',
      onCta: onSelectModel,
    );
  }

  List<Widget> _facts(Color onSurface) {
    const items = <(IconData, String)>[
      (Icons.person_off_outlined, 'Your profile stays unknown'),
      (Icons.history_toggle_off, "Chats won't build your memory"),
      (Icons.smart_toy_outlined, 'Agent memory is off here'),
    ];
    return [
      for (final (icon, label) in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: _accent.withValues(alpha: 0.75)),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.2,
                  color: onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
    ];
  }
}
