import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:llamaseek/Models/chat_preset.dart';

class ChatAttachmentPreset extends StatelessWidget {
  final ChatPreset preset;
  final Function() onPressed;

  const ChatAttachmentPreset({
    super.key,
    required this.preset,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Material(
          color: colorScheme.surface.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.12),
                  width: 0.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(preset.title, style: Theme.of(context).textTheme.titleSmall),
                  Text(
                    preset.subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
