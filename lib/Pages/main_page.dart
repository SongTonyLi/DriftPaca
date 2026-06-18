import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:llamaseek/Pages/chat_page/chat_page.dart';
import 'package:llamaseek/Pages/chat_page/chat_page_view_model.dart';
import 'package:llamaseek/Pages/openwebui_page.dart';
import 'package:llamaseek/Utils/gradient_settings.dart';
import 'package:llamaseek/Utils/mode_palette.dart';
import 'package:llamaseek/Widgets/chat_app_bar.dart';
import 'package:llamaseek/Widgets/chat_drawer.dart';
import 'package:llamaseek/Widgets/floating_gradient_background.dart';
import 'package:provider/provider.dart';
import 'package:responsive_framework/responsive_framework.dart';

class DriftPacaMainPage extends StatelessWidget {
  const DriftPacaMainPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('settings').listenable(
        keys: ['serverMode', 'openwebuiAddress'],
      ),
      builder: (context, box, _) {
        final serverMode = box.get('serverMode', defaultValue: 'local');
        final openwebuiAddress = box.get('openwebuiAddress');

        if (serverMode == 'openwebui' && openwebuiAddress != null) {
          return const OpenWebuiPage();
        }

        if (ResponsiveBreakpoints.of(context).isMobile) {
          return const _DriftPacaMobileMainPage();
        } else {
          return const _DriftPacaLargeMainPage();
        }
      },
    );
  }
}

class _DriftPacaMobileMainPage extends StatelessWidget {
  const _DriftPacaMobileMainPage();

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ChatPageViewModel>();
    final isIncognito =
        viewModel.currentChat?.isIncognito == true || viewModel.incognitoRequested;
    final isGenerating = viewModel.isStreaming || viewModel.isThinking;

    final baseTheme = Theme.of(context);
    final pair = readGradientPair(Hive.box('settings'));
    final systemDark = baseTheme.brightness == Brightness.dark;
    final mode = isIncognito
        ? (systemDark ? AppMode.incognitoDark : AppMode.incognitoLight)
        : (systemDark ? AppMode.dark : AppMode.normal);
    final palette = resolvePalette(pair, mode);

    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: const ChatAppBar(),
      body: const SafeArea(top: false, bottom: false, child: ChatPage()),
      drawer: const ChatDrawer(),
      drawerScrimColor: Colors.transparent,
    );

    // Incognito theme now derives from the resolver instead of a hardcoded scheme.
    final incognitoTheme = baseTheme.copyWith(
      brightness: baseTheme.brightness, // incognito follows the system light/dark
      colorScheme: palette.scheme,
      scaffoldBackgroundColor: Colors.transparent,
      iconTheme: baseTheme.iconTheme.copyWith(color: palette.scheme.onSurface),
      textTheme: baseTheme.textTheme.apply(
        bodyColor: palette.scheme.onSurface,
        displayColor: palette.scheme.onSurface,
      ),
    );

    return AnimatedTheme(
      data: isIncognito ? incognitoTheme : baseTheme,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
      child: Stack(
        children: [
          Positioned.fill(
            child: FloatingGradientBackground(
              meshA: palette.meshA,
              meshB: palette.meshB,
              canvas: palette.canvas,
              idleColor: palette.idle,
              isGenerating: isGenerating,
            ),
          ),
          scaffold,
        ],
      ),
    );
  }
}

class _DriftPacaLargeMainPage extends StatelessWidget {
  const _DriftPacaLargeMainPage();

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ChatPageViewModel>();
    final isIncognito =
        viewModel.currentChat?.isIncognito == true || viewModel.incognitoRequested;
    final isGenerating = viewModel.isStreaming || viewModel.isThinking;
    final baseTheme = Theme.of(context);
    final pair = readGradientPair(Hive.box('settings'));
    final systemDark = baseTheme.brightness == Brightness.dark;
    final mode = isIncognito
        ? (systemDark ? AppMode.incognitoDark : AppMode.incognitoLight)
        : (systemDark ? AppMode.dark : AppMode.normal);
    final palette = resolvePalette(pair, mode);

    return Stack(
      children: [
        Positioned.fill(
          child: FloatingGradientBackground(
            meshA: palette.meshA,
            meshB: palette.meshB,
            canvas: palette.canvas,
            idleColor: palette.idle,
            isGenerating: isGenerating,
          ),
        ),
        const Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Row(
              children: [
                ChatDrawer(),
                Expanded(child: ChatPage()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
