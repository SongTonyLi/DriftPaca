import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:llamaseek/Constants/memory_constants.dart';
import 'package:llamaseek/Services/memory_service.dart';

class MemorySection {
  final String label;
  final String key;
  final bool readOnly;
  String value;

  MemorySection({required this.label, required this.key, required this.value, this.readOnly = false});

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
  DateTime? lastUpdatedAt,
  String? lastUpdatedByModel,
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
        lastUpdatedAt: lastUpdatedAt,
        lastUpdatedByModel: lastUpdatedByModel,
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
  final DateTime? lastUpdatedAt;
  final String? lastUpdatedByModel;

  const _MemoryEditorSheet({
    required this.title,
    required this.sections,
    required this.maxTotalTokens,
    required this.onSave,
    this.onClear,
    this.onResummarize,
    this.isUpdating = false,
    this.updatingModelName,
    this.lastUpdatedAt,
    this.lastUpdatedByModel,
  });

  @override
  State<_MemoryEditorSheet> createState() => _MemoryEditorSheetState();
}

class _MemoryEditorSheetState extends State<_MemoryEditorSheet> {
  late List<MemorySection> _sections;

  // null = chips/overview, non-null = focused on that section index
  // -1 = show all sections (when memory has content)
  int? _viewMode;

  @override
  void initState() {
    super.initState();
    _sections = widget.sections
        .map((s) => MemorySection(label: s.label, key: s.key, value: s.value, readOnly: s.readOnly))
        .toList();
    // If any editable section has content, show all sections
    if (_hasContent) {
      _viewMode = -1;
    }
  }

  int get _totalTokens =>
      _sections.where((s) => !s.readOnly).fold(0, (sum, s) => sum + s.estimatedTokens);

  bool get _exceedsLimit => _totalTokens > widget.maxTotalTokens;

  bool get _hasContent => _sections.any((s) => !s.readOnly && s.value.isNotEmpty);

  void _openSection(int index) {
    setState(() => _viewMode = index);
  }

  void _goBack() {
    setState(() => _viewMode = _hasContent ? -1 : null);
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                    padding: const EdgeInsets.fromLTRB(8, 14, 20, 4),
                    child: Row(
                      children: [
                        if (_viewMode != null && _viewMode! >= 0)
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                            onPressed: _goBack,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          )
                        else ...[
                          const SizedBox(width: 12),
                          Consumer<MemoryService>(
                            builder: (context, memoryService, _) {
                              if (memoryService.isUpdating) {
                                return _PulsingStarIcon(size: 20, color: colorScheme.primary);
                              }
                              return Icon(Icons.auto_awesome_outlined, size: 20, color: colorScheme.primary);
                            },
                          ),
                        ],
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _viewMode != null && _viewMode! >= 0
                                    ? _sections[_viewMode!].label
                                    : widget.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 17,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              if (widget.lastUpdatedAt != null && _viewMode == null || _viewMode == -1)
                                Text(
                                  'by ${widget.lastUpdatedByModel ?? 'unknown'} at ${_formatTime(widget.lastUpdatedAt!)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                  ),
                                ),
                            ],
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
                  Consumer<MemoryService>(
                    builder: (context, memoryService, _) {
                      if (memoryService.lastError != null) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, size: 14, color: Colors.red),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  memoryService.lastError!,
                                  style: TextStyle(fontSize: 12, color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      if (!memoryService.isUpdating) return const SizedBox.shrink();
                      return Padding(
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
                      );
                    },
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
                  // Content area
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.05),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                            child: child,
                          ),
                        );
                      },
                      child: _viewMode == null
                          ? _buildEmptyState(colorScheme)
                          : _viewMode! >= 0
                              ? _buildFocusedSection(_viewMode!, colorScheme)
                              : ListView.separated(
                                  key: const ValueKey('all'),
                                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                                  itemCount: _sections.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 20),
                                  itemBuilder: (context, index) => _buildSection(index, colorScheme),
                                ),
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
                            if (widget.onClear != null && _viewMode != null)
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
            // Show collapsed section labels as tappable chips (skip read-only)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (int i = 0; i < _sections.length; i++)
                  if (!_sections[i].readOnly)
                    ActionChip(
                      label: Text(_sections[i].label, style: const TextStyle(fontSize: 12)),
                      onPressed: () => _openSection(i),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusedSection(int index, ColorScheme colorScheme) {
    final section = _sections[index];

    return Padding(
      key: ValueKey('focused_$index'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.readOnly)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Managed by system — not editable',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            )
          else if (section.value.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '~${section.estimatedTokens} tokens',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
          Expanded(
            child: TextFormField(
              initialValue: section.value,
              autofocus: !section.readOnly,
              readOnly: section.readOnly,
              onChanged: section.readOnly ? null : (value) {
                setState(() {
                  section.value = value;
                });
              },
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                filled: true,
                fillColor: section.readOnly
                    ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
                    : colorScheme.surfaceContainerLowest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: section.readOnly
                      ? BorderSide.none
                      : BorderSide(color: colorScheme.primary.withValues(alpha: 0.5), width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(16),
                hintText: section.readOnly ? null : 'Describe your ${section.label.toLowerCase()}...',
                hintStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                  fontSize: 14,
                ),
              ),
              style: TextStyle(
                fontSize: 14,
                color: section.readOnly
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.7)
                    : colorScheme.onSurface,
              ),
            ),
          ),
        ],
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
            Row(
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
                if (section.readOnly) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.lock_outline, size: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                ],
              ],
            ),
            if (hasContent && !section.readOnly)
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
          readOnly: section.readOnly,
          onChanged: section.readOnly ? null : (value) {
            setState(() {
              section.value = value;
            });
          },
          maxLines: null,
          minLines: 2,
          decoration: InputDecoration(
            filled: true,
            fillColor: section.readOnly
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
                : colorScheme.surface.withValues(alpha: 0.5),
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
              borderSide: section.readOnly
                  ? BorderSide.none
                  : BorderSide(color: colorScheme.primary.withValues(alpha: 0.5), width: 1.5),
            ),
            contentPadding: const EdgeInsets.all(14),
            hintText: section.readOnly ? null : 'Tap to add ${section.label.toLowerCase()}...',
            hintStyle: TextStyle(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
              fontSize: 14,
            ),
          ),
          style: TextStyle(
            fontSize: 14,
            color: section.readOnly
                ? colorScheme.onSurfaceVariant.withValues(alpha: 0.7)
                : colorScheme.onSurface,
          ),
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

class _PulsingStarIcon extends StatefulWidget {
  final double size;
  final Color color;

  const _PulsingStarIcon({required this.size, required this.color});

  @override
  State<_PulsingStarIcon> createState() => _PulsingStarIconState();
}

class _PulsingStarIconState extends State<_PulsingStarIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Icon(Icons.auto_awesome, size: widget.size, color: widget.color),
    );
  }
}
