import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:llamaseek/Pages/chat_page/chat_page_view_model.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:llamaseek/Extensions/code_syntax_highlighter.dart';
import 'package:llamaseek/Extensions/matched_latex_block_syntax.dart';
import 'package:llamaseek/Extensions/markdown_stylesheet_extension.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Utils/markdown_latex_preprocessor.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:llamaseek/Utils/favicon_cache.dart';
import 'package:llamaseek/Utils/search_thinking_utils.dart';

import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Widgets/search_card.dart';

import 'chat_bubble_actions.dart';
import 'chat_bubble_image.dart';
import 'package:llamaseek/Widgets/glass_context_menu.dart';
import 'chat_bubble_think_block.dart' show ThinkBlockParser, ThinkBlockWidget;
import 'streaming_llama.dart';

class ChatBubble extends StatelessWidget {
  final OllamaMessage message;
  final bool isStreaming;
  final bool animate;
  final List<MessageSegment> searchSegments;

  const ChatBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
    this.animate = false,
    this.searchSegments = const [],
  });

  @override
  Widget build(BuildContext context) {
    return _ChatBubbleBody(message: message, isStreaming: isStreaming, animate: animate, searchSegments: searchSegments);
  }
}

class _ChatBubbleBody extends StatelessWidget {
  final OllamaMessage message;
  final bool isStreaming;
  final bool animate;
  final List<MessageSegment> searchSegments;

  const _ChatBubbleBody({required this.message, required this.isStreaming, this.animate = false, this.searchSegments = const []});

  static final md.ExtensionSet _markdownExtensionSet = md.ExtensionSet(
    [
      ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
      const MatchedLatexBlockSyntax(),
    ],
    [
      _InlineHtmlBrSyntax(),
      _InlineLatexSyntax(),
      ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
    ],
  );

  bool get isSentFromUser => message.role == OllamaMessageRole.user;

  CrossAxisAlignment get bubbleAlignment => isSentFromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: isSentFromUser ? 48.0 : 14.0,
        right: isSentFromUser ? 8.0 : 14.0,
        top: 3.0,
        bottom: 3.0,
      ),
      child: Column(
        crossAxisAlignment: bubbleAlignment,
        children: [
          if (message.images != null && message.images!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: message.images!.asMap().entries.map((entry) => ChatBubbleImage(
                  imageFile: entry.value,
                  allImages: message.images!,
                  index: entry.key,
                )).toList(),
              ),
            ),
          if (isSentFromUser)
            _UserBubbleEntrance(
              animate: animate,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      TimeOfDay.fromDateTime(message.createdAt).format(context),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  _wrapWithMenu(
                    context,
                    _UserBubble(message: message, buildMarkdown: _buildMarkdown),
                  ),
                  _UserActionButtons(message: message),
                ],
              ),
            )
          else
            _AssistantBubble(
              message: message,
              isStreaming: isStreaming,
              buildMarkdown: _buildMarkdown,
              searchSegments: searchSegments,
            ),
        ],
      ),
    );
  }

  Widget _wrapWithMenu(BuildContext context, Widget child) {
    // Long-press only — no tap/double-tap recognizers — so citation links and
    // other tappable content inside the bubble keep their taps. Disabled while
    // the reply is still streaming.
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onLongPressStart: isStreaming
          ? null
          : (details) => showGlassContextMenu(
                context: context,
                position: details.globalPosition,
                actions: [
                  GlassMenuAction(
                    icon: Icons.delete_outline,
                    label: 'Delete exchange',
                    isDestructive: true,
                    onTap: () =>
                        ChatBubbleActions(message).handleDeleteExchange(context),
                  ),
                ],
              ),
      child: child,
    );
  }

  static Widget _buildMarkdown(BuildContext context, String data, {bool selectable = false}) {
    // Material Scrollbar (used by flutter_markdown for wide-table horizontal
    // scroll) reads MediaQuery.paddingOf(context) and inset its track by that
    // amount. Inside a chat bubble that isn't anywhere near the screen edge,
    // the iOS home-indicator inset (~34px) pushes the horizontal scrollbar
    // up — making it appear mid-table instead of at the bottom. Stripping
    // padding here keeps the scrollbar pinned to the table's actual bottom.
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: MarkdownBody(
        data: preprocessMarkdownLatex(data),
        selectable: selectable,
        softLineBreak: true,
        styleSheet: context.markdownStyleSheet,
        syntaxHighlighter: CodeSyntaxHighlighter(
          brightness: Theme.of(context).brightness,
        ),
        extensionSet: _markdownExtensionSet,
        builders: {
          'a': _LinkBuilder(),
          'latex': _SmartLatexBuilder(),
          'br': _HtmlBrBuilder(),
        },
        // No onTapLink: flutter_markdown attaches the link's TapGestureRecognizer
        // to the prose spans that FOLLOW the link, so an onTapLink handler would
        // open the citation URL when the user taps that trailing text. The
        // favicon from _LinkBuilder carries its own GestureDetector, so taps are
        // already handled at the icon itself.
      ),
    );
  }

  /// Truncates trailing incomplete link syntax (`[text](url` without closing
  /// `)`) so it doesn't render as raw markdown while the typewriter reveal
  /// catches up to the closing paren. Once `)` is revealed the full link
  /// renders normally.
  static final _incompleteLinkAtEndPattern =
      RegExp(r'\[[^\]\n]*\]\([^)\n]*$');

  static String _hideIncompleteLinks(String content) {
    final match = _incompleteLinkAtEndPattern.firstMatch(content);
    if (match == null) return content;
    return content.substring(0, match.start);
  }
}

