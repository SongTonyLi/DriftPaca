import 'package:flutter/material.dart';
import 'package:llamaseek/Utils/border_painter.dart';

class ChatBubbleMenu extends StatefulWidget {
  final Widget child;
  final List<Widget> menuChildren;

  const ChatBubbleMenu({
    super.key,
    required this.child,
    required this.menuChildren,
  });

  @override
  State<ChatBubbleMenu> createState() => _ChatBubbleMenuState();
}

class _ChatBubbleMenuState extends State<ChatBubbleMenu> {
  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: widget.menuChildren,
      builder: (context, controller, child) {
        return GestureDetector(
          // Only intercept taps while the menu is open (to dismiss it). When
          // closed, claiming taps would steal them from link/citation taps
          // inside the bubble content.
          onTap: controller.isOpen ? () => controller.close() : null,
          onLongPressStart: (details) {
            if (!controller.isOpen) {
              controller.open(position: details.localPosition);
            }
          },
          // A DoubleTapGestureRecognizer holds the gesture arena open on every
          // first tap-down (waiting ~300ms for a possible second tap), which
          // starves the citation-favicon link's TapGestureRecognizer inside the
          // bubble and swallows single taps on citations. Only register the
          // double-tap handler while the menu is already open (to toggle it
          // closed). When closed, long-press and right-click are the ways in, so
          // a plain tap reaches the link children unobstructed.
          onDoubleTapDown:
              controller.isOpen ? (details) => controller.close() : null,
          onSecondaryTapDown: (details) {
            controller.open(position: details.localPosition);
          },
          child: CustomPaint(
            foregroundPainter: BorderPainter(
              color: controller.isOpen
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surface,
              borderRadius: Radius.circular(10.0),
              strokeWidth: 2,
              padding: EdgeInsets.symmetric(horizontal: 10.0),
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
      onOpen: () => setState(() {}),
      onClose: () => setState(() {}),
    );
  }
}
