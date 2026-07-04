import 'package:flutter/material.dart';

/// Shared layout + one-shot staggered entrance for the empty-chat welcome
/// screens (normal and incognito), so both read as the same family.
///
/// Renders an editorial eyebrow, a title, a short accent divider, optional
/// [details] rows, and a tactile CTA pill — fading and rising each in turn —
/// then holds still. No continuous animation, so an idle welcome stays
/// power-cheap. The [accent] threads through the dots, divider, and CTA; the
/// title/detail text use the ambient theme so it adapts to light/dark.
class WelcomeScaffold extends StatefulWidget {
  final String eyebrow;
  final String title;
  final List<Widget> details;
  final String ctaLabel;
  final IconData ctaIcon;

  /// Optional leading widget for the CTA pill, shown in place of [ctaIcon]
  /// (e.g. the selected model's provider logo). Sized to ~17–18px to sit level
  /// with the default icon.
  final Widget? ctaLeading;
  final VoidCallback onCta;
  final Color accent;

  const WelcomeScaffold({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.ctaLabel,
    required this.onCta,
    required this.accent,
    this.details = const [],
    this.ctaIcon = Icons.auto_awesome,
    this.ctaLeading,
  });

  @override
  State<WelcomeScaffold> createState() => _WelcomeScaffoldState();
}

class _WelcomeScaffoldState extends State<WelcomeScaffold>
    with SingleTickerProviderStateMixin {
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

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final accent = widget.accent;
    final hasDetails = widget.details.isNotEmpty;

    var index = 0;
    Widget reveal(Widget child) {
      final start = index++ * 0.11;
      return _stagger(start, (start + 0.5).clamp(0.0, 1.0), child);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        reveal(_eyebrow(accent)),
        const SizedBox(height: 12),
        reveal(_title(onSurface)),
        const SizedBox(height: 14),
        reveal(_bar(accent)),
        if (hasDetails) ...[
          const SizedBox(height: 22),
          reveal(Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: widget.details,
          )),
        ],
        const SizedBox(height: 30),
        reveal(_cta(accent)),
      ],
    );
  }

  /// Fade + rise [child] over the [start, end] slice of the entrance.
  Widget _stagger(double start, double end, Widget child) {
    final anim = _entrance.drive(
      CurveTween(curve: Interval(start, end, curve: Curves.easeOutCubic)),
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

  Widget _eyebrow(Color accent) {
    Widget dot() => Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.55),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(),
        const SizedBox(width: 9),
        Text(
          widget.eyebrow,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.6,
            color: accent.withValues(alpha: 0.9),
          ),
        ),
        const SizedBox(width: 9),
        dot(),
      ],
    );
  }

  Widget _title(Color onSurface) => Text(
        widget.title,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: onSurface,
        ),
      );

  /// A short accent divider under the title.
  Widget _bar(Color accent) => Container(
        width: 38,
        height: 3,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.0),
              accent,
              accent.withValues(alpha: 0.0),
            ],
          ),
        ),
      );

  Widget _cta(Color accent) => Material(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onCta,
          splashColor: accent.withValues(alpha: 0.18),
          highlightColor: accent.withValues(alpha: 0.10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                widget.ctaLeading ??
                    Icon(widget.ctaIcon, size: 17, color: accent),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    widget.ctaLabel,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
