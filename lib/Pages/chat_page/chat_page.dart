import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';

import 'package:llamaseek/Widgets/chat_app_bar.dart';
import 'package:llamaseek/Widgets/memory_status_indicator.dart';
import 'package:llamaseek/Widgets/model_selection_bottom_sheet.dart';

import 'chat_page_view_model.dart';
import 'subwidgets/subwidgets.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with SingleTickerProviderStateMixin {
  static const double _composerHorizontalInset = 6.0;
  static const double _footerSpacing = 12.0;
  static const double _collapsedComposerPadding = 56.0;
  static const double _expandedComposerPadding = 86.0;

  // Incognito mode transition
  static const _transitionDuration = Duration(milliseconds: 400);
  static const _transitionCurve = Curves.easeInOutCubic;

  // ViewModel reference
  late final ChatPageViewModel _viewModel;

  // Search button pulse animation
  late final AnimationController _searchPulseController;

  // Welcome screen animation state
  var _crossFadeState = CrossFadeState.showFirst;
  double _scale = 1.0;

  // Input bar expansion state
  final _inputFocusNode = FocusNode();
  bool _isInputExpanded = false;

  bool get _shouldShowExpanded => _isInputExpanded;

  @override
  void initState() {
    super.initState();
    _viewModel = context.read<ChatPageViewModel>();
    _inputFocusNode.addListener(_onInputFocusChange);
    _searchPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _searchPulseController.dispose();
    _inputFocusNode.removeListener(_onInputFocusChange);
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _onInputFocusChange() {
    if (!_inputFocusNode.hasFocus && _viewModel.textFieldController.text.isEmpty && !_viewModel.isStreaming) {
      setState(() => _isInputExpanded = false);
    }
  }

  void _expandInput() {
    setState(() => _isInputExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inputFocusNode.requestFocus();
    });
  }

  bool get _isIncognito =>
      _viewModel.currentChat?.isIncognito == true || _viewModel.incognitoRequested;

  // Incognito palette
  static const _incognitoBg = Color(0xFF0D0D1A);
  static const _incognitoSurface = Color(0xFF16162A);
  static const _incognitoAccent = Color(0xFF6C63FF);
  static const _incognitoBorder = Color(0xFF2A2A4A);
  static const _incognitoText = Color(0xFF9898B0);

  @override
  Widget build(BuildContext context) {
    // Subscribe to ViewModel changes
    context.watch<ChatPageViewModel>();

    // Drive the search-button pulse animation
    final shouldPulse = _viewModel.webSearchEnabled &&
        (_viewModel.isStreaming || _viewModel.isSearching);
    if (shouldPulse && !_searchPulseController.isAnimating) {
      _searchPulseController.repeat(reverse: true);
    } else if (!shouldPulse && _searchPulseController.isAnimating) {
      _searchPulseController.stop();
      _searchPulseController.value = 0.0;
    }

    final isIncognito = _isIncognito;

    Widget body = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (!ResponsiveBreakpoints.of(context).isMobile) ChatAppBar(),
        Expanded(
          child: Stack(
            children: [
              _buildChatBody(),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomOverlay(),
              ),
              // Incognito badge (animated)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: isIncognito ? 1.0 : 0.0,
                    duration: _transitionDuration,
                    curve: _transitionCurve,
                    child: AnimatedSlide(
                      offset: isIncognito ? Offset.zero : const Offset(0, -0.5),
                      duration: _transitionDuration,
                      curve: Curves.easeOutCubic,
                      child: IgnorePointer(
                        ignoring: !isIncognito,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: _incognitoSurface.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _incognitoAccent.withValues(alpha: 0.15),
                              width: 0.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _incognitoAccent.withValues(alpha: 0.08),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.visibility_off_outlined, size: 13, color: _incognitoAccent.withValues(alpha: 0.7)),
                              const SizedBox(width: 6),
                              Text(
                                'Incognito',
                                style: TextStyle(
                                  color: _incognitoText,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.8,
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
            ],
          ),
        ),
      ],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // Incognito gradient background (animated)
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: isIncognito ? 1.0 : 0.0,
            duration: _transitionDuration,
            curve: _transitionCurve,
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.0, -0.4),
                  radius: 1.2,
                  colors: [
                    Color(0xFF141428),
                    _incognitoBg,
                  ],
                ),
              ),
            ),
          ),
        ),
        body,
      ],
    );
  }

  Widget _buildChatBody() {
    if (_viewModel.messages.isEmpty) {
      if (_viewModel.currentChat == null) {
        if (!_viewModel.isServerConfigured) {
          return ChatEmpty(
            child: ChatWelcome(
              showingState: _crossFadeState,
              onFirstChildFinished: () => setState(() => _crossFadeState = CrossFadeState.showSecond),
              secondChildScale: _scale,
              onSecondChildScaleEnd: () => setState(() => _scale = 1.0),
            ),
          );
        } else if (_isIncognito) {
          return ChatEmpty(
            child: _buildIncognitoWelcome(),
          );
        } else {
          return ChatEmpty(
            child: ChatSelectModelButton(
              currentModelName: _viewModel.selectedModel?.name,
              onPressed: _showModelSelectionBottomSheet,
            ),
          );
        }
      } else if (_isIncognito && _viewModel.messages.isEmpty) {
        return ChatEmpty(
          child: _buildIncognitoWelcome(),
        );
      } else {
        return ChatEmpty(
          child: Text('No messages yet!'),
        );
      }
    } else {
      final isMobile = ResponsiveBreakpoints.of(context).isMobile;
      return ChatListView(
        key: PageStorageKey<String>(_viewModel.currentChat?.id ?? 'empty'),
        messages: _viewModel.messages,
        isAwaitingReply: _viewModel.isThinking && _viewModel.searchSegments.isEmpty,
        isStreaming: _viewModel.isStreaming,
        searchSegments: _viewModel.searchSegments,
        error: _viewModel.currentError != null
            ? ChatError(
                message: _viewModel.currentError!.message,
                onRetry: () => _viewModel.retryLastPrompt(),
              )
            : null,
        bottomPadding: _chatBodyBottomPadding(context),
        topPadding: isMobile ? MediaQuery.of(context).padding.top + ChatAppBar.mobileOverlayHeight : null,
      );
    }
  }

  Widget _buildBottomOverlay() {
    final footer = _buildChatFooter();
    // Use theme surface — AnimatedTheme interpolates this in sync with
    // the gradient overlay, so the bottom area transitions at the same
    // rate as the main content area.
    final bgColor = Theme.of(context).colorScheme.surface;
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Composer — transparent so the full-screen incognito gradient
        // overlay (behind this Stack layer) shows through, keeping the
        // transition in sync with the area above.
        Padding(
          padding: EdgeInsets.only(
            left: _composerHorizontalInset,
            right: _composerHorizontalInset,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (footer != null) ...[
                footer,
                const SizedBox(height: _footerSpacing),
              ],
              _buildComposer(),
            ],
          ),
        ),
        // Gradient fade below the input bar — content fades out in safe area
        if (bottomSafeArea > 0)
          IgnorePointer(
            child: Container(
              height: bottomSafeArea,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    bgColor.withValues(alpha: 0.5),
                    bgColor,
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildComposer() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24.0),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            // Use theme colors so AnimatedTheme drives the transition
            // at the same rate as the gradient overlay behind.
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(24.0),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRect(
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.bottomCenter,
                  heightFactor: _shouldShowExpanded ? 1.0 : 0.0,
                  child: AnimatedOpacity(
                    opacity: _shouldShowExpanded ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeIn,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: ChatTextField(
                        key: ValueKey(_viewModel.currentChat?.id),
                        controller: _viewModel.textFieldController,
                        onEditingComplete: _sendMessage,
                        focusNode: _inputFocusNode,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6, top: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.add, size: 20, color: _isIncognito ? _incognitoText : null),
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                      onPressed: _handleAttachmentButton,
                    ),
                    const SizedBox(width: 2),
                    AnimatedBuilder(
                      animation: _searchPulseController,
                      builder: (context, child) {
                        final isActive = _viewModel.webSearchEnabled &&
                            (_viewModel.isStreaming || _viewModel.isSearching);
                        return Opacity(
                          opacity: isActive
                              ? 0.3 + 0.7 * (1.0 - _searchPulseController.value)
                              : 1.0,
                          child: child,
                        );
                      },
                      child: IconButton(
                        icon: Icon(
                          _viewModel.webSearchEnabled ? Icons.travel_explore : Icons.travel_explore_outlined,
                          size: 20,
                          color: _viewModel.webSearchEnabled
                              ? Theme.of(context).colorScheme.onPrimary
                              : (_isIncognito ? _incognitoText : null),
                        ),
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(),
                        style: _viewModel.webSearchEnabled
                            ? IconButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        onPressed: (_viewModel.isStreaming || _viewModel.isSearching) ? null : () {
                          final needsConsent = _viewModel.toggleWebSearch();
                          if (needsConsent) {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Web Search'),
                                content: const Text(
                                  'When enabled, your search queries will be sent to DuckDuckGo (duckduckgo.com) to retrieve web results. Web page content may also be fetched to provide context for AI responses.\n\nNo data is collected by DriftPaca.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () {
                                      _viewModel.acceptWebSearchConsent();
                                      Navigator.pop(ctx);
                                    },
                                    child: const Text('Enable'),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                        tooltip: 'Web Search',
                      ),
                    ),
                    Expanded(
                      child: IgnorePointer(
                        ignoring: _shouldShowExpanded,
                        child: GestureDetector(
                          onTap: _expandInput,
                          behavior: HitTestBehavior.opaque,
                          child: AnimatedOpacity(
                            opacity: _shouldShowExpanded ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 300),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Text(
                                'Message',
                                style: TextStyle(
                                  color: _isIncognito
                                      ? _incognitoText.withValues(alpha: 0.4)
                                      : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_viewModel.isStreaming || _viewModel.isSearching)
                      IconButton(
                        icon: const Icon(Icons.stop_rounded, size: 20),
                        padding: const EdgeInsets.all(6),
                        constraints: const BoxConstraints(),
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.errorContainer,
                          foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        onPressed: _viewModel.cancelStreaming,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncognitoWelcome() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.visibility_off_outlined,
          size: 48,
          color: _incognitoAccent.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),
        Text(
          'Incognito Mode',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: _incognitoText,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Your profile is unknown in this mode.\n'
            'Conversations won\'t be used to build your memory.\n'
            'Agent memory is not available here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: _incognitoText.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: _showModelSelectionBottomSheet,
          icon: Icon(Icons.auto_awesome_outlined, size: 16, color: _incognitoAccent),
          label: Text(
            _viewModel.selectedModel?.name ?? 'Select a model to start',
            style: TextStyle(color: _incognitoAccent),
          ),
        ),
      ],
    );
  }

  Widget? _buildChatFooter() {
    if (_viewModel.hasImageAttachments) {
      return ChatAttachmentRow(
        itemCount: _viewModel.imageFiles.length,
        itemBuilder: (context, index) {
          return ChatAttachmentImage(
            imageFile: _viewModel.imageFiles[index],
            onRemove: (imageFile) => _viewModel.removeImage(imageFile),
          );
        },
      );
    } else if (_viewModel.messages.isEmpty && _viewModel.presets.isNotEmpty) {
      return ChatAttachmentRow(
        itemCount: _viewModel.presets.length,
        itemBuilder: (context, index) {
          final preset = _viewModel.presets[index];
          return ChatAttachmentPreset(
            preset: preset,
            onPressed: () async {
              _viewModel.setTextFieldValue(preset.prompt);
              await _sendMessage();
            },
          );
        },
      );
    }

    return null;
  }

  double _chatBodyBottomPadding(BuildContext context) {
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    final composerPadding = _shouldShowExpanded ? _expandedComposerPadding : _collapsedComposerPadding;
    final base = composerPadding + bottomSafeArea;
    if (!_viewModel.hasImageAttachments) return base;

    return base + _attachmentPreviewHeight(context) + _footerSpacing;
  }

  double _attachmentPreviewHeight(BuildContext context) {
    return MediaQuery.of(context).size.height * ChatAttachmentImage.previewHeightFactor;
  }

  Future<void> _sendMessage() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isInputExpanded = false);
    await _viewModel.sendMessage(
      onModelSelectionRequired: _showModelSelectionBottomSheet,
      onServerNotConfigured: _onServerNotConfigured,
    );
  }

  Future<void> _showModelSelectionBottomSheet() async {
    final selectedModel = await showModelSelectionBottomSheet(
      context: context,
      title: "Select a Model",
      currentModelName: _viewModel.selectedModel?.name,
    );

    if (selectedModel != null) {
      _viewModel.setSelectedModel(selectedModel);
    }
  }

  Future<void> _handleAttachmentButton() async {
    await _viewModel.pickImages(
      onPermissionDenied: _showPhotosDeniedAlert,
    );
  }

  void _onServerNotConfigured() {
    setState(() {
      _crossFadeState = CrossFadeState.showSecond;
      _scale = _scale == 1.0 ? 1.05 : 1.0;
    });
  }

  Future<void> _showPhotosDeniedAlert() async {
    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Photos Permission Denied'),
          content: const Text('Please allow access to photos in the settings.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
