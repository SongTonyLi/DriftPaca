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

/// Shows a memory editor bottom sheet with glassy UI.
/// Swipe down to dismiss — no close button.
Future<void> showMemoryBottomSheet(
  BuildContext context, {
  required String title,
  required List<MemorySection> sections,
  required int maxTotalTokens,
  required void Function(List<MemorySection> updatedSections) onSave,
  VoidCallback? onClear,
  Future<String?> Function(String content, int tokenLimit)? onResummarize,
  bool isUpdating = false,
  String? updatingModelName,
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
        isUpdating: isUpdating,
        updatingModelName: updatingModelName,
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
  final bool isUpdating;
  final String? updatingModelName;

  const _MemoryEditorSheet({
    required this.title,
    required this.sections,
    required this.maxTotalTokens,
    required this.onSave,
    this.onClear,
    this.onResummarize,
    this.isUpdating = false,
    this.updatingModelName,
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

  bool get _isEmpty => _sections.every((s) => s.value.isEmpty);

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
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome_outlined, size: 20, color: colorScheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 17,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (_totalTokens > 0)
                          Text(
                            '~$_totalTokens tokens',
                            style: TextStyle(
                              fontSize: 12,
                              color: _exceedsLimit ? Colors.red : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.isUpdating)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${widget.updatingModelName ?? 'Summarizer'} is actively updating memory...',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.primary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
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
                  const SizedBox(height: 4),
                  // Section list
                  Expanded(
                    child: _isEmpty
                        ? _buildEmptyState(colorScheme)
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                            itemCount: _sections.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 20),
                            itemBuilder: (context, index) => _buildSection(index, colorScheme),
                          ),
                  ),
                  // Bottom actions — sticky footer
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: colorScheme.outline.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                        child: Row(
                          children: [
                            if (widget.onClear != null && !_isEmpty)
                              TextButton(
                                onPressed: () => _confirmClear(context),
                                child: Text(
                                  'Clear All',
                                  style: TextStyle(color: Colors.red.withValues(alpha: 0.7), fontSize: 14),
                                ),
                              ),
                            const Spacer(),
                            FilledButton(
                              onPressed: _handleSave,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                              ),
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      ),
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

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 16),
            Text(
              'No memories yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Memories are built automatically as you chat.\nTap a section below to add manually.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 24),
            // Show collapsed section labels as tappable chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _sections.map((s) => ActionChip(
                label: Text(s.label, style: const TextStyle(fontSize: 12)),
                avatar: Icon(Icons.add, size: 14, color: colorScheme.primary),
                onPressed: () {
                  // Switch to full editor mode
                  setState(() {
                    s.value = ' '; // trigger non-empty to show editor
                  });
                  // Then clear it so field is empty but editor is visible
                  Future.microtask(() {
                    setState(() {
                      s.value = '';
                    });
                  });
                },
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(int index, ColorScheme colorScheme) {
    final section = _sections[index];
    final hasContent = section.value.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              section.label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                letterSpacing: 0.2,
              ),
            ),
            if (hasContent)
              Text(
                '~${section.estimatedTokens} tokens',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
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
            filled: true,
            fillColor: colorScheme.surface.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5), width: 1.5),
            ),
            contentPadding: const EdgeInsets.all(14),
            hintText: 'Tap to add ${section.label.toLowerCase()}...',
            hintStyle: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
              fontSize: 14,
            ),
          ),
          style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
        ),
      ],
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
