import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';

import 'package:llamaseek/Widgets/chat_app_bar.dart';
import 'package:llamaseek/Widgets/model_selection_bottom_sheet.dart';

import 'chat_page_view_model.dart';
import 'subwidgets/subwidgets.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  // ViewModel reference
  late final ChatPageViewModel _viewModel;

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
  }

  @override
  void dispose() {
    _inputFocusNode.removeListener(_onInputFocusChange);
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _onInputFocusChange() {
    if (!_inputFocusNode.hasFocus &&
        _viewModel.textFieldController.text.isEmpty &&
        !_viewModel.isStreaming) {
      setState(() => _isInputExpanded = false);
    }
  }

  void _expandInput() {
    setState(() => _isInputExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inputFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe to ViewModel changes
    context.watch<ChatPageViewModel>();

    return Column(
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
                bottom: 120,
                child: _buildChatFooter(),
              ),
              Positioned(
                left: 6,
                right: 6,
                bottom: _viewModel.hasImageAttachments ? 80 : 0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24.0),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                    child: Container(
                      decoration: BoxDecoration(
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
                          // TextField — always mounted, slides in/out via height + opacity
                          ClipRect(
                            child: AnimatedAlign(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOutCubic,
                              alignment: Alignment.bottomCenter,
                              heightFactor: _shouldShowExpanded ? 1.0 : 0.0,
                              child: AnimatedOpacity(
                                opacity: _shouldShowExpanded ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 350),
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
                          // Button row — always present, "Message" fades in/out
                          Padding(
                            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 6, top: 4),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.add, size: 20),
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints(),
                                  onPressed: _handleAttachmentButton,
                                ),
                                const SizedBox(width: 2),
                                IconButton(
                                  icon: Icon(
                                    _viewModel.webSearchEnabled ? Icons.travel_explore : Icons.travel_explore_outlined,
                                    size: 20,
                                    color: _viewModel.webSearchEnabled ? Theme.of(context).colorScheme.onPrimary : null,
                                  ),
                                  padding: const EdgeInsets.all(6),
                                  constraints: const BoxConstraints(),
                                  style: _viewModel.webSearchEnabled
                                      ? IconButton.styleFrom(
                                          backgroundColor: Theme.of(context).colorScheme.primary,
                                        )
                                      : null,
                                  onPressed: () => _viewModel.toggleWebSearch(),
                                  tooltip: 'Web Search',
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
                                              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (_viewModel.isStreaming)
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
                ),
              ),
            ],
          ),
        ),
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
        } else {
          return ChatEmpty(
            child: ChatSelectModelButton(
              currentModelName: _viewModel.selectedModel?.name,
              onPressed: _showModelSelectionBottomSheet,
            ),
          );
        }
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
        isAwaitingReply: _viewModel.isThinking,
        isStreaming: _viewModel.isStreaming,
        error: _viewModel.currentError != null
            ? ChatError(
                message: _viewModel.currentError!.message,
                onRetry: () => _viewModel.retryLastPrompt(),
              )
            : null,
        bottomPadding: _viewModel.hasImageAttachments ? 160 : (_shouldShowExpanded ? 110 : 80),
        topPadding: isMobile ? MediaQuery.of(context).padding.top + ChatAppBar.mobileOverlayHeight : null,
      );
    }
  }

  Widget _buildChatFooter() {
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
    } else if (_viewModel.messages.isEmpty) {
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
    } else {
      return const SizedBox();
    }
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
