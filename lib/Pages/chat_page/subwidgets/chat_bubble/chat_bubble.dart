import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:llamaseek/Pages/chat_page/chat_page_view_model.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:llamaseek/Extensions/code_syntax_highlighter.dart';
import 'package:llamaseek/Extensions/matched_latex_block_syntax.dart';
import 'package:llamaseek/Extensions/markdown_stylesheet_extension.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Utils/markdown_latex_preprocessor.dart';
import 'package:llamaseek/Utils/motion.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:llamaseek/Utils/favicon_cache.dart';
import 'package:llamaseek/Utils/search_thinking_utils.dart';
import 'package:llamaseek/Utils/surrogate_safe_length.dart';

import 'package:llamaseek/Models/research_ledger.dart';
import 'package:llamaseek/Models/research_phase.dart';
import 'package:llamaseek/Models/search_event.dart';
import 'package:llamaseek/Widgets/research_activity_strip.dart';
import 'package:llamaseek/Widgets/search_card.dart';
import 'package:llamaseek/Widgets/clarification_card.dart';

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

  /// What the research loop is doing right now, and since when. Set only on
  /// the live bubble of a running agentic search — a cached bubble from
  /// further up the conversation is not the run, so it is handed null and
  /// shows no strip.
  final ResearchPhase? researchPhase;
  final DateTime? researchPhaseStartedAt;

  const ChatBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
    this.animate = false,
    this.searchSegments = const [],
    this.researchPhase,
    this.researchPhaseStartedAt,
  });

  @override
  Widget build(BuildContext context) {
    return _ChatBubbleBody(
      message: message,
      isStreaming: isStreaming,
      animate: animate,
      searchSegments: searchSegments,
      researchPhase: researchPhase,
      researchPhaseStartedAt: researchPhaseStartedAt,
    );
  }
}

class _ChatBubbleBody extends StatelessWidget {
  final OllamaMessage message;
  final bool isStreaming;
  final bool animate;
  final List<MessageSegment> searchSegments;
  final ResearchPhase? researchPhase;
  final DateTime? researchPhaseStartedAt;

  const _ChatBubbleBody({
    required this.message,
    required this.isStreaming,
    this.animate = false,
    this.searchSegments = const [],
    this.researchPhase,
    this.researchPhaseStartedAt,
  });

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
              researchPhase: researchPhase,
              researchPhaseStartedAt: researchPhaseStartedAt,
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
      duration: const Duration(milliseconds: 280),
      vsync: this,
      value: widget.animate ? 0.0 : 1.0,
    );
    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Cubic(0.16, 1.0, 0.3, 1.0),
      ),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.animate || animationsDisabled(context)) {
      _controller.value = 1.0;
    } else if (_controller.value == 0.0 && !_controller.isAnimating) {
      _controller.forward();
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
  final ResearchPhase? researchPhase;
  final DateTime? researchPhaseStartedAt;

  const _AssistantBubble({
    required this.message,
    required this.isStreaming,
    required this.buildMarkdown,
    this.searchSegments = const [],
    this.researchPhase,
    this.researchPhaseStartedAt,
  });

  @override
  State<_AssistantBubble> createState() => _AssistantBubbleState();
}