/// Animates user bubble entrance with a scale pop + fade.
class _UserBubbleEntrance extends StatefulWidget {
  final bool animate;
  final Widget child;

  const _UserBubbleEntrance({this.animate = false, required this.child});

  @override
  State<_UserBubbleEntrance> createState() => _UserBubbleEntranceState();
}

class _UserBubbleEntranceState extends State<_UserBubbleEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
      value: widget.animate ? 0.0 : 1.0,
    );
    _scale = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Cubic(0.34, 1.56, 0.64, 1.0),
      ),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    if (widget.animate) {
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        alignment: Alignment.bottomRight,
        child: widget.child,
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  final OllamaMessage message;
  final Widget Function(BuildContext, String, {bool selectable}) buildMarkdown;

  const _UserBubble({required this.message, required this.buildMarkdown});

  @override
  Widget build(BuildContext context) {
    final color =
        Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.8);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.68,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20.0),
          topRight: Radius.circular(20.0),
          bottomLeft: Radius.circular(20.0),
          bottomRight: Radius.circular(4.0),
        ),
      ),
      child: buildMarkdown(context, message.content),
    );
  }
}

class _AssistantBubble extends StatefulWidget {
  final OllamaMessage message;
  final bool isStreaming;
  final Widget Function(BuildContext, String, {bool selectable}) buildMarkdown;
  final List<MessageSegment> searchSegments;

  const _AssistantBubble({
    required this.message,
    required this.isStreaming,
    required this.buildMarkdown,
    this.searchSegments = const [],
  });

  @override
  State<_AssistantBubble> createState() => _AssistantBubbleState();
}

