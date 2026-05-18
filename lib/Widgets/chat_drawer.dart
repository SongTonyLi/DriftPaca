import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:llamaseek/Constants/constants.dart';
import 'package:llamaseek/Models/ollama_chat.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
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
    if (date == null) return 'Older';
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
              isSelected: chatProvider.currentChat == null,
              onTap: () {
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

                    return _ChatDrawerTile(
                      icon: Icons.chat_outlined,
                      selectedIcon: Icons.chat,
                      title: chat.title,
                      isSelected: isSelected,
                      onTap: () {
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
    } else if (result == 'delete') {
      final confirmed = await _showDeleteDialog(context);
      if (confirmed == true) {
        await chatProvider.deleteChat(chat);
      }
    }
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
  final VoidCallback onDelete;
  final String chatTitle;

  const _GlassContextMenu({
    required this.onRename,
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

class _ChatDrawerTile extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;
  final void Function(Offset globalPosition)? onLongPress;

  const _ChatDrawerTile({
    required this.icon,
    required this.selectedIcon,
    required this.title,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onLongPressStart: onLongPress != null
          ? (details) => onLongPress!(details.globalPosition)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
        child: Material(
          color: isSelected
              ? colorScheme.secondaryContainer.withValues(alpha: 0.45)
              : Colors.transparent,
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
                    color: isSelected
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected
                            ? colorScheme.onSecondaryContainer
                            : colorScheme.onSurfaceVariant,
                      ),
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