class _AssistantBubbleState extends State<_AssistantBubble>
    with TickerProviderStateMixin {
  bool _wasStreaming = false;

  // ── Rejected-draft fade-out ──
  // The completeness gate can reject a draft mid-run: the live message's
  // content is cleared and the loop goes back to searching. Cutting the
  // paragraph out between two frames reads as a rendering glitch, so the
  // text it removed is held here and played out.
  String? _fadingDraft;
  AnimationController? _draftFade;
  Animation<double>? _draftOpacity;
  Animation<double>? _draftSize;

  // ── Typewriter reveal state ──
  String _targetContent = '';
  String _targetThinking = '';
  int _revealedLength = 0;
  int _revealedThinkingLength = 0;
  Ticker? _revealTicker;
  bool _animationsDisabled = false;
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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsDisabled = animationsDisabled(context);
    if (_animationsDisabled) {
      _dropDraftFade();
      _settleReveal();
    } else if (widget.isStreaming) {
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
      // The draft the gate just threw away, if it did: the message object is
      // mutated in place, so old.message.content is the same string as the
      // new one — the state's own previous target is the only record of what
      // was on screen a frame ago.
      if (_targetContent.isNotEmpty && widget.message.content.isEmpty) {
        _beginDraftFade(_targetContent.substring(
            0, surrogateSafeLength(_targetContent, _revealedLength)));
      }
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
    if (_animationsDisabled) {
      _settleReveal();
      return;
    }
    _revealTicker ??= createTicker(_onRevealTick);
    if (!_revealTicker!.isActive) {
      _revealTicker!.start();
    }
  }

  void _stopRevealTicker() {
    _revealTicker?.stop();
  }

  void _settleReveal() {
    _targetContent = widget.message.content;
    _targetThinking = _displayThinking(widget.message.thinking);
    _revealedLength = _targetContent.length;
    _revealedThinkingLength = _targetThinking.length;
    _revealProgress = _revealedLength.toDouble();
    _thinkingRevealProgress = _revealedThinkingLength.toDouble();
    _stopRevealTicker();
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

  /// Holds [text] on screen and plays it out: 220 ms of fade over 300 ms of
  /// collapse, both off one controller so the height finishes settling just
  /// after the words have gone. Under reduced motion the draft is dropped on
  /// the spot instead.
  void _beginDraftFade(String text) {
    if (text.isEmpty || _animationsDisabled) {
      _dropDraftFade();
      return;
    }
    const total = Duration(milliseconds: 300);
    final controller = _draftFade ??= AnimationController(
      vsync: this,
      duration: total,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _fadingDraft = null);
        }
      });
    _draftOpacity ??= Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: controller,
        // 220 ms of the 300 ms timeline.
        curve: const Interval(0.0, 220 / 300, curve: Curves.easeOut),
      ),
    );
    _draftSize ??= Tween<double>(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
    _fadingDraft = text;
    controller.forward(from: 0.0);
  }

  void _dropDraftFade() {
    _fadingDraft = null;
    _draftFade?.stop();
  }

  Widget _buildFadingDraft(BuildContext context) {
    final draft = _fadingDraft;
    final opacity = _draftOpacity;
    final size = _draftSize;
    if (draft == null || opacity == null || size == null) {
      return const SizedBox.shrink();
    }
    return FadeTransition(
      opacity: opacity,
      child: SizeTransition(
        sizeFactor: size,
        axisAlignment: -1,
        child: widget.buildMarkdown(context, draft),
      ),
    );
  }

  @override
  void dispose() {
    _revealTicker?.dispose();
    _draftFade?.dispose();
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
          // What the research loop is busy with, between the content and the
          // llama: the llama says "still going", the strip says what for.
          // `done` fires while the answer is still streaming out, and a pill
          // reading "Done" over a live stream would contradict it.
          if (widget.isStreaming &&
              widget.researchPhase != null &&
              widget.researchPhase != ResearchPhase.done)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ResearchActivityStrip(
                phase: widget.researchPhase!,
                startedAt: widget.researchPhaseStartedAt,
              ),
            ),
          // Llama on its own line: running during streaming, resting after
          if (widget.isStreaming || _wasStreaming)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: StreamingLlama(isRunning: widget.isStreaming),
            ),
          // Smoothly reveal action buttons when streaming ends
          AnimatedSize(
            duration: motionDuration(
              context,
              const Duration(milliseconds: 300),
            ),
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
          // A LIVE segment with no text yet is still rendered: that empty
          // moment is precisely when the "Thinking..." header has to be on
          // screen. Only a finished segment with nothing in it is dropped.
          if (segment.isComplete && segment.text.isEmpty) continue;
          widgets.add(ThinkBlockWidget(
            // Keyed on the segment instance so the one live block keeps its
            // element — and with it its stopwatch, pulse and collapse
            // animation — when the view model completes it in place.
            key: ObjectKey(segment),
            content: segment.text,
            isComplete: segment.isComplete,
            isStreaming: !segment.isComplete,
            elapsedSeconds: segment.elapsedSeconds,
          ));
        case SearchCardSegment():
          widgets.add(SearchCard(segment: segment));
        case ResearchLedgerSegment():
          widgets.add(_ResearchLedgerPanel(segment: segment));
        case ClarificationSegment():
          // Only a live, streaming bubble has a paused run to resume; a
          // saved message renders the card as the record it is.
          final viewModel = widget.isStreaming
              ? context.read<ChatPageViewModel?>()
              : null;
          widgets.add(ClarificationCard(
            segment: segment,
            onAnswer: viewModel == null
                ? null
                : (selected) =>
                    viewModel.answerClarification(segment, selected),
          ));
        case AnswerSegment():
          break;
      }
    }
    return widgets;
  }

  Widget _buildMessageContent(BuildContext context) {
    final content = _isRevealing
        ? _ChatBubbleBody._hideIncompleteLinks(
            _targetContent.substring(
                0, surrogateSafeLength(_targetContent, _revealedLength)))
        : widget.message.content;

    final segments = _getSearchSegments();
    final searchWidgets = _buildSearchSegmentsFrom(segments);

    final displayThinking = _displayThinking(widget.message.thinking);
    if (displayThinking.isNotEmpty) {
      final thinkingContent = _isRevealing
          ? _targetThinking.substring(
              0, surrogateSafeLength(_targetThinking, _revealedThinkingLength))
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
          if (_fadingDraft != null) _buildFadingDraft(context),
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
          if (_fadingDraft != null) _buildFadingDraft(context),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildModelLabel(context),
        ...searchWidgets,
        if (content.isNotEmpty) widget.buildMarkdown(context, content),
        if (_fadingDraft != null) _buildFadingDraft(context),
      ],
    );
  }
}