class _AssistantBubbleState extends State<_AssistantBubble>
    with SingleTickerProviderStateMixin {
  bool _wasStreaming = false;

  // ── Typewriter reveal state ──
  String _targetContent = '';
  String _targetThinking = '';
  int _revealedLength = 0;
  int _revealedThinkingLength = 0;
  Ticker? _revealTicker;
  double _revealProgress = 0.0;
  double _thinkingRevealProgress = 0.0;
  // Throttles how often the reveal rebuilds (re-parses markdown). Independent
  // wall clock so it survives the ticker stopping/restarting.
  final Stopwatch _revealThrottle = Stopwatch()..start();

  static const double _baseCharsPerFrame = 0.7;
  static const int _catchUpThreshold = 80;
  // Drain any backlog within ~this many frames (~1.5s at 60fps). A fixed
  // chars/frame cap made long answers reveal over hundreds of frames, and
  // every frame re-parses the full (growing) markdown + preprocessing chain —
  // which spiked memory and janked other animations (e.g. the prompt bar).
  // Bounding the frame count keeps long text a fast-but-visible stream while
  // short text still reveals at the gentle base pace.
  static const int _revealFrameBudget = 90;

  /// Reveal rate in chars/frame: gentle base pace for a small backlog,
  /// otherwise fast enough to finish the backlog within [_revealFrameBudget]
  /// frames so a long answer never re-parses markdown for many seconds.
  double _revealSpeed(int remaining) {
    if (remaining <= _catchUpThreshold) return _baseCharsPerFrame;
    final budgetPace = remaining / _revealFrameBudget;
    return budgetPace > _baseCharsPerFrame ? budgetPace : _baseCharsPerFrame;
  }

  /// True once both thinking and response content are fully revealed.
  bool get _revealComplete =>
      _revealedThinkingLength >= _targetThinking.length &&
      _revealedLength >= _targetContent.length;

  /// Whether the typewriter should drive the displayed text: during the
  /// stream, and afterwards while a buffered tail is still being revealed.
  /// History messages (never streamed) skip the reveal and render in full.
  bool get _isRevealing =>
      widget.isStreaming || (_wasStreaming && !_revealComplete);

  /// Returns the thinking text to display for this bubble.
  /// When search segments are shown, only the model thinking portion is shown
  /// since search thinking is rendered separately above.
  String _displayThinking(String? thinking) {
    if (thinking == null || thinking.isEmpty) return '';
    // Strip search data header if present (both live and history)
    var clean = stripSearchData(thinking);
    if (widget.searchSegments.isNotEmpty || thinking.startsWith('<!--SEARCH_DATA:')) {
      // If no separator exists, the thinking is only Call 1 thinking which
      // is already rendered as a ThinkingSegment in searchWidgets. Return
      // empty to avoid duplication.
      if (!clean.contains(searchThinkingSeparator)) return '';
      return modelThinkingFromCombined(clean);
    }
    return clean;
  }

  /// Gets search segments: live from ViewModel during streaming,
  /// or deserialized from thinking field for history messages.
  List<MessageSegment> _getSearchSegments() {
    // Live segments from ViewModel (during active search/streaming)
    if (widget.searchSegments.isNotEmpty) return widget.searchSegments;

    // Try to deserialize from persisted thinking field
    final thinking = widget.message.thinking;
    if (thinking != null && thinking.isNotEmpty) {
      final decoded = decodeSearchSegments(thinking);
      if (decoded != null) return decoded;
    }
    return const [];
  }

  @override
  void initState() {
    super.initState();
    _targetContent = widget.message.content;
    _targetThinking = _displayThinking(widget.message.thinking);
    // Show whatever content is already present on creation as an immediate
    // head start, so the bubble isn't blank until didUpdateWidget fires on the
    // next token. The ticker then reveals only tokens that arrive afterwards.
    _revealedLength = _targetContent.length;
    _revealedThinkingLength = _targetThinking.length;
    _revealProgress = _revealedLength.toDouble();
    _thinkingRevealProgress = _revealedThinkingLength.toDouble();
    if (widget.isStreaming) {
      _ensureRevealTicker();
    }
  }

  @override
  void didUpdateWidget(_AssistantBubble old) {
    super.didUpdateWidget(old);
    final nextThinking = _displayThinking(widget.message.thinking);
    if (old.isStreaming && !widget.isStreaming) {
      // Stream finished. Don't jump to the full text — keep the typewriter
      // running so any buffered remainder still reveals progressively. The
      // ticker stops itself in _onRevealTick once it catches up.
      _wasStreaming = true;
      _targetContent = widget.message.content;
      _targetThinking = nextThinking;
      if (_revealedThinkingLength > _targetThinking.length) {
        _revealedThinkingLength = _targetThinking.length;
        _thinkingRevealProgress = _revealedThinkingLength.toDouble();
      }
      if (_revealedLength > _targetContent.length) {
        _revealedLength = _targetContent.length;
        _revealProgress = _revealedLength.toDouble();
      }
      _ensureRevealTicker();
    } else if (widget.isStreaming) {
      _targetContent = widget.message.content;
      _targetThinking = nextThinking;
      // Clamp reveal progress if content was shortened (e.g., WEBSEARCH clear)
      if (_revealedLength > _targetContent.length) {
        _revealedLength = _targetContent.length;
        _revealProgress = _revealedLength.toDouble();
      }
      if (_revealedThinkingLength > _targetThinking.length) {
        _revealedThinkingLength = _targetThinking.length;
        _thinkingRevealProgress = _revealedThinkingLength.toDouble();
      }
      _ensureRevealTicker();
    } else {
      _targetContent = widget.message.content;
      _targetThinking = nextThinking;
      if (_wasStreaming && !_revealComplete) {
        // Just-finished message still typing out its buffered tail — keep
        // the ticker going instead of snapping to the full text.
        _ensureRevealTicker();
      } else {
        // History message, or reveal already complete: show in full.
        _revealedLength = _targetContent.length;
        _revealedThinkingLength = _targetThinking.length;
        _revealProgress = _revealedLength.toDouble();
        _thinkingRevealProgress = _revealedThinkingLength.toDouble();
      }
    }
  }

  /// Lazily creates the reveal ticker on first use; restarts it when paused.
  /// Uses a single Ticker for the widget's lifetime to avoid violating
  /// SingleTickerProviderStateMixin's one-ticker contract.
  void _ensureRevealTicker() {
    if (_revealTicker == null) {
      _revealTicker = createTicker(_onRevealTick);
    }
    if (!_revealTicker!.isActive) {
      _revealTicker!.start();
    }
  }

  void _stopRevealTicker() {
    _revealTicker?.stop();
  }

  void _onRevealTick(Duration elapsed) {
    // Advance the reveal cursor every frame, but only rebuild (which re-parses
    // the whole markdown) at ~30fps. At 60fps the re-parse competes with the
    // stream notifications and starves other animations like the prompt bar.
    // Reveal thinking tokens first, then response content.
    if (_revealedThinkingLength < _targetThinking.length) {
      final remaining = _targetThinking.length - _revealedThinkingLength;
      _thinkingRevealProgress += _revealSpeed(remaining);
      final newLen = _thinkingRevealProgress.floor().clamp(0, _targetThinking.length);
      if (newLen != _revealedThinkingLength &&
          _revealDue(newLen >= _targetThinking.length)) {
        setState(() => _revealedThinkingLength = newLen);
      }
    } else if (_revealedLength < _targetContent.length) {
      final remaining = _targetContent.length - _revealedLength;
      _revealProgress += _revealSpeed(remaining);
      final newLen = _revealProgress.floor().clamp(0, _targetContent.length);
      if (newLen != _revealedLength &&
          _revealDue(newLen >= _targetContent.length)) {
        setState(() => _revealedLength = newLen);
      }
    } else {
      _stopRevealTicker();
    }
  }

  /// Whether a reveal rebuild should happen this frame: at most every ~33ms
  /// (~30fps), but always when the phase reaches its target so the final
  /// characters flush and the ticker can stop.
  bool _revealDue(bool reachedTarget) {
    if (reachedTarget || _revealThrottle.elapsedMilliseconds >= 33) {
      _revealThrottle.reset();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _revealTicker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMessageContent(context),
          // Llama on its own line: running during streaming, resting after
          if (widget.isStreaming || _wasStreaming)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: StreamingLlama(isRunning: widget.isStreaming),
            ),
          // Smoothly reveal action buttons when streaming ends
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: _isRevealing
                ? const SizedBox(width: double.infinity, height: 0)
                : Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _AssistantActionButtons(message: widget.message),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelLabel(BuildContext context) {
    final model = widget.message.model;
    if (model == null || model.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        model,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// Builds search segment widgets (thinking blocks + search cards) from a list of segments.
  List<Widget> _buildSearchSegmentsFrom(List<MessageSegment> segments) {
    final widgets = <Widget>[];
    for (final segment in segments) {
      switch (segment) {
        case ThinkingSegment():
          if (segment.text.isEmpty) continue;
          widgets.add(ThinkBlockWidget(
            content: segment.text,
            isComplete: true,
            isStreaming: false,
          ));
        case SearchCardSegment():
          widgets.add(SearchCard(segment: segment));
        case AnswerSegment():
          break;
      }
    }
    return widgets;
  }

  /// Rewinds a reveal cursor by one code unit when it lands between the two
  /// halves of a UTF-16 surrogate pair, so [String.substring] never emits an
  /// orphaned high surrogate (which renders as a tofu box for one frame).
  int _surrogateSafeLength(String text, int length) {
    if (length <= 0) return length;
    final safe = length > text.length ? text.length : length;
    final unit = text.codeUnitAt(safe - 1);
    // A high surrogate (0xD800–0xDBFF) as the last included unit leaves its low
    // half outside the cut — whether the low half exists further along (a
    // mid-reveal boundary) or the target itself ends mid-pair (a stream chunk
    // split across a code point). Cut before the high surrogate in both cases.
    return (unit >= 0xD800 && unit <= 0xDBFF) ? safe - 1 : safe;
  }

  Widget _buildMessageContent(BuildContext context) {
    final content = _isRevealing
        ? _ChatBubbleBody._hideIncompleteLinks(
            _targetContent.substring(
                0, _surrogateSafeLength(_targetContent, _revealedLength)))
        : widget.message.content;

    final segments = _getSearchSegments();
    final searchWidgets = _buildSearchSegmentsFrom(segments);

    final displayThinking = _displayThinking(widget.message.thinking);
    if (displayThinking.isNotEmpty) {
      final thinkingContent = _isRevealing
          ? _targetThinking.substring(
              0, _surrogateSafeLength(_targetThinking, _revealedThinkingLength))
          : displayThinking;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildModelLabel(context),
          ...searchWidgets,
          ThinkBlockWidget(
            content: thinkingContent,
            isComplete: content.isNotEmpty,
            isStreaming: widget.isStreaming,
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 4),
            widget.buildMarkdown(context, content),
          ],
        ],
      );
    }

    final parsed = ThinkBlockParser.tryParse(content);

    if (parsed != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildModelLabel(context),
          ...searchWidgets,
          ThinkBlockWidget(
            content: parsed.thinkContent,
            isComplete: parsed.isThinkingComplete,
            isStreaming: widget.isStreaming,
          ),
          if (parsed.responseContent.isNotEmpty) ...[
            const SizedBox(height: 4),
            widget.buildMarkdown(context, parsed.responseContent),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildModelLabel(context),
        ...searchWidgets,
        if (content.isNotEmpty) widget.buildMarkdown(context, content),
      ],
    );
  }
}

