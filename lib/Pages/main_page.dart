import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:llamaseek/Pages/chat_page/chat_page.dart';
import 'package:llamaseek/Pages/chat_page/chat_page_view_model.dart';
import 'package:llamaseek/Pages/openwebui_page.dart';
import 'package:llamaseek/Widgets/chat_app_bar.dart';
import 'package:llamaseek/Widgets/chat_drawer.dart';
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

  static const _incognitoColorScheme = ColorScheme.dark(
    surface: Color(0xFF0D0D1A),
    onSurface: Color(0xFFE0E0E8),
    onSurfaceVariant: Color(0xFF9898B0),
    primary: Color(0xFF6C63FF),
    onPrimary: Colors.white,
    primaryContainer: Color(0xFF2A2A50),
    onPrimaryContainer: Color(0xFFD0CCFF),
    secondaryContainer: Color(0xFF16162A),
    onSecondaryContainer: Color(0xFFC8C8D8),
    outline: Color(0xFF2A2A4A),
    errorContainer: Color(0xFF4A1A1A),
    onErrorContainer: Color(0xFFFFB4AB),
  );

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ChatPageViewModel>();
    final isIncognito = viewModel.currentChat?.isIncognito == true || viewModel.incognitoRequested;

    final baseTheme = Theme.of(context);

    final scaffold = Scaffold(
      extendBodyBehindAppBar: true,
      // backgroundColor is intentionally NOT set — AnimatedTheme
      // interpolates colorScheme.surface smoothly. An explicit override
      // here would snap instantly, desyncing from the gradient overlay.
      appBar: const ChatAppBar(),
      body: const SafeArea(top: false, bottom: false, child: ChatPage()),
      drawer: const ChatDrawer(),
      drawerScrimColor: Colors.transparent,
    );

    // Derive incognito theme from base so text styles share the same
    // `inherit` value — required for AnimatedTheme's TextStyle.lerp.
    final incognitoTheme = baseTheme.copyWith(
      brightness: Brightness.dark,
      colorScheme: _incognitoColorScheme,
      scaffoldBackgroundColor: _incognitoColorScheme.surface,
      iconTheme: baseTheme.iconTheme.copyWith(
        color: _incognitoColorScheme.onSurface,
      ),
      textTheme: baseTheme.textTheme.apply(
        bodyColor: _incognitoColorScheme.onSurface,
        displayColor: _incognitoColorScheme.onSurface,
      ),
    );

    return AnimatedTheme(
      data: isIncognito ? incognitoTheme : baseTheme,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
      child: scaffold,
    );
  }
}

class _DriftPacaLargeMainPage extends StatelessWidget {
  const _DriftPacaLargeMainPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            ChatDrawer(),
            Expanded(child: ChatPage()),
          ],
        ),
      ),
    );
  }
}
