import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:llamaseek/Utils/idle_activity_controller.dart';

/// Wraps [child] and pokes the ambient [IdleActivityController] on any pointer
/// activity or scroll, so background animation knows the user is engaged.
class IdleActivityDetector extends StatelessWidget {
  final Widget child;
  const IdleActivityDetector({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final activity = context.read<IdleActivityController>();
    return Listener(
      // Translucent so the whole area observes pointers even over transparent
      // regions whose child does not hit-test itself; the events still reach
      // the content below (we never absorb them).
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => activity.poke(),
      onPointerMove: (_) => activity.poke(),
      onPointerSignal: (_) => activity.poke(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          activity.poke();
          return false; // keep bubbling
        },
        child: child,
      ),
    );
  }
}