/// Collapsible panel rendering a [ResearchLedgerSegment]: the run's
/// objective, which sub-goals have been searched vs are still open (each
/// with its source-id chip, when searched), and — once the run has
/// stopped — why. Mirrors [SearchCard]'s header/expand idiom (an InkWell
/// header, `AnimatedRotation` chevron) rather than a new visual language;
/// uses `AnimatedSize` for the body instead of SearchCard's dedicated
/// AnimationController since there's no entrance-animation need here (the
/// segment is overwritten in place, never freshly appended mid-stream the
/// way a search card is).
class _ResearchLedgerPanel extends StatefulWidget {
  final ResearchLedgerSegment segment;

  const _ResearchLedgerPanel({required this.segment});

  @override
  State<_ResearchLedgerPanel> createState() => _ResearchLedgerPanelState();
}

class _ResearchLedgerPanelState extends State<_ResearchLedgerPanel> {
  bool _expanded = true;

  /// Queries this panel has already shown as searched. A row is only worth
  /// animating in the frame it *becomes* a finding; every later rebuild
  /// (a sharper objective, another card landing, a collapse) would
  /// otherwise replay the entrance of rows that have been sitting there
  /// for rounds. Seeded in [initState] so a message decoded from history
  /// renders its findings settled rather than animating the whole ledger
  /// on scroll.
  final Set<String> _seenSearched = <String>{};
  bool _seenSyncScheduled = false;

  @override
  void initState() {
    super.initState();
    _rememberSearched();
  }

  void _rememberSearched() {
    for (final entry in widget.segment.entries) {
      if (entry.searched) _seenSearched.add(entry.query);
    }
  }

