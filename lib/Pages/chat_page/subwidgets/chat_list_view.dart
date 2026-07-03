import 'package:flutter/material.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:shimmer/shimmer.dart';
import 'package:notification_centre/notification_centre.dart';

import 'package:llamaseek/Models/search_event.dart';

import 'chat_bubble/chat_bubble.dart';
import 'package:llamaseek/Constants/constants.dart';
import 'package:llamaseek/Utils/observe_size.dart';
import 'package:llamaseek/Utils/retained_position_scroll_physics.dart';

class ChatListView extends StatefulWidget {
  final List<OllamaMessage> messages;
  final bool isAwaitingReply;
  final bool isStreaming;
  final Widget? error;
  final double? bottomPadding;
  final double? topPadding;
  final List<MessageSegment> searchSegments;
  final bool composerExpanded;

  const ChatListView({
    super.key,
    required this.messages,
    required this.isAwaitingReply,
    this.isStreaming = false,
    this.error,
    this.bottomPadding,
    this.topPadding,
    this.searchSegments = const [],
    this.composerExpanded = false,
  });

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  final ScrollController _scrollController = ScrollController();
  bool _isScrollToBottomButtonVisible = false;

  final _messageSizeProxy = WidgetSizeProxy();

  /// Cached bubble widgets keyed by message ID. Returning the exact same
  /// Widget reference lets Flutter skip the entire subtree rebuild,
  /// avoiding expensive markdown re-parsing during streaming updates.
  final Map<String, Widget> _bubbleCache = {};
  final Set<String> _animatedMessageIds = {};

  /// Test seam: the message IDs currently held in [_bubbleCache]. Used to
  /// assert that stale cache entries are pruned after an in-place message
  /// list mutation (regenerate/delete), which has no observable effect on
  /// the rendered widget tree and so cannot be verified any other way.
  @visibleForTesting
  Set<String> get debugCachedBubbleIds => _bubbleCache.keys.toSet();

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(() {
      _updateScrollToBottomButtonVisibility();
    });