/// Copy and Edit buttons shown below user messages.
class _UserActionButtons extends StatelessWidget {
  final OllamaMessage message;

  const _UserActionButtons({required this.message});

  @override
  Widget build(BuildContext context) {
    final actions = ChatBubbleActions(message);
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CopyChip(onCopy: actions.handleCopy),
        const SizedBox(width: 8),
        _ActionChip(
          icon: Icons.edit_outlined,
          label: 'Edit',
          color: colorScheme.onSurfaceVariant,
          onTap: () async {
            final result = await _showEditPopup(context, message);
            if (result != null && context.mounted) {
              final viewModel = Provider.of<ChatPageViewModel>(context, listen: false);
              viewModel.editAndResend(message, result);
            }
          },
        ),
      ],
    );
  }
}

/// Copy and Regenerate buttons shown below assistant messages.
class _AssistantActionButtons extends StatelessWidget {
  final OllamaMessage message;

  const _AssistantActionButtons({required this.message});

  @override
  Widget build(BuildContext context) {
    final actions = ChatBubbleActions(message);
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CopyChip(onCopy: actions.handleCopy),
        const SizedBox(width: 8),
        _ActionChip(
          icon: Icons.refresh_outlined,
          label: 'Regenerate',
          color: colorScheme.onSurfaceVariant,
          onTap: () => actions.handleRegenerate(context),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Copy chip that shows "Copied" feedback with checkmark for 3 seconds.
class _CopyChip extends StatefulWidget {
  final VoidCallback onCopy;

  const _CopyChip({required this.onCopy});

  @override
  State<_CopyChip> createState() => _CopyChipState();
}

class _CopyChipState extends State<_CopyChip> with SingleTickerProviderStateMixin {
  bool _copied = false;

  void _handleTap() {
    widget.onCopy();
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _copied ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: InkWell(
        key: ValueKey(_copied),
        onTap: _handleTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _copied ? Icons.check_rounded : Icons.copy_outlined,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                _copied ? 'Copied' : 'Copy',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: _copied ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows an animated edit popup that expands from the chat bubble.
/// Returns the edited text if saved, null if cancelled.
Future<String?> _showEditPopup(BuildContext context, OllamaMessage message) async {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (dialogContext, animation, secondaryAnimation, _) {
      final moveCurve = CurvedAnimation(
        parent: animation,
        curve: const Cubic(0.16, 1.0, 0.3, 1.0),
        reverseCurve: Curves.easeInQuart,
      );
      final fadeCurve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      );

      return FadeTransition(
        opacity: fadeCurve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(moveCurve),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(moveCurve),
            child: _EditPopupContent(message: message),
          ),
        ),
      );
    },
  );
}

class _EditPopupContent extends StatefulWidget {
  final OllamaMessage message;

  const _EditPopupContent({required this.message});

  @override
  State<_EditPopupContent> createState() => _EditPopupContentState();
}

class _EditPopupContentState extends State<_EditPopupContent> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.message.content);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.15),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                          child: TextField(
                            controller: _controller,
                            autofocus: true,
                            maxLines: null,
                            textCapitalization: TextCapitalization.sentences,
                            style: Theme.of(context).textTheme.bodyLarge,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Edit message...',
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  color: colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: () {
                                final text = _controller.text.trim();
                                if (text.isNotEmpty) {
                                  Navigator.pop(context, text);
                                }
                              },
                              icon: const Icon(Icons.send_rounded, size: 16),
                              label: const Text('Send as New'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Converts <br>, <br/>, <br /> into a `br` element rendered as a
/// full-width line break widget. Using a WidgetSpan (via _HtmlBrBuilder)
/// instead of a \n text node avoids a Flutter RichText issue where
/// WidgetSpan elements don't follow \n line breaks correctly — they
/// float to the previous line instead of staying with their text.
class _InlineHtmlBrSyntax extends md.InlineSyntax {
  _InlineHtmlBrSyntax() : super(r'<br\s*/?>', startCharacter: 0x3C);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.empty('br'));
    return true;
  }
}