  /// Folds this frame's findings into [_seenSearched] once it is on screen.
  /// Deliberately not a `setState`: the set only changes what the *next*
  /// build treats as new, and rebuilding here would cut the very entrance
  /// this frame just started.
  void _scheduleSeenSync() {
    if (_seenSyncScheduled) return;
    _seenSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _seenSyncScheduled = false;
      if (!mounted) return;
      _rememberSearched();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segment = widget.segment;
    final searched = segment.entries.where((e) => e.searched).toList();
    final open = segment.entries.where((e) => !e.searched).toList();
    _scheduleSeenSync();

    // A finished run that never opened a single sub-goal did no research at
    // all — the model answered straight from the chat. The panel exists to
    // frame research; with nothing to frame it is just a heading, so it
    // stays out of the way. Mid-run it still shows (entries are empty until
    // the first round lands), because that is exactly when the reader most
    // needs to see what the run is going after.
    if (segment.entries.isEmpty && segment.terminationReason != null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.flag_outlined,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Research goal',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _expanded ? 0.0 : -0.25,
                      duration: motionDuration(
                        context,
                        const Duration(milliseconds: 200),
                      ),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Not wrapped in AnimatedSize under reduced motion: a
            // zero-duration AnimatedSize whose child changes size (a
            // sub-goal landing, the panel collapsing) re-dirties itself
            // from inside its own performLayout, which is a framework
            // assertion, and the widget has nothing left to do here anyway.
            if (animationsDisabled(context))
              _ledgerBody(segment, searched, open)
            else
              AnimatedSize(
                duration:
                    motionDuration(context, const Duration(milliseconds: 200)),
                curve: Curves.easeInOut,
                alignment: Alignment.topLeft,
                child: _ledgerBody(segment, searched, open),
              ),
          ],
        ),
      ),
    );
  }

  Widget _ledgerBody(
    ResearchLedgerSegment segment,
    List<LedgerEntryView> searched,
    List<LedgerEntryView> open,
  ) {
    if (!_expanded) return const SizedBox(width: double.infinity, height: 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 0, 12, 10),
      child: _LedgerBody(
        segment: segment,
        searched: searched,
        open: open,
        seenSearched: _seenSearched,
      ),
    );
  }
}

class _LedgerBody extends StatelessWidget {
  final ResearchLedgerSegment segment;
  final List<LedgerEntryView> searched;
  final List<LedgerEntryView> open;

  /// Queries the panel has already shown as searched — see
  /// `_ResearchLedgerPanelState._seenSearched`. Anything searched and NOT
  /// in here became a finding on this very frame, and is worth an entrance.
  final Set<String> seenSearched;

  const _LedgerBody({
    required this.segment,
    required this.searched,
    required this.open,
    required this.seenSearched,
  });

  /// The line under the checklist: why the run stopped, or what it is
  /// about to do. Both live in one `AnimatedSwitcher` keyed by this
  /// string, so "researching X" → "drafting the answer" → the termination
  /// banner reads as one line changing its mind rather than three
  /// different lines cutting over each other.
  String _footerKey() {
    if (segment.terminationReason != null) {
      return 'termination:${segment.terminationReason}:'
          '${searched.fold<int>(0, (sum, entry) => sum + entry.ranges.length)}';
    }
    return _nextStepText();
  }

  String _nextStepText() {
    // Derivation is a silent model call that can take seconds; without
    // this the panel claims it is about to draft an answer it has not
    // even framed a goal for yet.
    if (segment.isDeriving) return 'Framing the research goal…';
    if (open.isEmpty) return 'Next — drafting the answer';
    return 'Next — researching "${open.first.query}"';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = animationsDisabled(context);

    final objective = Text(
      segment.objective,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
      // Three, not two: a derived goal is one line, but the fallback
      // when derivation fails is the user's raw message, and clipping
      // that mid-clause is how this line stopped reading as a goal.
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (segment.objective.isNotEmpty)
          AnimatedSwitcher(
            duration: motionDuration(context, const Duration(milliseconds: 260)),
            layoutBuilder: _leftAlignedSwitcherLayout,
            // Keyed by the text: the provisional objective (the user's raw
            // question) crosses over to the derived goal instead of being
            // swapped out from under the reader mid-sentence.
            child: KeyedSubtree(
              key: ValueKey<String>(segment.objective),
              child: segment.isDeriving && !disabled
                  ? Shimmer.fromColors(
                      baseColor: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.45),
                      highlightColor:
                          theme.colorScheme.onSurface.withValues(alpha: 0.95),
                      period: const Duration(milliseconds: 1400),
                      child: objective,
                    )
                  : objective,
            ),
          ),
        if (searched.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SectionLabel('Findings'),
          for (final entry in searched)
            _LedgerEntryRow(
              entry: entry,
              searched: true,
              animateIn: !seenSearched.contains(entry.query),
            ),
        ],
        if (open.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SectionLabel('Still open'),
          for (final entry in open)
            _LedgerEntryRow(entry: entry, searched: false, animateIn: false),
        ],
        const SizedBox(height: 10),
        AnimatedSwitcher(
          duration: motionDuration(context, const Duration(milliseconds: 240)),
          layoutBuilder: _leftAlignedSwitcherLayout,
          child: KeyedSubtree(
            key: ValueKey<String>(_footerKey()),
            child: segment.terminationReason != null
                ? _TerminationBanner(
                    reason: segment.terminationReason!,
                    // Searches, not sub-goals: one sub-goal can be searched
                    // more than once, and counting entries under-reported a
                    // run by exactly the searches this panel had already
                    // failed to show.
                    searchedCount: searched.fold<int>(
                        0, (sum, entry) => sum + entry.ranges.length),
                  )
                : _NextStepLine(text: _nextStepText()),
          ),
        ),
      ],
    );
  }
}

