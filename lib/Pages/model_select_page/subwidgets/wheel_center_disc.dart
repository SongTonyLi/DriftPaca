import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

/// The frosted-glass disc at the center of the wheel. Shows the currently docked
/// model: its brand logo (cross-fading on change), the model name in JetBrains
/// Mono, an optional parameter-size line, and capability badges. Tapping it
/// confirms the selection.
class WheelCenterDisc extends StatelessWidget {
  final double diameter;
  final String asset;
  final Color accent;
  final bool tinted;
  final String modelName;
  final String paramSize;
  final bool think;
  final bool vision;
  final bool tools;
  final VoidCallback? onTap;

  const WheelCenterDisc({
    super.key,
    required this.diameter,
    required this.asset,
    required this.accent,
    required this.modelName,
    this.tinted = false,
    this.paramSize = '',
    this.think = false,
    this.vision = false,
    this.tools = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final logoSize = diameter * 0.30;

    final badges = <Widget>[
      if (think) const _Badge(Icons.psychology_alt_outlined, 'Think', Color(0xFF9C6ADE)),
      if (vision) const _Badge(Icons.visibility_outlined, 'Vision', Color(0xFF3D8BD4)),
      if (tools) const _Badge(Icons.handyman_outlined, 'Tools', Color(0xFFCF8523)),
    ];

    // Width-bounded so the name wraps; a FittedBox below scales the whole
    // column down if a model with many badges would otherwise overflow.
    final content = SizedBox(
      width: diameter * 0.8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: logoSize,
            width: logoSize,
            child: SvgPicture.asset(
              asset,
              fit: BoxFit.contain,
              colorFilter: tinted
                  ? ColorFilter.mode(
                      cs.onSurface.withValues(alpha: 0.8), BlendMode.srcIn)
                  : null,
            ),
          ),
          SizedBox(height: diameter * 0.045),
          Text(
            modelName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.jetBrainsMono(
              fontSize: (diameter * 0.078).clamp(11.0, 16.0),
              fontWeight: FontWeight.w600,
              height: 1.12,
              color: cs.onSurface,
            ),
          ),
          if (paramSize.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              paramSize,
              style: TextStyle(
                fontSize: 11.5,
                color: cs.onSurface.withValues(alpha: 0.55),
                letterSpacing: 0.3,
              ),
            ),
          ],
          if (badges.isNotEmpty) ...[
            SizedBox(height: diameter * 0.05),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 5,
              runSpacing: 5,
              children: badges,
            ),
          ],
        ],
      ),
    );

    final disc = Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Color.lerp(cs.outline, accent, 0.55)!.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.28),
            blurRadius: 42,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            color: cs.surface.withValues(alpha: 0.82),
            alignment: Alignment.center,
            padding: EdgeInsets.all(diameter * 0.1),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween(begin: 0.86, end: 1.0).animate(anim),
                  child: child,
                ),
              ),
              child: FittedBox(
                key: ValueKey(modelName),
                fit: BoxFit.scaleDown,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );

    return GestureDetector(onTap: onTap, child: disc);
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Badge(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
