import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:llamaseek/Pages/model_select_page/model_select_route.dart';
import 'package:llamaseek/Pages/chat_page/chat_page_view_model.dart';
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
    final currentChat = chatProvider.currentChat;

    return AppBar(
      toolbarHeight: isMobile ? mobileOverlayHeight : kToolbarHeight,
      // No title on the empty/welcome states — the welcome screen carries the
      // branding there. A real conversation shows its title + model chip.
      title: currentChat == null
          ? null
          : FractionallySizedBox(
              widthFactor: titleWidthFactor,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    currentChat.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                                currentChat.model,
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
            final viewModel = Provider.of<ChatPageViewModel>(context, listen: false);
            // Stay in current mode: if currently incognito, new chat is also incognito
            final wasIncognito = chatProvider.currentChat?.isIncognito == true || viewModel.incognitoRequested;
            if (wasIncognito) {
              viewModel.requestIncognito();
            } else {
              viewModel.clearIncognito();
            }
            chatProvider.destinationChatSelected(0);
          },
        ),
      ],
      forceMaterialTransparency: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      // Fade the bar's surface from opaque at the top to fully transparent
      // at the bottom so the blurred area doesn't end as a hard line — the
      // chat content underneath emerges smoothly instead of stepping.
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
          // Container (not DecoratedBox) — without a child or constraints it
          // expands to fill the BackdropFilter's bounds, so the blur and
          // gradient actually have a paint area to land on.
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleModelSelectionButton(BuildContext context) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    final selectedModel = await showModelSelectWheel(
      context: context,
      title: "Change the model",
      currentModelName: chatProvider.currentChat?.model,
    );

    if (selectedModel != null) {
      await chatProvider.updateCurrentChat(newModel: selectedModel.name);
    }
  }

  @override
  Size get preferredSize => const Size.fromHeight(mobileOverlayHeight);
}
