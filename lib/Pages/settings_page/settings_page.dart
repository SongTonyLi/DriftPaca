import 'package:flutter/material.dart';
import 'package:llamaseek/Models/settings_route_arguments.dart';

import 'subwidgets/subwidgets.dart';

class SettingsPage extends StatelessWidget {
  final SettingsRouteArguments? arguments;

  const SettingsPage({super.key, this.arguments});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: _SettingsPageContent(arguments: arguments),
      ),
    );
  }
}

class _SettingsPageContent extends StatelessWidget {
  final SettingsRouteArguments? arguments;

  const _SettingsPageContent({required this.arguments});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        ThemesSettings(),
        SizedBox(height: 16),
        ServerSettings(
          autoFocusServerAddress: arguments?.autoFocusServerAddress ?? false,
        ),
        SizedBox(height: 16),
        ReinsSettings(),
      ],
    );
  }
}
