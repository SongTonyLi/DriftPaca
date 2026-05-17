import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:llamaseek/Constants/constants.dart';
import 'package:llamaseek/Widgets/model_selection_bottom_sheet.dart';
import 'package:provider/provider.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:responsive_framework/responsive_framework.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  static const double mobileOverlayHeight = 50;
  static const double titleWidthFactor = 0.8;

  const ChatAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final isMobile = ResponsiveBreakpoints.of(context).isMobile;

    return AppBar(
      toolbarHeight: isMobile ? mobileOverlayHeight : kToolbarHeight,
      title: FractionallySizedBox(
        widthFactor: titleWidthFactor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              chatProvider.currentChat?.title ?? AppConstants.appName,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (chatProvider.currentChat != null)
              InkWell(
                onTap: () {
                  _handleModelSelectionButton(context);
                },
                customBorder: StadiumBorder(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: ValueListenableBuilder(
                    valueListenable: Hive.box('settings').listenable(keys: ['isCloudMode']),
                    builder: (context, box, _) {
                      final isCloud = box.get('isCloudMode', defaultValue: false);
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isCloud ? Icons.cloud_outlined : Icons.dns_outlined,
                            size: 12,
                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            chatProvider.currentChat!.model,
                            style: GoogleFonts.kodeMono(
                              textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                                  ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () {
            chatProvider.destinationChatSelected(0);
          },
        ),
      ],
      forceMaterialTransparency: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }

  Future<void> _handleModelSelectionButton(BuildContext context) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    final selectedModel = await showModelSelectionBottomSheet(
      context: context,
      title: "Change The Model",
      currentModelName: chatProvider.currentChat?.model,
    );

    if (selectedModel != null) {
      await chatProvider.updateCurrentChat(newModel: selectedModel.name);
    }
  }

  @override
  Size get preferredSize => const Size.fromHeight(mobileOverlayHeight);
}
