import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:llamaseek/Constants/memory_constants.dart';
import 'package:llamaseek/Services/memory_service.dart';
import 'package:llamaseek/Models/memory_topic.dart';
import 'package:llamaseek/Models/ephemeral_context.dart';

class MemorySection {
  final String label;
  final String key;
  final bool readOnly;
  String value;

  MemorySection({required this.label, required this.key, required this.value, this.readOnly = false});

  int get estimatedTokens => (value.length / 4).ceil();
}

/// Shows a memory editor bottom sheet with glassy UI.
/// Supports both the flat-section mode (conversation memory) and
/// the tabbed three-tier mode (agent memory).
Future<void> showMemoryBottomSheet(
  BuildContext context, {
  required String title,
  required int maxTotalTokens,
  // Flat-section mode (conversation memory)
  List<MemorySection>? sections,
  void Function(List<MemorySection> updatedSections)? onSave,
  // Tabbed mode (agent memory)
  List<MemorySection>? profileSections,
  void Function(List<MemorySection> updatedSections)? onSaveProfile,
  Future<void> Function(MemoryTopic topic)? onSaveTopic,
  Future<void> Function(int id)? onDeleteTopic,
  Future<void> Function(EphemeralContext ctx)? onSaveEphemeral,
  Future<void> Function(int id)? onDeleteEphemeral,
  List<MemoryTopic> topics = const [],
  List<EphemeralContext> ephemeralContexts = const [],
  // Common
  VoidCallback? onClear,
  Future<String?> Function(String content, int tokenLimit)? onResummarize,
  bool isUpdating = false,
  String? updatingModelName,
  DateTime? lastUpdatedAt,
  String? lastUpdatedByModel,
}) {
  final bool isTabbed = profileSections != null;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      if (isTabbed) {
        return _TabbedMemorySheet(
          title: title,
          profileSections: profileSections,
          maxTotalTokens: maxTotalTokens,
          onSaveProfile: onSaveProfile!,
          onSaveTopic: onSaveTopic!,
          onDeleteTopic: onDeleteTopic!,
          onSaveEphemeral: onSaveEphemeral!,
          onDeleteEphemeral: onDeleteEphemeral!,
          topics: topics,
          ephemeralContexts: ephemeralContexts,
          onClear: onClear,
          onResummarize: onResummarize,
          isUpdating: isUpdating,
          updatingModelName: updatingModelName,
          lastUpdatedAt: lastUpdatedAt,
          lastUpdatedByModel: lastUpdatedByModel,
        );
      }
      return _MemoryEditorSheet(
        title: title,
        sections: sections!,
        maxTotalTokens: maxTotalTokens,
        onSave: onSave!,
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

// ---------------------------------------------------------------------------
// Flat-section editor (conversation memory) — unchanged logic
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Tabbed three-tier editor (agent memory)
// ---------------------------------------------------------------------------

class _TabbedMemorySheet extends StatefulWidget {
  final String title;
  final List<MemorySection> profileSections;
  final int maxTotalTokens;
  final void Function(List<MemorySection> updatedSections) onSaveProfile;
  final Future<void> Function(MemoryTopic topic) onSaveTopic;
  final Future<void> Function(int id) onDeleteTopic;
  final Future<void> Function(EphemeralContext ctx) onSaveEphemeral;
  final Future<void> Function(int id) onDeleteEphemeral;
  final List<MemoryTopic> topics;
  final List<EphemeralContext> ephemeralContexts;
  final VoidCallback? onClear;
  final Future<String?> Function(String content, int tokenLimit)? onResummarize;
  final bool isUpdating;
  final String? updatingModelName;
  final DateTime? lastUpdatedAt;
  final String? lastUpdatedByModel;

  const _TabbedMemorySheet({
    required this.title,
    required this.profileSections,
    required this.maxTotalTokens,
    required this.onSaveProfile,
    required this.onSaveTopic,
    required this.onDeleteTopic,
    required this.onSaveEphemeral,
    required this.onDeleteEphemeral,
    required this.topics,
    required this.ephemeralContexts,
    this.onClear,
    this.onResummarize,
    this.isUpdating = false,
    this.updatingModelName,
    this.lastUpdatedAt,
    this.lastUpdatedByModel,
  });

  @override
  State<_TabbedMemorySheet> createState() => _TabbedMemorySheetState();
}

class _TabbedMemorySheetState extends State<_TabbedMemorySheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<MemorySection> _profileSections;
  late List<MemoryTopic> _topics;
  late List<EphemeralContext> _ephemeral;

  // Profile view: null = chips, -1 = all, >=0 = focused
  int? _profileViewMode;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _profileSections = widget.profileSections
        .map((s) => MemorySection(label: s.label, key: s.key, value: s.value, readOnly: s.readOnly))
        .toList();
    _topics = List.of(widget.topics);
    _ephemeral = List.of(widget.ephemeralContexts);
    if (_profileHasContent) {
      _profileViewMode = -1;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _profileHasContent =>
      _profileSections.any((s) => !s.readOnly && s.value.isNotEmpty);

  int get _profileTokens =>
      _profileSections.where((s) => !s.readOnly).fold(0, (sum, s) => sum + s.estimatedTokens);

  bool get _profileExceedsLimit => _profileTokens > widget.maxTotalTokens;

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
                    if (_profileViewMode != null && _profileViewMode! >= 0 && _tabController.index == 0)
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                        onPressed: () {
                          setState(() => _profileViewMode = _profileHasContent ? -1 : null);
                        },
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
                            _profileViewMode != null && _profileViewMode! >= 0 && _tabController.index == 0
                                ? _profileSections[_profileViewMode!].label
                                : widget.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 17,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          if (widget.lastUpdatedAt != null && (_profileViewMode == null || _profileViewMode == -1))
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
                    if (_profileTokens > 0 && _tabController.index == 0)
                      Text(
                        '~$_profileTokens tokens',
                        style: TextStyle(
                          fontSize: 12,
                          color: _profileExceedsLimit
                              ? Colors.red
                              : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                  ],
                ),
              ),
              // Status bar
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
              if (_profileExceedsLimit && _tabController.index == 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Profile exceeds token limit. Reduce content or it will be auto-resummarized.',
                          style: TextStyle(fontSize: 12, color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
              // Tab bar
              TabBar(
                controller: _tabController,
                onTap: (_) => setState(() {}),
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
                indicatorSize: TabBarIndicatorSize.label,
                dividerColor: colorScheme.outline.withValues(alpha: 0.1),
                tabs: [
                  const Tab(text: 'Profile'),
                  Tab(text: 'Topics (${_topics.length})'),
                  Tab(text: 'Recent (${_ephemeral.length})'),
                ],
              ),
              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildProfileTab(colorScheme),
                    _buildTopicsTab(colorScheme),
                    _buildEphemeralTab(colorScheme),
                  ],
                ),
              ),
              // Footer
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
                        if (widget.onClear != null)
                          TextButton(
                            onPressed: () => _confirmClear(context),
                            child: Text(
                              'Clear All',
                              style: TextStyle(color: Colors.red.withValues(alpha: 0.7), fontSize: 14),
                            ),
                          ),
                        const Spacer(),
                        FilledButton(
                          onPressed: _handleProfileSave,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                          ),
                          child: const Text('Save Profile'),
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

  // ---- Profile tab ----

  Widget _buildProfileTab(ColorScheme colorScheme) {
    if (_profileViewMode == null) {
      return _buildProfileEmptyState(colorScheme);
    }
    if (_profileViewMode! >= 0) {
      return _buildProfileFocusedSection(_profileViewMode!, colorScheme);
    }
    // -1 = show all
    return ListView.separated(
      key: const ValueKey('profile_all'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      itemCount: _profileSections.length,
      separatorBuilder: (_, __) => const SizedBox(height: 20),
      itemBuilder: (context, index) => _buildProfileSection(index, colorScheme),
    );
  }

  Widget _buildProfileEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_outline,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 16),
            Text(
              'No profile yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Profile fields are updated automatically as you chat.\nTap a section below to add manually.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (int i = 0; i < _profileSections.length; i++)
                  if (!_profileSections[i].readOnly)
                    ActionChip(
                      label: Text(_profileSections[i].label, style: const TextStyle(fontSize: 12)),
                      onPressed: () => setState(() => _profileViewMode = i),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileFocusedSection(int index, ColorScheme colorScheme) {
    final section = _profileSections[index];
    return Padding(
      key: ValueKey('profile_focused_$index'),
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
              onChanged: section.readOnly
                  ? null
                  : (value) {
                      setState(() => section.value = value);
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

  Widget _buildProfileSection(int index, ColorScheme colorScheme) {
    final section = _profileSections[index];
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
          onChanged: section.readOnly
              ? null
              : (value) {
                  setState(() => section.value = value);
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

  // ---- Topics tab ----

  Widget _buildTopicsTab(ColorScheme colorScheme) {
    if (_topics.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.topic_outlined,
                size: 48,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
              ),
              const SizedBox(height: 16),
              Text(
                'No topics yet',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Topics are created automatically as you chat\nabout different subjects.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _showTopicEditor(context, null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Topic'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
          itemCount: _topics.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final topic = _topics[index];
            return _buildTopicCard(topic, colorScheme);
          },
        ),
        Positioned(
          right: 20,
          bottom: 16,
          child: FloatingActionButton.small(
            heroTag: 'add_topic',
            onPressed: () => _showTopicEditor(context, null),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _buildTopicCard(MemoryTopic topic, ColorScheme colorScheme) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showTopicEditor(context, topic),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topic.topicKey,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      topic.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '~${topic.estimatedTokens} tokens',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 20, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                onPressed: () async {
                  if (topic.id != null) {
                    await widget.onDeleteTopic(topic.id!);
                    setState(() => _topics.removeWhere((t) => t.id == topic.id));
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTopicEditor(BuildContext context, MemoryTopic? existing) async {
    final keyController = TextEditingController(text: existing?.topicKey ?? '');
    final contentController = TextEditingController(text: existing?.content ?? '');

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                    child: Row(
                      children: [
                        Icon(
                          existing != null ? Icons.edit_outlined : Icons.add_circle_outline,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            existing != null ? 'Edit Topic' : 'New Topic',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 17,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext, false),
                          icon: Icon(Icons.close, size: 20, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  // Fields
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Topic Name',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: keyController,
                          textCapitalization: TextCapitalization.sentences,
                          autofocus: existing == null,
                          style: TextStyle(fontSize: 15, color: colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: 'e.g. Flutter Development',
                            hintStyle: TextStyle(
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                              fontSize: 15,
                            ),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerLowest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colorScheme.primary.withValues(alpha: 0.5),
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Content',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: contentController,
                          textCapitalization: TextCapitalization.sentences,
                          maxLines: 6,
                          minLines: 4,
                          style: TextStyle(fontSize: 14, color: colorScheme.onSurface, height: 1.4),
                          decoration: InputDecoration(
                            hintText: 'What should the AI remember about this topic?',
                            hintStyle: TextStyle(
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                              fontSize: 14,
                            ),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerLowest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colorScheme.primary.withValues(alpha: 0.5),
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.all(14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Actions
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, true),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Save', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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

    if (result == true) {
      final key = keyController.text.trim();
      final content = contentController.text.trim();
      if (key.isEmpty || content.isEmpty) return;

      final topic = existing != null
          ? existing.copyWith(topicKey: key, content: content)
          : MemoryTopic(topicKey: key, content: content);
      await widget.onSaveTopic(topic);

      if (existing != null) {
        setState(() {
          final idx = _topics.indexWhere((t) => t.id == existing.id);
          if (idx >= 0) _topics[idx] = topic;
        });
      } else {
        setState(() => _topics.add(topic));
      }
    }

    keyController.dispose();
    contentController.dispose();
  }

  // ---- Ephemeral / Recent Context tab ----

  Widget _buildEphemeralTab(ColorScheme colorScheme) {
    if (_ephemeral.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.schedule_outlined,
                size: 48,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.25),
              ),
              const SizedBox(height: 16),
              Text(
                'No recent context',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Short-lived context about what you are currently\nworking on. Created automatically as you chat\nand expires after a few days.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      itemCount: _ephemeral.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final ctx = _ephemeral[index];
        return _buildEphemeralCard(ctx, colorScheme);
      },
    );
  }

  Widget _buildEphemeralCard(EphemeralContext ctx, ColorScheme colorScheme) {
    final days = ctx.daysRemaining;
    final daysLabel = days <= 0 ? 'Expiring soon' : days == 1 ? '1 day left' : '$days days left';
    final daysColor = days <= 1 ? Colors.orange : colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showEphemeralEditor(context, ctx),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            ctx.contextKey,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          daysLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: daysColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ctx.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '~${ctx.estimatedTokens} tokens',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 20, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                onPressed: () async {
                  if (ctx.id != null) {
                    await widget.onDeleteEphemeral(ctx.id!);
                    setState(() => _ephemeral.removeWhere((e) => e.id == ctx.id));
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEphemeralEditor(BuildContext context, EphemeralContext existing) async {
    final contentController = TextEditingController(text: existing.content);
    double ttlDays = existing.daysRemaining.clamp(1, EphemeralContext.maxTtlDays).toDouble();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                        padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
                        child: Row(
                          children: [
                            Icon(Icons.schedule_outlined, size: 20, color: colorScheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    existing.contextKey,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 17,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(sheetContext, false),
                              icon: Icon(Icons.close, size: 20, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      // Fields
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Content',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: contentController,
                              textCapitalization: TextCapitalization.sentences,
                              maxLines: 6,
                              minLines: 4,
                              style: TextStyle(fontSize: 14, color: colorScheme.onSurface, height: 1.4),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: colorScheme.surfaceContainerLowest,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: colorScheme.primary.withValues(alpha: 0.5),
                                    width: 1.5,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.all(14),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // TTL control
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.timer_outlined,
                                        size: 16,
                                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Expires in ${ttlDays.round()} day${ttlDays.round() == 1 ? '' : 's'}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Slider(
                                    value: ttlDays,
                                    min: 1,
                                    max: EphemeralContext.maxTtlDays.toDouble(),
                                    divisions: EphemeralContext.maxTtlDays - 1,
                                    label: '${ttlDays.round()}d',
                                    onChanged: (v) => setSheetState(() => ttlDays = v),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Actions
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => Navigator.pop(sheetContext, true),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Save', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
      },
    );

    if (result == true) {
      final content = contentController.text.trim();
      if (content.isEmpty) return;

      final newExpiry = DateTime.now().add(Duration(days: ttlDays.round()));
      final updated = existing.copyWith(content: content, expiresAt: newExpiry);
      await widget.onSaveEphemeral(updated);

      setState(() {
        final idx = _ephemeral.indexWhere((e) => e.id == existing.id);
        if (idx >= 0) _ephemeral[idx] = updated;
      });
    }

    contentController.dispose();
  }

  // ---- Save / Clear ----

  Future<void> _handleProfileSave() async {
    if (_profileExceedsLimit && widget.onResummarize != null) {
      final shouldResummarize = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Profile Too Large'),
          content: const Text(
            'Profile exceeds the allowed size. Reduce content manually, or auto-resummarize to fit?',
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
        for (final section in _profileSections) {
          if (section.estimatedTokens > MemoryConstants.maxPerSectionTokens) {
            final condensed = await widget.onResummarize!(
              section.value,
              MemoryConstants.maxPerSectionTokens,
            );
            if (condensed != null) {
              setState(() => section.value = condensed);
            }
          }
        }
      } else {
        return;
      }
    }

    widget.onSaveProfile(_profileSections);
    if (mounted) Navigator.pop(context);
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Memory?'),
        content: const Text(
          'This will delete profile, topics, and recent context. This cannot be undone.',
        ),
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

// ---------------------------------------------------------------------------
// Shared animated icon
// ---------------------------------------------------------------------------

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