/// Renders `br` elements as a full-width zero-height widget that
/// forces subsequent inline content to the next line.
class _HtmlBrBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return const SizedBox(width: double.infinity, height: 0);
  }
}

/// Renders markdown links as a small inline favicon that pops in. The
/// destination's website logo replaces the visible link text — the user
/// sees the brand, taps the brand. Hit area is locked to the visible
/// circle via `HitTestBehavior.opaque`, so taps next to the icon never
/// trigger the URL.
///
/// Favicons are expected to be in the [FaviconCache] (preloaded by the
/// web-search pipeline). On cache miss the widget kicks off a fetch and
/// animates in once the bytes arrive; on permanent failure it shows a
/// muted globe glyph.
///
/// Wrapping the result in a `WidgetSpan` inside a `Text.rich` lets
/// flutter_markdown's [_mergeInlineChildren] merge it with surrounding
/// text so the favicon flows inline.
class _LinkBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final href = element.attributes['href'] ?? '';
    if (href.isEmpty) return null;

    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            baseline: TextBaseline.alphabetic,
            child: _LinkFavicon(href: href),
          ),
        ],
      ),
    );
  }
}

/// Animated favicon for inline links. Plays a one-shot scale + fade "pop"
/// when the favicon resolves, mirroring sticker-placement feel.
class _LinkFavicon extends StatefulWidget {
  final String href;

