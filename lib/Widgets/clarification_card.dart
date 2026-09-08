import 'package:flutter/material.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Utils/motion.dart';

/// The one place a research run stops and asks the user something: a
/// question with checkbox options, shown before the first search when the
/// message could mean several distinct things (see `ResearchClarification`).
///
/// Two states, decided by [ClarificationSegment.isAnswered]. While open it
/// is a form — pick any that apply, then Continue, or Skip to let the run
/// proceed on its own reading. Once answered (or reloaded from a saved
/// message, which is always answered) it is a record of what was asked
/// and chosen, with the picks marked and the form controls gone: the run
/// has moved on, and a control that could no longer do anything would only
/// invite a tap.
///
/// Shares the research ledger panel's visual language — the same
/// container, the same header row with a leading icon — rather than a new
/// one, since it sits directly under that panel in the bubble.
class ClarificationCard extends StatefulWidget {
  final ClarificationSegment segment;

  /// Called with the picked options (empty for Skip). Null makes the card
  /// read-only even while unanswered — a bubble with no run to resume.
  final void Function(List<String> selected)? onAnswer;

  const ClarificationCard({super.key, required this.segment, this.onAnswer});

  @override
  State<ClarificationCard> createState() => _ClarificationCardState();
}

class _ClarificationCardState extends State<ClarificationCard> {
  final _picked = <String>{};

  bool get _interactive => !widget.segment.isAnswered && widget.onAnswer != null;

  void _submit(List<String> selected) {
    widget.onAnswer?.call(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final segment = widget.segment;
    final answered = segment.isAnswered;
    final chosen = segment.selected ?? const <String>[];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _interactive
                ? colorScheme.primary.withValues(alpha: 0.45)
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  Icon(Icons.help_outline,
                      size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      answered
                          ? (chosen.isEmpty ? 'Clarification skipped' : 'Clarified')
                          : 'Before searching — what do you mean?',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 4, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    segment.question,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final option in segment.options)
                    _OptionRow(
                      label: option,
                      checked: answered
                          ? chosen.contains(option)
                          : _picked.contains(option),
                      // A pick the user made stays legible after the run
                      // moves on; unpicked options fade back.
                      muted: answered && !chosen.contains(option),
                      onChanged: _interactive
                          ? (value) => setState(() {
                                if (value) {
                                  _picked.add(option);
                                } else {
                                  _picked.remove(option);
                                }
                              })
                          : null,
                    ),
                  if (_interactive) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: _picked.isEmpty
                              ? null
                              : () => _submit([
                                    // Options order, not tap order, so the
                                    // note reads the way the card does.
                                    for (final o in segment.options)
                                      if (_picked.contains(o)) o
                                  ]),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                          ),
                          child: const Text('Continue'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => _submit(const []),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Skip'),
                        ),
                      ],
                    ),
                  ] else if (!answered) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Waiting for an answer…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String label;
  final bool checked;
  final bool muted;
  final ValueChanged<bool>? onChanged;

  const _OptionRow({
    required this.label,
    required this.checked,
    required this.muted,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textColor = muted
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
        : colorScheme.onSurface;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!checked),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Checkbox(
                value: checked,
                onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: motionDuration(context, const Duration(milliseconds: 150)),
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: textColor,
                  height: 1.3,
                ),
                child: Text(label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
