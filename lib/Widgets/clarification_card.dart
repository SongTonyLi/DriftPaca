import 'package:flutter/material.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Utils/motion.dart';

/// The one place a research run stops and asks the user something: a
/// question with checkbox options, shown before the first search when the
/// message could mean several distinct things (see `ResearchClarification`).
///
/// Two states, decided by [ClarificationSegment.isAnswered]. While open it
/// is a form — pick any that apply, and/or type an answer of your own, then
/// Continue, or Skip to let the run proceed on its own reading. Once
/// answered (or reloaded from a saved message, which is always answered) it
/// is a record of what was asked and chosen, with the picks marked, the
/// typed answer shown, and the form controls gone: the run has moved on,
/// and a control that could no longer do anything would only invite a tap.
///
/// The typed answer exists because the options are the model's guesses at
/// what the user meant, and the case that most needs a clarification is
/// the one where it guessed wrong — "which Mercury?" with three readings
/// listed and the user meaning a fourth. Without a way to say so, the only
/// exits were a wrong tick or Skip, and Skip hands the run back to the
/// very ambiguity it stopped on. The typed text travels as one more pick,
/// after the ticked options, so everything downstream (the brief, the
/// completeness gate, the ledger's instance split) treats the user's own
/// words exactly as it treats an option they endorsed.
///
/// Shares the research ledger panel's visual language — the same
/// container, the same header row with a leading icon — rather than a new
/// one, since it sits directly under that panel in the bubble.
class ClarificationCard extends StatefulWidget {
  final ClarificationSegment segment;

  /// Called with the answer: the picked options in option order, then the
  /// typed answer if there is one (empty for Skip). Null makes the card
  /// read-only even while unanswered — a bubble with no run to resume.
  final void Function(List<String> selected)? onAnswer;

  const ClarificationCard({super.key, required this.segment, this.onAnswer});

  /// The entries of an answer that were typed rather than ticked: whatever
  /// [selected] holds that is not one of [options]. How a reloaded card
  /// tells the two apart, since the answer is saved as one list.
  static List<String> typedAnswers(
          List<String> selected, List<String> options) =>
      [
        for (final entry in selected)
          if (!options.contains(entry)) entry
      ];

  @override
  State<ClarificationCard> createState() => _ClarificationCardState();
}

class _ClarificationCardState extends State<ClarificationCard> {
  final _picked = <String>{};
  final _typed = TextEditingController();

  bool get _interactive => !widget.segment.isAnswered && widget.onAnswer != null;

  String get _typedAnswer => _typed.text.trim();

  bool get _canContinue => _picked.isNotEmpty || _typedAnswer.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Continue's enabled state follows the field as it is typed in, the
    // same way it follows the checkboxes.
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  void _submit(List<String> selected) {
    widget.onAnswer?.call(selected);
  }

  void _continue() {
    if (!_canContinue) return;
    _submit([
      // Options order, not tap order, so the note reads the way the card
      // does; the typed answer last, after everything that was ticked.
      for (final o in widget.segment.options)
        if (_picked.contains(o)) o,
      if (_typedAnswer.isNotEmpty) _typedAnswer,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final segment = widget.segment;
    final answered = segment.isAnswered;
    final chosen = segment.selected ?? const <String>[];
    final typedAnswers =
        answered ? ClarificationCard.typedAnswers(chosen, segment.options) : const <String>[];

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
                  // What the user typed, kept on the record next to what
                  // they ticked — it is the answer, in their words.
                  for (final answer in typedAnswers) _TypedAnswerRow(answer),
                  if (_interactive) ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: _typed,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _continue(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.3,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Or type your own answer',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
                        prefixIcon: Icon(Icons.edit_outlined,
                            size: 18, color: colorScheme.onSurfaceVariant),
                        prefixIconConstraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: _canContinue ? _continue : null,
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

/// An answer the user typed, on an answered card: laid out like a ticked
/// option, with a pen where the checkbox would be, so the record reads as
/// one list of what they said.
class _TypedAnswerRow extends StatelessWidget {
  final String answer;

  const _TypedAnswerRow(this.answer);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Icon(Icons.edit_outlined,
                size: 18, color: colorScheme.primary),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              answer,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