  const _LinkFavicon({required this.href});

  @override
  State<_LinkFavicon> createState() => _LinkFaviconState();
}

class _LinkFaviconState extends State<_LinkFavicon>
    with SingleTickerProviderStateMixin {
  static const double _size = 16.0;
  // easeOutBack — gentle overshoot (~10%) without oscillation. Subtler
  // than elasticOut for a 16px icon, so a paragraph of citations doesn't
  // visually rattle when they pop in.
  static const Cubic _popCurve = Cubic(0.34, 1.56, 0.64, 1.0);

  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  Uint8List? _bytes;
  String _domain = '';
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _scale = CurvedAnimation(parent: _controller, curve: _popCurve);
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
    _domain = Uri.tryParse(widget.href)?.host ?? '';

    // When bytes are already cached we skip the pop entirely and render
    // at full scale. During streaming, MarkdownBody re-parses on every
    // typewriter tick and recreates the WidgetSpan child — if we
    // animated from 0 on each build, the controller would never reach 1
    // before the next rebuild, and the favicon would stay invisible
    // until streaming finished. Skipping the animation for cached bytes
    // makes citations appear instantly during streaming (which is the
    // common case once `FaviconCache.preload` has warmed the cache).
    final cache = FaviconCache.instance;
    if (cache.isResolved(_domain)) {
      _bytes = cache.bytesFor(_domain);
      _resolved = true;
      _controller.value = 1.0;
    } else {
      _resolveFavicon();
    }
  }

  Future<void> _resolveFavicon() async {
    if (_domain.isEmpty) {
      _resolved = true;
      _controller.value = 1.0;
      return;
    }

    final bytes = await FaviconCache.instance.fetch(_domain);
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _resolved = true;
    });
    // Only animate when bytes have just arrived from the network — there
    // was a real "appear" moment to celebrate. Cached bytes never get
    // here.
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Hit area is pinned to the visible favicon rectangle (16x16) and
    // not the padding/spacing around it. The GestureDetector lives
    // inside the SizedBox so its bounds match the icon exactly — taps
    // in adjacent text or whitespace never route here.
    return SizedBox(
      width: _size,
      height: _size,
      child: ScaleTransition(
        scale: _scale,
        child: FadeTransition(
          opacity: _fade,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => launchUrlString(widget.href),
            child: _resolved ? _buildIcon(colorScheme) : null,
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(ColorScheme colorScheme) {
    if (_bytes != null) {
      return ClipOval(
        child: Image.memory(
          _bytes!,
          width: _size,
          height: _size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _fallbackGlyph(colorScheme),
        ),
      );
    }
    return _fallbackGlyph(colorScheme);
  }

  Widget _fallbackGlyph(ColorScheme colorScheme) {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.onSurface.withValues(alpha: 0.10),
      ),
      child: Icon(
        Icons.language_rounded,
        size: _size * 0.72,
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
    );
  }
}

class _InlineLatexSyntax extends md.InlineSyntax {
  // Match $$...$$ (display) or $...$ (inline).
  // No restrictive lookahead — allows LaTeX inside bold, before dashes, etc.
  _InlineLatexSyntax() : super(r'\$\$([\s\S]+?)\$\$|\$([^$\n]+?)\$', startCharacter: 0x24);

  /// Math operators that unambiguously indicate LaTeX, not currency.
  /// Excludes `*` (used in markdown bold **) and `-` (used in prose).
  /// Currency: "$514 billion" — digits + words, no LaTeX operators.
  /// LaTeX: "$1+1=2$" — has +, =, ^, etc.
  static final _mathOperatorPattern = RegExp(r'[+=^_\\{}<>]|(?<!\*)\*(?!\*)');

  /// Currency: starts with digit and contains NO LaTeX operators — OR is
  /// a prose-currency span the preprocessor would have escaped.
  ///
  /// [preprocessMarkdownLatex] normally escapes the `$` signs
  /// before this parser ever sees the pair. Mirroring the prose-currency
  /// heuristic here is defense in depth: if a future pipeline change ever
  /// lets a prose-currency span reach this parser unescaped (e.g. through a
  /// nested context the preprocessor doesn't traverse), it still renders as
  /// text instead of a non-wrapping LaTeX run.
  static bool _isCurrency(String content) {
    if (!RegExp(r'^\s*[\d,.]').hasMatch(content)) return false;
    // Strip markdown bold markers before checking for math operators
    final stripped = content.replaceAll('**', '');
    if (!_mathOperatorPattern.hasMatch(stripped)) return true;
    return looksLikeCurrencyProse(content);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final displayContent = match.group(1);
    final inlineContent = match.group(2);
    final equation = (displayContent ?? inlineContent)?.trim();

    // MUST always return true when regex matched — returning false
    // without consuming causes InlineParser to loop infinitely.
    if (equation == null || equation.isEmpty) {
      parser.addNode(md.Text(match.group(0)!));
      return true;
    }

    // Guard: inline $...$ that looks like currency (starts with digit, no math operators).
    // Display $$...$$ is always treated as LaTeX (currency never uses $$).
    if (inlineContent != null && _isCurrency(equation)) {
      parser.addNode(md.Text(match.group(0)!));
      return true;
    }

    final isDisplay = displayContent != null;
    final element = md.Element.text('latex', equation);
    element.attributes['MathStyle'] = isDisplay ? 'display' : 'text';
    parser.addNode(element);
    return true;
  }
}

/// Renders LaTeX: inline ($...$) normally, display ($$...$$) centered.
///
/// For inline math, we return a [RichText] containing a [WidgetSpan] so that
/// flutter_markdown's `_mergeInlineChildren` merges it with adjacent text
/// spans into a single flowing [RichText]. Without this, the Math widget
/// becomes a separate child in a [Wrap] and breaks to its own line.
class _SmartLatexBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final text = element.textContent;
    if (text.isEmpty) return const SizedBox();

    final isDisplay = element.attributes['MathStyle'] == 'display';
    final rawSource = isDisplay ? '\$\$$text\$\$' : '\$$text\$';

    // Ensure text color is explicit — flutter_math_fork can render
    // invisible text when preferredStyle has no color (e.g. in tables).
    final effectiveColor = preferredStyle?.color ?? Theme.of(context).textTheme.bodyMedium?.color;
    final mathTextStyle = (preferredStyle ?? const TextStyle()).copyWith(color: effectiveColor);

    final mathWidget = _SmartLatexWidget(
      text: text,
      isDisplay: isDisplay,
      rawSource: rawSource,
      mathTextStyle: mathTextStyle,
    );

    if (isDisplay) return mathWidget;

    // Wrap inline math in RichText+WidgetSpan so it flows with surrounding
    // text instead of breaking to a new line in the Wrap layout.
    return RichText(
      text: TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: mathWidget,
          ),
        ],
      ),
    );
  }
}

