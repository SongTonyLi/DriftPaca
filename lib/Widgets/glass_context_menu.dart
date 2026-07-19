import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:llamaseek/Utils/motion.dart';

/// A single tappable row in a [showGlassContextMenu].
class GlassMenuAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const GlassMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });
}

/// Presents the app's shared liquid-glass long-press menu at [position] (a
/// global offset — typically `LongPressStartDetails.globalPosition`).
///
/// It animates in with a scale + fade spring anchored at the touch point and
/// renders on a frosted [BackdropFilter] surface. Both the chat drawer and the
/// chat bubbles route through this so every long-press menu in the app looks
/// and moves identically. Tapping an action dismisses the menu, then runs the
/// action's callback.
Future<void> showGlassContextMenu({
  required BuildContext context,
  required Offset position,
  required List<GlassMenuAction> actions,
  String? header,
  double width = 220,
}) {
  HapticFeedback.mediumImpact();

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black26,
    transitionDuration: motionDuration(
      context,
      const Duration(milliseconds: 250),
    ),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (dialogContext, animation, secondaryAnimation, _) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: const Cubic(0.16, 1.0, 0.3, 1.0),
        reverseCurve: const Cubic(0.4, 0.0, 0.7, 0.2),
      );

      final size = MediaQuery.of(dialogContext).size;
      // Rough height estimate so the menu flips up when the finger is near the
      // bottom edge instead of running off-screen.
      final estHeight =
          (header != null ? 41.0 : 12.0) + actions.length * 46.0 + 10.0;

      return Stack(
        children: [
          Positioned(
            left: position.dx.clamp(16.0, size.width - width - 16.0),
            top: position.dy.clamp(72.0, size.height - estHeight - 24.0),
            child: ScaleTransition(
              scale: curved,
              alignment: Alignment.topLeft,
              child: FadeTransition(
                opacity: animation,
                child: _GlassMenu(
                  header: header,
                  actions: actions,
                  width: width,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _GlassMenu extends StatelessWidget {
  final String? header;
  final List<GlassMenuAction> actions;
  final double width;

  const _GlassMenu({
    required this.actions,
    required this.width,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuColor = isDark
        ? colorScheme.surface.withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.96);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16.0),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Material(
          color: menuColor,
          borderRadius: BorderRadius.circular(16.0),
          child: Container(
            width: width,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(
                color: isDark
                    ? colorScheme.outlineVariant.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.8),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (header != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        header!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const Divider(height: 1, indent: 12, endIndent: 12),
                ] else
                  const SizedBox(height: 6),
                for (final action in actions) _GlassMenuItem(action: action),
                SizedBox(height: header != null ? 4 : 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassMenuItem extends StatelessWidget {
  final GlassMenuAction action;

  const _GlassMenuItem({required this.action});

  @override
  Widget build(BuildContext context) {
    final color = action.isDestructive
        ? Colors.red
        : Theme.of(context).colorScheme.onSurface;

    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        action.onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Icon(action.icon, size: 20, color: color),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                action.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
