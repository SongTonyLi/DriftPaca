import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:llamaseek/Constants/memory_constants.dart';

class MemorySection {
  final String label;
  final String key;
  String value;

  MemorySection({required this.label, required this.key, required this.value});

  int get estimatedTokens => (value.length / 4).ceil();
}

/// Shows a memory editor bottom sheet with glassy sidebar-like UI.
/// Swipe down to dismiss — no close button.
Future<void> showMemoryBottomSheet(
  BuildContext context, {
  required String title,
  required List<MemorySection> sections,
  required int maxTotalTokens,
  required void Function(List<MemorySection> updatedSections) onSave,
  VoidCallback? onClear,
  Future<String?> Function(String content, int tokenLimit)? onResummarize,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return _MemoryEditorSheet(
        title: title,
        sections: sections,
        maxTotalTokens: maxTotalTokens,
        onSave: onSave,
        onClear: onClear,
        onResummarize: onResummarize,
      );
    },
  );
}

class _MemoryEditorSheet extends StatefulWidget {
  final String title;
  final List<MemorySection> sections;
  final int maxTotalTokens;
  final void Function(List<MemorySection> updatedSections) onSave;
  final VoidCallback? onClear;
  final Future<String?> Function(String content, int tokenLimit)? onResummarize;

  const _MemoryEditorSheet({
    required this.title,
    required this.sections,
    required this.maxTotalTokens,
    required this.onSave,
    this.onClear,
    this.onResummarize,
  });

  @override
  State<_MemoryEditorSheet> createState() => _MemoryEditorSheetState();
}

class _MemoryEditorSheetState extends State<_MemoryEditorSheet> {
  late List<MemorySection> _sections;

  @override
  void initState() {
    super.initState();
    _sections = widget.sections
        .map((s) => MemorySection(label: s.label, key: s.key, value: s.value))
        .toList();
  }

  int get _totalTokens =>
      _sections.fold(0, (sum, s) => sum + s.estimatedTokens);

  bool get _exceedsLimit => _totalTokens > widget.maxTotalTokens;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.40),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.15),
                  width: 0.5,
                ),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome_outlined, size: 20, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          '~$_totalTokens tokens',
                          style: TextStyle(
                            fontSize: 12,
                            color: _exceedsLimit ? Colors.red : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Actions row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (widget.onClear != null)
                          TextButton(
                            onPressed: () => _confirmClear(context),
                            child: const Text('Clear', style: TextStyle(color: Colors.red, fontSize: 13)),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: _handleSave,
                          child: const Text('Save', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                  if (_exceedsLimit)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Memory exceeds token limit. Reduce content or it will be auto-resummarized.',
                              style: TextStyle(fontSize: 12, color: Colors.orange),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Divider(height: 1, color: colorScheme.outline.withValues(alpha: 0.15)),
                  // Section list
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      itemCount: _sections.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final section = _sections[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  section.label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  '~${section.estimatedTokens} tokens',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: section.value,
                              onChanged: (value) {
                                setState(() {
                                  section.value = value;
                                });
                              },
                              maxLines: null,
                              minLines: 2,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.all(12),
                                hintText: 'No ${section.label.toLowerCase()} recorded',
                              ),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleSave() async {
    if (_exceedsLimit && widget.onResummarize != null) {
      final shouldResummarize = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Memory Too Large'),
          content: const Text(
            'Memory exceeds the allowed size. Reduce content manually, or auto-resummarize to fit?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Go Back'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Auto-Resummarize'),
            ),
          ],
        ),
      );

      if (shouldResummarize == true) {
        for (final section in _sections) {
          if (section.estimatedTokens > MemoryConstants.maxPerSectionTokens) {
            final condensed = await widget.onResummarize!(
              section.value,
              MemoryConstants.maxPerSectionTokens,
            );
            if (condensed != null) {
              setState(() {
                section.value = condensed;
              });
            }
          }
        }
      } else {
        return;
      }
    }

    widget.onSave(_sections);
    if (mounted) Navigator.pop(context);
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Memory?'),
        content: const Text('This will delete all memory data. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // close dialog
              widget.onClear?.call();
              Navigator.pop(this.context); // close bottom sheet
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