    NotificationCenter().addObserver(
      NotificationNames.generationBegin,
      this,
      (n) => Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _scrollToBottom();
      }),
    );
  }

  @override
  void didUpdateWidget(covariant ChatListView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Clear bubble cache when switching chats (message list replaced entirely)
    if (!identical(widget.messages, oldWidget.messages)) {
      _bubbleCache.clear();
      _animatedMessageIds.clear();
    } else {
      // Same list object, mutated in place (e.g. regenerate/delete remove a
      // range of messages to preserve list identity). putIfAbsent only ever
      // adds, so entries for removed messages would leak until the next chat
      // switch — prune them down to the messages still present.
      _pruneStaleCacheEntries();
    }

    // Add to the post frame callback to ensure that the scroll offset is
    // read after the widget has been updated.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Update the button visibility when the user switches chats,
      // regenerates a message or delete a message.
      _updateScrollToBottomButtonVisibility();
    });
  }

  /// Drops cached bubble widgets (and animation bookkeeping) for messages that
  /// are no longer present in [widget.messages]. Called when the list object is
  /// mutated in place, where the identity check in [didUpdateWidget] cannot tell
  /// that entries have been removed.
  void _pruneStaleCacheEntries() {
    final currentIds = widget.messages.map((m) => m.id).toSet();
    _bubbleCache.removeWhere((id, _) => !currentIds.contains(id));
    _animatedMessageIds.removeWhere((id) => !currentIds.contains(id));
  }

  @override
  void dispose() {
    _scrollController.dispose();

    // Remove the observer for the generation begin notification
    NotificationCenter().removeObserver(NotificationNames.generationBegin, this);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hide the scroll-to-bottom button whenever the composer is expanded — it
    // grows upward over the button's fixed offset and would otherwise cover it.
    // Covers both the keyboard-up case and an expanded draft kept open with the
    // keyboard dismissed (e.g. a pending draft while a reply streams).
    final showScrollButton = _isScrollToBottomButtonVisible &&
        MediaQuery.of(context).viewInsets.bottom == 0 &&
        !widget.composerExpanded;
    return Stack(
      children: [
        // Fade the conversation out at its bottom so it dissolves into the
        // animated gradient behind it. The scroll-to-bottom button is a sibling
        // in this Stack (below), so it is NOT affected by this mask.
        ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, 0.9, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          // SelectionArea enables native iOS long-press selection across
          // bubbles without intercepting vertical scroll.
          child: SelectionArea(
            child: CustomScrollView(
          controller: _scrollController,
          reverse: true,
          physics: RetainedPositionScrollPhysics(
            widgetSizeProxy: _messageSizeProxy,
          ),
          slivers: [
            if (widget.bottomPadding != null)
              SliverPadding(
                padding: EdgeInsets.only(bottom: widget.bottomPadding!),
              ),
            if (widget.error != null)
              SliverToBoxAdapter(
                child: widget.error,
              ),
            if (widget.isAwaitingReply)
              SliverToBoxAdapter(
                child: _buildSkeletonLoader(context),
              ),
            SliverList.builder(
              key: widget.key,
              itemCount: widget.messages.length,
              itemBuilder: (context, index) {
                final message = widget.messages[widget.messages.length - index - 1];
                final isStreamingMessage = index == 0 && widget.isStreaming;

                if (index == 0) {
                  // Mark every index-0 user message as "seen" so its entrance
                  // animation plays at most once, on genuine first appearance.
                  // Recording the id even when we don't animate (a freshly sent
                  // message first paints while isStreaming is already true)
                  // prevents a stale pop later: on regenerate the prior user
                  // message transiently becomes the last, non-streaming bubble
                  // and would otherwise animate as if just sent.
                  final firstAppearance = message.role == OllamaMessageRole.user &&
                      _animatedMessageIds.add(message.id);
                  final shouldAnimate = firstAppearance && !isStreamingMessage;

                  return ObserveSize(
                    key: Key(message.id),
                    onSizeChanged: _onMessageSizeChanged,
                    child: RepaintBoundary(
                      child: ChatBubble(
                        message: message,
                        isStreaming: isStreamingMessage,
                        animate: shouldAnimate,
                        searchSegments: widget.searchSegments,
                      ),
                    ),
                  );
                }

                // Cached widget reference — Flutter skips the entire subtree
                // rebuild when the same Widget instance is returned, avoiding
                // expensive markdown re-parsing during streaming updates.
                return _bubbleCache.putIfAbsent(
                  message.id,
                  () => RepaintBoundary(
                    child: ChatBubble(message: message),
                  ),
                );
              },
            ),
            // Top padding for glass AppBar overlap (end of reversed list = visual top)
            if (widget.topPadding != null && widget.topPadding! > 0)
              SliverToBoxAdapter(
                child: SizedBox(height: widget.topPadding!),
              ),
          ],
        ),
        ),
        ),
        Positioned(
          right: 16,
          bottom: _scrollToBottomButtonBottomOffset(),
          child: AnimatedScale(
            scale: showScrollButton ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            curve: _isScrollToBottomButtonVisible ? Curves.easeOutBack : Curves.easeIn,
            child: AnimatedOpacity(
              opacity: showScrollButton ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !showScrollButton,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.78),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: IconButton(
                    onPressed: _scrollToBottom,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                    tooltip: 'Scroll to latest',
                    style: IconButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.82),
                      minimumSize: const Size(40, 40),
                      maximumSize: const Size(40, 40),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Skeleton loading indicator with animated text placeholder lines.
  Widget _buildSkeletonLoader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      child: Shimmer.fromColors(
        baseColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
        highlightColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.14),
        period: const Duration(milliseconds: 1500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _skeletonLine(width: 220),
            const SizedBox(height: 10),
            _skeletonLine(width: 180),
            const SizedBox(height: 10),
            _skeletonLine(width: 140),
          ],
        ),
      ),
    );
  }

  Widget _skeletonLine({required double width}) {
    return Container(
      width: width,
      height: 12,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
      ),
    );
  }

  void _onMessageSizeChanged(Size? previousSize, Size currentSize) {
    final currentHeight = currentSize.height;
    final previousHeight = (previousSize ?? currentSize).height;
    _messageSizeProxy.deltaHeight = currentHeight - previousHeight;
  }

  void _updateScrollToBottomButtonVisibility() {
    if (_scrollController.position.pixels > 100 && !_isScrollToBottomButtonVisible) {
      setState(() {
        _isScrollToBottomButtonVisible = true;
      });
    }

    if (_scrollController.position.pixels < 100 && _isScrollToBottomButtonVisible) {
      setState(() {
        _isScrollToBottomButtonVisible = false;
      });
    }
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  double _scrollToBottomButtonBottomOffset() {
    final overlayHeight = widget.bottomPadding ?? 0;
    return overlayHeight > 0 ? overlayHeight + 12 : 16;
  }
}
