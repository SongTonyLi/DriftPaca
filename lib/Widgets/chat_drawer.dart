import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:llamaseek/Constants/constants.dart';
import 'package:llamaseek/Constants/memory_constants.dart';
import 'package:llamaseek/Models/agent_memory.dart';
import 'package:llamaseek/Models/conversation_memory.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Pages/chat_page/chat_page_view_model.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Services/memory_service.dart';
import 'package:llamaseek/Widgets/memory_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';

import 'title_divider.dart';

class ChatDrawer extends StatelessWidget {
  const ChatDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      backgroundColor: Colors.transparent,
      width: 400,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20.0),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.40),
                  borderRadius: BorderRadius.circular(20.0),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.15),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  children: [
                    const Expanded(child: ChatNavigationDrawer()),
                    Builder(builder: (context) {
                      final chatProvider = Provider.of<ChatProvider>(context);
                      final viewModel = Provider.of<ChatPageViewModel>(context);
                      final isIncognito = chatProvider.currentChat?.isIncognito == true || viewModel.incognitoRequested;
                      if (isIncognito) return const SizedBox.shrink();
                      return Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
                        child: _AgentMemoryTile(),
                      );
                    }),
                    Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.fromLTRB(28, 16, 28, 10),
                      child: IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () {
                          if (ResponsiveBreakpoints.of(context).isMobile) {
                            Navigator.pop(context);
                          }

                          Navigator.pushNamed(context, '/settings');
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChatNavigationDrawer extends StatelessWidget {
  const ChatNavigationDrawer({super.key});

  static String _dateGroupLabel(DateTime? date) {
    if (date == null) return 'Today';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final chatDay = DateTime(date.year, date.month, date.day);
    final diff = today.difference(chatDay).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff <= 7) return 'Previous 7 Days';
    if (diff <= 30) return 'Previous 30 Days';
    return 'Older';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        // Group chats by date
        final groups = <String, List<MapEntry<int, OllamaChat>>>{};
        for (final entry in chatProvider.chats.asMap().entries) {
          final label = _dateGroupLabel(entry.value.lastUpdate);
          groups.putIfAbsent(label, () => []).add(entry);
        }

        // Preserve display order
        const groupOrder = ['Today', 'Yesterday', 'Previous 7 Days', 'Previous 30 Days', 'Older'];

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 16, 10),
              child: Text(
                AppConstants.appName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            _ChatDrawerTile(
              icon: Icons.add_circle_outline,
              selectedIcon: Icons.add_circle,
              title: 'New Chat',
              isSelected: chatProvider.currentChat == null && !Provider.of<ChatPageViewModel>(context).incognitoRequested,
              onTap: () {
                final viewModel = Provider.of<ChatPageViewModel>(context, listen: false);
                viewModel.clearIncognito();
                chatProvider.destinationChatSelected(0);
                if (ResponsiveBreakpoints.of(context).isMobile) {
                  Navigator.pop(context);
                }
              },
            ),
            _ChatDrawerTile(
              icon: Icons.visibility_off_outlined,
              selectedIcon: Icons.visibility_off,
              title: 'New Incognito Chat',
              isSelected: false,
              isIncognito: true,
              onTap: () {
                final viewModel = Provider.of<ChatPageViewModel>(context, listen: false);
                viewModel.requestIncognito();
                chatProvider.destinationChatSelected(0);
                if (ResponsiveBreakpoints.of(context).isMobile) {
                  Navigator.pop(context);
                }
              },
            ),
            for (final groupName in groupOrder)
              if (groups.containsKey(groupName)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 10),
                  child: TitleDivider(title: groupName),
                ),
                for (final entry in groups[groupName]!) ...[
                  Builder(builder: (context) {
                    final index = entry.key;
                    final chat = entry.value;
                    final isSelected = chatProvider.currentChat?.id == chat.id;

                    final memoryService = Provider.of<MemoryService>(context);
                    final isSummarizing = memoryService.isUpdating && memoryService.updatingChatId == chat.id;

                    return _ChatDrawerTile(
                      icon: chat.isIncognito ? Icons.visibility_off_outlined : Icons.chat_outlined,
                      selectedIcon: chat.isIncognito ? Icons.visibility_off : Icons.chat,
                      title: chat.title,
                      isSelected: isSelected,
                      isSummarizing: isSummarizing,
                      isIncognito: chat.isIncognito,
                      onTap: () {
                        // Clear incognito flag when selecting an existing chat
                        Provider.of<ChatPageViewModel>(context, listen: false).clearIncognito();
                        chatProvider.destinationChatSelected(index + 1);
                        if (ResponsiveBreakpoints.of(context).isMobile) {
                          Navigator.pop(context);
                        }
                      },
                      onLongPress: (position) {
                        _showChatContextMenu(context, chat, position);
                      },
                    );
                  }),
                ],
              ],
          ],
        );
      },
    );
  }

  void _showChatContextMenu(
    BuildContext context,
    OllamaChat chat,
    Offset position,
  ) async {
    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      transitionBuilder: (dialogContext, animation, secondaryAnimation, _) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeIn,
        );

        return Stack(
          children: [
            Positioned(
              left: position.dx.clamp(16.0, MediaQuery.of(dialogContext).size.width - 196),
              top: position.dy.clamp(60.0, MediaQuery.of(dialogContext).size.height - 160),
              child: ScaleTransition(
                scale: curvedAnimation,
                alignment: Alignment.topLeft,
                child: FadeTransition(
                  opacity: animation,
                  child: _GlassContextMenu(
                    onRename: () => Navigator.pop(dialogContext, 'rename'),
                    onMemory: () => Navigator.pop(dialogContext, 'memory'),
                    onDelete: () => Navigator.pop(dialogContext, 'delete'),
                    chatTitle: chat.title,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    if (result == null || !context.mounted) return;

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    if (result == 'rename') {
      final newTitle =
          await _showRenameDialog(context, currentTitle: chat.title);
      if (newTitle != null) {
        await chatProvider.updateChat(chat, newTitle: newTitle);
      }
    } else if (result == 'memory') {
      _showConversationMemory(context, chat);
    } else if (result == 'delete') {
      final confirmed = await _showDeleteDialog(context);
      if (confirmed == true) {
        await chatProvider.deleteChat(chat);
      }
    }
  }

  void _showConversationMemory(BuildContext context, OllamaChat chat) async {
    final memoryService = Provider.of<MemoryService>(context, listen: false);
    final convMemory = await memoryService.getConversationMemory(chat.id) ?? ConversationMemory();

    if (!context.mounted) return;

    showMemoryBottomSheet(
      context,
      title: 'Conversation Memory',
      maxTotalTokens: MemoryConstants.maxConversationMemoryTokens,
      isUpdating: memoryService.isUpdating,
      updatingModelName: Hive.box('settings').get('memoryModel', defaultValue: MemoryConstants.defaultModel),
      lastUpdatedAt: convMemory.updatedAt,
      lastUpdatedByModel: Hive.box('settings').get('memoryModel', defaultValue: MemoryConstants.defaultModel),
      sections: [
        MemorySection(label: 'Summary', key: 'summary', value: convMemory.summary),
        MemorySection(label: 'Key Context', key: 'key_context', value: convMemory.keyContext),
        MemorySection(label: 'User Requests', key: 'user_requests', value: convMemory.userRequests),
        MemorySection(label: 'Media Descriptions', key: 'media_descriptions', value: convMemory.mediaDescriptions),
        MemorySection(label: 'Current State', key: 'current_state', value: convMemory.currentState),
        MemorySection(label: 'Errors & Solutions', key: 'errors_and_solutions', value: convMemory.errorsAndSolutions),
        MemorySection(label: 'Model History', key: 'model_history', value: convMemory.modelHistory),
        MemorySection(label: 'Unresolved Items', key: 'unresolved_items', value: convMemory.unresolvedItems),
      ],
      onSave: (sections) {
        final updated = ConversationMemory(
          summary: sections.firstWhere((s) => s.key == 'summary').value,
          keyContext: sections.firstWhere((s) => s.key == 'key_context').value,
          userRequests: sections.firstWhere((s) => s.key == 'user_requests').value,
          mediaDescriptions: sections.firstWhere((s) => s.key == 'media_descriptions').value,
          currentState: sections.firstWhere((s) => s.key == 'current_state').value,
          errorsAndSolutions: sections.firstWhere((s) => s.key == 'errors_and_solutions').value,
          modelHistory: sections.firstWhere((s) => s.key == 'model_history').value,
          unresolvedItems: sections.firstWhere((s) => s.key == 'unresolved_items').value,
        );
        memoryService.updateConversationMemoryField(chat.id, updated);
      },
      onClear: () {
        memoryService.updateConversationMemoryField(chat.id, ConversationMemory());
      },
      onResummarize: (content, limit) => memoryService.resummarize(content, limit),
    );
  }

  Future<String?> _showRenameDialog(
    BuildContext context, {
    String? currentTitle,
  }) async {
    String? newTitle;

    return await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename Chat'),
          content: TextFormField(
            initialValue: currentTitle,
            decoration: const InputDecoration(
              labelText: 'New Name',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
            autofocus: true,
            onChanged: (value) => newTitle = value,
            onTapOutside: (PointerDownEvent event) {
              FocusManager.instance.primaryFocus?.unfocus();
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (newTitle != null && newTitle!.trim().isNotEmpty) {
                  Navigator.of(context).pop(newTitle!.trim());
                }
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showDeleteDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Chat?'),
          content: const Text("This action can't be undone."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}

class _GlassContextMenu extends StatelessWidget {
  final VoidCallback onRename;
  final VoidCallback onMemory;
  final VoidCallback onDelete;
  final String chatTitle;

  const _GlassContextMenu({
    required this.onRename,
    required this.onMemory,
    required this.onDelete,
    required this.chatTitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16.0),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Material(
          color: colorScheme.surface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(16.0),
          child: Container(
            width: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  chatTitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Divider(height: 1, indent: 12, endIndent: 12),
              _GlassMenuItem(
                icon: Icons.edit_outlined,
                label: 'Rename',
                onTap: onRename,
              ),
              _GlassMenuItem(
                icon: Icons.auto_awesome_outlined,
                label: 'Memory',
                onTap: onMemory,
              ),
              _GlassMenuItem(
                icon: Icons.delete_outline,
                label: 'Delete',
                onTap: onDelete,
                isDestructive: true,
              ),
              const SizedBox(height: 4),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

class _GlassMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _GlassMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive
        ? Colors.red
        : Theme.of(context).colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgentMemoryTile extends StatelessWidget {
  const _AgentMemoryTile();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final memoryService = Provider.of<MemoryService>(context);
    final isUpdating = memoryService.isUpdating;

    return InkWell(
      onTap: () => _showAgentMemory(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            if (isUpdating)
              _PulsingIcon(
                icon: Icons.auto_awesome,
                size: 22,
                color: colorScheme.primary,
              )
            else
              Icon(Icons.auto_awesome_outlined, color: colorScheme.onSurfaceVariant, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Agent Memory',
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
              ),
            ),
            if (isUpdating)
              Text(
                'Updating...',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.primary,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showAgentMemory(BuildContext context) async {
    final memoryService = Provider.of<MemoryService>(context, listen: false);
    final agentMemory = await memoryService.getAgentMemory() ?? AgentMemory();

    if (!context.mounted) return;

    showMemoryBottomSheet(
      context,
      title: 'Agent Memory',
      maxTotalTokens: MemoryConstants.maxAgentMemoryTokens,
      isUpdating: memoryService.isUpdating,
      updatingModelName: Hive.box('settings').get('memoryModel', defaultValue: MemoryConstants.defaultModel),
      lastUpdatedAt: agentMemory.updatedAt,
      lastUpdatedByModel: Hive.box('settings').get('memoryModel', defaultValue: MemoryConstants.defaultModel),
      sections: [
        MemorySection(
          label: 'System Info',
          key: 'system_info',
          value: 'Current time: ${DateTime.now().toString().split('.').first} (${DateTime.now().timeZoneName})',
          readOnly: true,
        ),
        MemorySection(label: 'User Profile', key: 'user_profile', value: agentMemory.userProfile),
        MemorySection(label: 'Preferences', key: 'preferences', value: agentMemory.preferences),
        MemorySection(label: 'Learned Facts', key: 'learned_facts', value: agentMemory.learnedFacts),
        MemorySection(label: 'Interests & Expertise', key: 'interests_and_expertise', value: agentMemory.interestsAndExpertise),
        MemorySection(label: 'Language & Tone', key: 'language_and_tone', value: agentMemory.languageAndTone),
        MemorySection(label: 'Key People', key: 'key_people', value: agentMemory.keyPeople),
        MemorySection(label: 'Ongoing Projects & Goals', key: 'ongoing_projects', value: agentMemory.ongoingProjects),
        MemorySection(label: 'Past Conversations', key: 'past_conversation_refs', value: agentMemory.pastConversationRefs),
      ],
      onSave: (sections) {
        final updated = AgentMemory(
          userProfile: sections.firstWhere((s) => s.key == 'user_profile').value,
          preferences: sections.firstWhere((s) => s.key == 'preferences').value,
          learnedFacts: sections.firstWhere((s) => s.key == 'learned_facts').value,
          interestsAndExpertise: sections.firstWhere((s) => s.key == 'interests_and_expertise').value,
          languageAndTone: sections.firstWhere((s) => s.key == 'language_and_tone').value,
          keyPeople: sections.firstWhere((s) => s.key == 'key_people').value,
          ongoingProjects: sections.firstWhere((s) => s.key == 'ongoing_projects').value,
          pastConversationRefs: sections.firstWhere((s) => s.key == 'past_conversation_refs').value,
        );
        memoryService.updateAgentMemoryField(updated);
      },
      onClear: () => memoryService.clearAgentMemory(),
      onResummarize: (content, limit) => memoryService.resummarize(content, limit),
    );
  }
}

class _ChatDrawerTile extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String title;
  final bool isSelected;
  final bool isSummarizing;
  final bool isIncognito;
  final VoidCallback onTap;
  final void Function(Offset globalPosition)? onLongPress;

  const _ChatDrawerTile({
    required this.icon,
    required this.selectedIcon,
    required this.title,
    required this.isSelected,
    this.isSummarizing = false,
    this.isIncognito = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    const incognitoAccent = Color(0xFF6C63FF);
    final Color tileColor;
    final Color contentColor;
    if (isSelected && isIncognito) {
      tileColor = incognitoAccent.withValues(alpha: 0.12);
      contentColor = incognitoAccent.withValues(alpha: 0.8);
    } else if (isSelected) {
      tileColor = colorScheme.secondaryContainer.withValues(alpha: 0.45);
      contentColor = colorScheme.onSecondaryContainer;
    } else if (isIncognito) {
      tileColor = Colors.transparent;
      contentColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.75);
    } else {
      tileColor = Colors.transparent;
      contentColor = colorScheme.onSurfaceVariant;
    }

    return GestureDetector(
      onLongPressStart: onLongPress != null
          ? (details) => onLongPress!(details.globalPosition)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
        child: Material(
          color: tileColor,
          borderRadius: BorderRadius.circular(28.0),
          child: InkWell(
            borderRadius: BorderRadius.circular(28.0),
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  Icon(
                    isSelected ? selectedIcon : icon,
                    color: contentColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: contentColor,
                        fontStyle: isIncognito ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ),
                  if (isSummarizing)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _PulsingIcon(
                        icon: Icons.auto_awesome,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color color;

  const _PulsingIcon({required this.icon, required this.size, required this.color});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon> with SingleTickerProviderStateMixin {
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
      child: Icon(widget.icon, size: widget.size, color: widget.color),
    );
  }
}