class _SmartLatexWidget extends StatelessWidget {
  final String text;
  final bool isDisplay;
  final String rawSource;
  final TextStyle mathTextStyle;

  const _SmartLatexWidget({
    required this.text,
    required this.isDisplay,
    required this.rawSource,
    required this.mathTextStyle,
  });

  @override
  Widget build(BuildContext context) {
    final mathWidget = Math.tex(
      text,
      mathStyle: isDisplay ? MathStyle.display : MathStyle.text,
      textStyle: mathTextStyle,
      onErrorFallback: (_) => _LatexSourceFallback(
        rawSource: rawSource,
        isDisplay: isDisplay,
        preferredStyle: mathTextStyle,
      ),
    );

    if (isDisplay) {
      // Display math: centered, horizontally scrollable for long equations.
      // When inside a table cell, use an intrinsic-friendly viewport to avoid
      // IntrinsicColumnWidth crashing on flutter_math_fork's LayoutBuilder.
      final inTableCell = context.findAncestorWidgetOfExactType<TableCell>() != null;
      if (inTableCell) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: _IntrinsicFriendlyMathViewport(child: mathWidget),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(
          width: double.infinity,
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.antiAlias,
              child: mathWidget,
            ),
          ),
        ),
      );
    }

    // Inline math in table cells: wrap in a scroll view that provides
    // stub intrinsic dimensions. flutter_math_fork's internal LayoutBuilder
    // cannot report intrinsics, but Table with IntrinsicColumnWidth requires
    // them — _IntrinsicFriendlyMathViewport resolves this conflict.
    final inTableCell = context.findAncestorWidgetOfExactType<TableCell>() != null;
    if (inTableCell) {
      return _IntrinsicFriendlyMathViewport(child: mathWidget);
    }

    // Inline math in text: return directly so it flows with surrounding
    // text. Wrapping in SingleChildScrollView breaks WidgetSpan intrinsic
    // width calculation, causing line breaks (e.g. "$N$ 体" splits).
    return mathWidget;
  }
}

