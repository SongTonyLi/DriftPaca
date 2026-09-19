import 'package:flutter/material.dart';

enum AttachmentSource { photos, files }

Future<AttachmentSource?> showAttachmentSourceSheet(BuildContext context) {
  return showModalBottomSheet<AttachmentSource>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Material(
            color: colorScheme.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outline.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.photo_outlined),
                  title: const Text('Photos'),
                  subtitle: const Text('Attach an image from your library'),
                  onTap: () => Navigator.pop(context, AttachmentSource.photos),
                ),
                ListTile(
                  leading: const Icon(Icons.attach_file),
                  title: const Text('Files'),
                  subtitle: const Text('PDF, Word, Excel, PowerPoint, or text'),
                  onTap: () => Navigator.pop(context, AttachmentSource.files),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    },
  );
}
