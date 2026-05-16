import 'package:flutter/material.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:shimmer/shimmer.dart';
import 'package:notification_centre/notification_centre.dart';

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

  const ChatListView({
    super.key,
    required this.messages,
    required this.isAwaitingReply,
    this.isStreaming = false,
    this.error,
    this.bottomPadding,
  });

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  final ScrollController _scrollController = ScrollController();
  bool _isScrollToBottomButtonVisible = false;

  final _messageSizeProxy = WidgetSizeProxy();

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(() {
      _updateScrollToBottomButtonVisibility();
    });

    NotificationCenter().addObserver(
      NotificationNames.generationBegin,
      this,
      (n) => _scrollToBottom(),
    );
  }

  @override
  void didUpdateWidget(covariant ChatListView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Add to the post frame callback to ensure that the scroll offset is
    // read after the widget has been updated.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Update the button visibility when the user switches chats,
      // regenerates a message or delete a message.
      _updateScrollToBottomButtonVisibility();
    });
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
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        CustomScrollView(
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
                  return ObserveSize(
                    key: Key(message.id),
                    onSizeChanged: _onMessageSizeChanged,
                    child: ChatBubble(
                      message: message,
                      isStreaming: isStreamingMessage,
                    ),
                  );
                }

                return ChatBubble(message: message);
              },
            ),
          ],
        ),
        if (_isScrollToBottomButtonVisible)
          Padding(
            padding: const EdgeInsets.only(bottom: 76),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).shadowColor.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton.filled(
                onPressed: _scrollToBottom,
                icon: const Icon(Icons.keyboard_arrow_down, size: 22),
                style: IconButton.styleFrom(
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHigh,
                  foregroundColor:
                      Theme.of(context).colorScheme.onSurface,
                  minimumSize: const Size(40, 40),
                  maximumSize: const Size(40, 40),
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
        baseColor:
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
        highlightColor:
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.14),
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
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }
}