/// A horizontally scrollable wrapper that provides safe intrinsic dimensions.
///
/// flutter_math_fork uses LayoutBuilder internally for certain complex
/// constructs (aligned, cases, matrices). LayoutBuilder cannot report intrinsic
/// dimensions. When these widgets are in a Table with IntrinsicColumnWidth,
/// the table's layout algorithm asks for intrinsic widths and crashes.
///
/// This widget solves the conflict by:
/// 1. Reporting a fixed intrinsic width (so the table gets a usable value)
/// 2. Giving a horizontal viewport finite cell constraints during normal layout
/// 3. Exposing the child's natural width through the viewport's scroll extent
class _IntrinsicFriendlyMathViewport extends SingleChildRenderObjectWidget {
  _IntrinsicFriendlyMathViewport({required Widget child})
      : super(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            primary: false,
            child: child,
          ),
        );

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderIntrinsicFriendlyMathViewport();
}

class _RenderIntrinsicFriendlyMathViewport extends RenderProxyBox {
  // Fallback intrinsic width when the child (flutter_math_fork) can't report.
  static const double _fallbackWidth = 50.0;

  double _safeChildIntrinsic(double height, {required bool min}) {
    try {
      final v = min ? child?.getMinIntrinsicWidth(height) : child?.getMaxIntrinsicWidth(height);
      return (v != null && v > 0) ? v : _fallbackWidth;
    } catch (_) {
      return _fallbackWidth;
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) => _safeChildIntrinsic(height, min: true);

  @override
  double computeMaxIntrinsicWidth(double height) {
    final minW = computeMinIntrinsicWidth(height);
    final maxW = _safeChildIntrinsic(height, min: false);
    // Table asserts max >= min.
    return maxW >= minW ? maxW : minW;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    try {
      return child?.getMinIntrinsicHeight(width) ?? 0;
    } catch (_) {
      return 20;
    }
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    try {
      return child?.getMaxIntrinsicHeight(width) ?? 0;
    } catch (_) {
      return 20;
    }
  }

  @override
  bool get isRepaintBoundary => true;
}

class _LatexSourceFallback extends StatelessWidget {
  final String rawSource;
  final bool isDisplay;
  final TextStyle? preferredStyle;

  const _LatexSourceFallback({
    required this.rawSource,
    required this.isDisplay,
    this.preferredStyle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final markdownStyleSheet = context.markdownStyleSheet;
    final textStyle = markdownStyleSheet.code
            ?.copyWith(
              backgroundColor: Colors.transparent,
              color: colorScheme.onSurface.withValues(alpha: 0.82),
            )
            .merge(
              preferredStyle?.copyWith(
                backgroundColor: Colors.transparent,
                color: colorScheme.onSurface.withValues(alpha: 0.82),
              ),
            ) ??
        preferredStyle?.copyWith(
          color: colorScheme.onSurface.withValues(alpha: 0.82),
        );

    if (isDisplay) {
      // Do NOT use width: double.infinity here — this fallback can be rendered
      // inside a horizontal SingleChildScrollView (from _SmartLatexWidget's
      // display mode), which provides unbounded width constraints.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: DecoratedBox(
          decoration: markdownStyleSheet.codeblockDecoration ?? const BoxDecoration(),
          child: Padding(
            padding: markdownStyleSheet.codeblockPadding ?? const EdgeInsets.all(14),
            child: Text(rawSource, style: textStyle),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(rawSource, style: textStyle),
      ),
    );
  }
}
