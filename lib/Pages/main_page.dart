import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:llamaseek/Pages/chat_page/chat_page.dart';
import 'package:llamaseek/Pages/openwebui_page.dart';
import 'package:llamaseek/Widgets/chat_app_bar.dart';
import 'package:llamaseek/Widgets/chat_drawer.dart';
import 'package:responsive_framework/responsive_framework.dart';

class LlamaSeekMainPage extends StatelessWidget {
  const LlamaSeekMainPage({super.key});

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
          return const _LlamaSeekMobileMainPage();
        } else {
          return const _LlamaSeekLargeMainPage();
        }
      },
    );
  }
}

class _LlamaSeekMobileMainPage extends StatelessWidget {
  const _LlamaSeekMobileMainPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const ChatAppBar(),
      body: const SafeArea(top: false, bottom: false, child: ChatPage()),
      drawer: const ChatDrawer(),
      drawerScrimColor: Colors.transparent,
    );
  }
}

class _LlamaSeekLargeMainPage extends StatelessWidget {
  const _LlamaSeekLargeMainPage();

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
