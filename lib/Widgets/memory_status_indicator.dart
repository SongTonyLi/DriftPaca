import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:llamaseek/Services/memory_service.dart';
import 'package:llamaseek/Utils/motion.dart';

class MemoryStatusIndicator extends StatefulWidget {
  const MemoryStatusIndicator({super.key});

  @override
  State<MemoryStatusIndicator> createState() => _MemoryStatusIndicatorState();
}

class _MemoryStatusIndicatorState extends State<MemoryStatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncAnimation({
    required bool isUpdating,
    required bool disabled,
  }) {
    if (disabled) {
      _controller
        ..stop()
        ..value = 1.0;
    } else if (isUpdating) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MemoryService>(
      builder: (context, memoryService, _) {
        if (!memoryService.isEnabled) return const SizedBox.shrink();
        final disabled = animationsDisabled(context);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _syncAnimation(
            isUpdating: memoryService.isUpdating,
            disabled: disabled,
          );
        });

        return AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            final color = memoryService.isUpdating
                ? Theme.of(context).colorScheme.primary.withValues(alpha: _animation.value)
                : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3);

            return Tooltip(
              message: memoryService.isUpdating
                  ? 'Updating memory...'
                  : 'Memory idle',
              child: Icon(
                Icons.auto_awesome,
                size: 18,
                color: color,
              ),
            );
          },
        );
      },
    );
  }
}
