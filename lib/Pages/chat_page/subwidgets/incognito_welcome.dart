import 'package:flutter/material.dart';

/// The incognito-mode welcome: a private, "off the record" panel.
///
/// A softly glowing masked-eye hero, an editorial `· PRIVATE SESSION ·` label,
/// the privacy facts as a scannable icon list, and a tactile model-select CTA.
/// Plays a one-shot staggered entrance and then holds still — no continuous
/// animation, so an idle incognito screen stays power-cheap. Text colours come
/// from the (now light/dark-aware) incognito theme; the indigo accent is fixed.
class IncognitoWelcome extends StatefulWidget {
  final String? selectedModelName;
  final VoidCallback onSelectModel;

  const IncognitoWelcome({
    super.key,
    required this.selectedModelName,
    required this.onSelectModel,
  });

  @override
  State<IncognitoWelcome> createState() => _IncognitoWelcomeState();
}

class _IncognitoWelcomeState extends State<IncognitoWelcome>
    with SingleTickerProviderStateMixin {
  static const Color _accent = Color(0xFF6C63FF);

  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    // One-shot: drives the staggered reveal, then idles at 1.0 (no repaints).
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  /// Fade + rise a child over the [start, end] slice of the entrance.
  Widget _stagger(double start, double end, Widget child) {
    final anim = CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - anim.value) * 14),
          child: c,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stagger(0.00, 0.45, _hero()),
        const SizedBox(height: 26),
        _stagger(0.12, 0.55, _eyebrow()),
        const SizedBox(height: 12),
        _stagger(0.20, 0.62, _title(onSurface)),
        const SizedBox(height: 14),
        _stagger(0.26, 0.66, _bar()),
        const SizedBox(height: 22),
        _stagger(0.34, 0.80, _facts(onSurface)),
        const SizedBox(height: 30),
        _stagger(0.55, 1.00, _cta()),
      ],
    );
  }

  Widget _hero() {
    return Container(
      width: 108,
      height: 108,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          stops: const [0.15, 1.0],
          colors: [_accent.withValues(alpha: 0.30), _accent.withValues(alpha: 0.0)],
        ),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 66,
        height: 66,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _accent.withValues(alpha: 0.12),
          border: Border.all(color: _accent.withValues(alpha: 0.35)),
        ),
        child: const Icon(Icons.visibility_off_rounded, size: 30, color: _accent),
      ),
    );
  }

  Widget _eyebrow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dot(),
        const SizedBox(width: 9),
        Text(
          'PRIVATE SESSION',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.6,
            color: _accent.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(width: 9),
        _dot(),
      ],
    );
  }

  Widget _dot() => Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _accent.withValues(alpha: 0.55),
        ),
      );

  Widget _title(Color onSurface) => Text(
        'Incognito Mode',
        style: TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: onSurface,
        ),
      );

  /// A short "redaction bar" — an editorial accent divider under the title.
  Widget _bar() => Container(
        width: 38,
        height: 3,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          gradient: LinearGradient(
            colors: [_accent.withValues(alpha: 0.0), _accent, _accent.withValues(alpha: 0.0)],
          ),
        ),
      );

  Widget _facts(Color onSurface) {
    const items = <(IconData, String)>[
      (Icons.person_off_outlined, 'Your profile stays unknown'),
      (Icons.history_toggle_off, "Chats won't build your memory"),
      (Icons.smart_toy_outlined, 'Agent memory is off here'),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
      ],
    );
  }

  Widget _cta() {
    final label = widget.selectedModelName ?? 'Select a model to start';
    return Material(
      color: _accent.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onSelectModel,
        splashColor: _accent.withValues(alpha: 0.18),
        highlightColor: _accent.withValues(alpha: 0.10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, size: 17, color: _accent),
              const SizedBox(width: 9),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: _accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