/// `AnimatedSwitcher`'s default stacks its children centred, which shunts a
/// cross-fading line to the middle of the panel for the length of the
/// transition. These lines are left-aligned prose; keep them there.
Widget _leftAlignedSwitcherLayout(
  Widget? currentChild,
  List<Widget> previousChildren,
) {
  return Stack(
    alignment: Alignment.centerLeft,
    children: <Widget>[
      ...previousChildren,
      if (currentChild != null) currentChild,
    ],
  );
}

/// What the run is about to do, shown while it is still going — the live
/// counterpart to [_TerminationBanner], which replaces it once the run
/// stops. Named off the ledger's own state rather than any prediction: the
/// harness tells the model, every round, to close a still-open item next,
/// so the first one is what it has asked for — not a guess about what the
/// model will choose.
class _NextStepLine extends StatelessWidget {
  /// Already resolved by [_LedgerBody], which also keys the cross-fade on
  /// it — the line and the key have to be the same string or a change
  /// would swap the text without a transition.
  final String text;

  const _NextStepLine({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.arrow_forward,
            size: 14,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

/// One sub-goal row: a source-id chip (searched entries) or a plain bullet
/// (still-open entries) plus the query text.
///
/// Stateful for one reason: the moment a sub-goal turns into a finding is
/// the only progress this panel ever shows, and it used to be a cut. The
/// leading glyph transitions bullet → chip through an `AnimatedSwitcher`,
/// and a row that has just crossed over ([animateIn]) fades in behind it —
/// the row keeps its element across the move from "Still open" to
/// "Findings", so the glyph switcher is the same one, not a fresh widget
/// starting settled.
class _LedgerEntryRow extends StatefulWidget {
  final LedgerEntryView entry;
  final bool searched;

  /// True only on the frame this row first appears as searched; the panel
  /// State decides, so a rebuild for an unrelated reason (or a message
  /// read back from history) never replays the entrance.
  final bool animateIn;

  const _LedgerEntryRow({
    required this.entry,
    required this.searched,
    required this.animateIn,
  });

  @override
  State<_LedgerEntryRow> createState() => _LedgerEntryRowState();
}

class _LedgerEntryRowState extends State<_LedgerEntryRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: widget.animateIn && widget.searched ? 0.0 : 1.0,
  );
  late final Animation<double> _opacity =
      CurvedAnimation(parent: _fade, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    if (_fade.value == 0.0) _fade.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fade.duration = motionDuration(context, const Duration(milliseconds: 220));
    if (animationsDisabled(context)) _fade.value = 1.0;
  }

  @override
  void didUpdateWidget(_LedgerEntryRow old) {
    super.didUpdateWidget(old);
    // Only the crossing matters. Going the other way (the panel marking the
    // row as already seen) must not restart or rewind an entrance that is
    // mid-flight.
    if (!(old.animateIn && old.searched) && widget.animateIn && widget.searched) {
      if (animationsDisabled(context)) {
        _fade.value = 1.0;
      } else {
        _fade.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // The chip needs ids to show; a searched entry without any still reads
    // as a bullet, so the switcher is keyed on what is actually drawn.
    final showChip = widget.searched && widget.entry.ranges.isNotEmpty;
    return FadeTransition(
      opacity: _opacity,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSwitcher(
              duration:
                  motionDuration(context, const Duration(milliseconds: 280)),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: showChip
                  ? Padding(
                      key: const ValueKey<bool>(true),
                      padding: const EdgeInsets.only(top: 1, right: 6),
                      child: _SourceIdChip(ranges: widget.entry.ranges),
                    )
                  : Padding(
                      key: const ValueKey<bool>(false),
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Icon(Icons.circle,
                          size: 5,
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.5)),
                    ),
            ),
            Expanded(
              child: Text(
                widget.entry.query,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pill showing the source ids backing a searched entry — e.g. "3",
/// "3–5", or "3–5 · 12–16" when the sub-goal was searched more than once.
/// The ranges are listed rather than merged into one span because the ids
/// between them belong to other sub-goals. Never renders the "[a]-[b]"
/// bracket form: that syntax is reserved for citation markers the model
/// reads and the citation parser scans for (see SearchAgent's
/// compaction/ledger text).
class _SourceIdChip extends StatelessWidget {
  final List<SourceIdRange> ranges;

  const _SourceIdChip({required this.ranges});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = ranges
        .map((r) => r.start == r.end ? '${r.start}' : '${r.start}–${r.end}')
        .join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}

/// Banner shown once a research run has stopped, keyed off
/// [SearchTerminationReason.name] (see ResearchLedgerSegment.terminationReason)
/// so the user can tell a converged answer from one cut off by a safety cap.
class _TerminationBanner extends StatelessWidget {
  final String reason;
  final int searchedCount;

  const _TerminationBanner({
    required this.reason,
    required this.searchedCount,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final presentation = _presentation();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(presentation.icon,
            size: 14,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            presentation.text,
            style: TextStyle(
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }

  ({IconData icon, String text}) _presentation() {
    switch (reason) {
      case 'converged':
        // Zero is its own case, not a degenerate plural: "findings gathered
        // across 0 searches" claims research that never happened. The model
        // answered from what it already knew, and saying so is the honest
        // caption for a panel whose checklist is entirely unticked.
        if (searchedCount == 0) {
          return (
            icon: Icons.check_circle_outline,
            text: 'Answered without searching',
          );
        }
        final plural = searchedCount == 1 ? '' : 'es';
        return (
          icon: Icons.check_circle_outline,
          text: 'Research complete — findings gathered across '
              '$searchedCount search$plural',
        );
      case 'hardCapReached':
        return (
          icon: Icons.hourglass_disabled_outlined,
          text: 'Stopped at the search limit',
        );
      case 'roundCapReached':
        return (
          icon: Icons.hourglass_disabled_outlined,
          text: 'Stopped at the round limit',
        );
      case 'unproductiveRounds':
        return (
          icon: Icons.info_outline,
          text: 'Stopped early — no new information in recent searches',
        );
      case 'searchUnavailable':
        // Deliberately distinct from every other stop: the run ended
        // because searching was impossible, not because an answer was
        // reached or a budget ran out. Reading this as "research complete"
        // would badly overstate what the answer below is based on.
        return (
          icon: Icons.cloud_off_outlined,
          text: 'Stopped — the search engine is rate-limiting requests; '
              'the answer may be incomplete',
        );
      case 'stalled':
        // Deliberately not "Cancelled", even though the outcome carries the
        // same cancelled flag: the user did not stop this run, the model
        // stopped answering. Telling them they cancelled something they
        // never touched is worse than saying nothing.
        return (
          icon: Icons.cloud_off_outlined,
          text: 'Stopped — the model stopped responding; the answer may be '
              'incomplete',
        );
      case 'cancelled':
        return (icon: Icons.cancel_outlined, text: 'Cancelled');
      default:
        return (icon: Icons.info_outline, text: 'Stopped');
    }
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

class _CopyChipState extends State<_CopyChip> {
  bool _copied = false;
  Timer? _copyFeedbackTimer;

  void _handleTap() {
    widget.onCopy();
    _copyFeedbackTimer?.cancel();
    setState(() => _copied = true);
    _copyFeedbackTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _copyFeedbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = _copied ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return AnimatedSwitcher(
      duration: motionDuration(
        context,
        const Duration(milliseconds: 200),
      ),
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
    transitionDuration: motionDuration(
      context,
      const Duration(milliseconds: 400),
    ),
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
  bool _animationsDisabled = false;

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsDisabled = animationsDisabled(context);
    if (_animationsDisabled) {
      _controller.value = 1.0;
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
    if (_animationsDisabled) {
      _controller.value = 1.0;
    } else {
      _controller.forward();
    }
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
          key: const ValueKey('link-favicon-fade'),
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
