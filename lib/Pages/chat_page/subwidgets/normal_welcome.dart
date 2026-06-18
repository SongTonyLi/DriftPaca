import 'package:flutter/material.dart';

import 'welcome_scaffold.dart';

/// The normal (non-incognito) empty-chat welcome, built on the shared
/// [WelcomeScaffold] so it matches the incognito screen's layout and entrance.
/// Uses the app's theme accent (derived from the user's gradient colours) and
/// invites the user to pick a model and start.
class NormalWelcome extends StatelessWidget {
  final String? selectedModelName;
  final VoidCallback onSelectModel;

  const NormalWelcome({
    super.key,
    required this.selectedModelName,
    required this.onSelectModel,
  });

  @override
  Widget build(BuildContext context) {
    return WelcomeScaffold(
      accent: Theme.of(context).colorScheme.primary,
      eyebrow: 'WELCOME',
      title: 'Start a conversation',
      ctaLabel: selectedModelName ?? 'Select a model to start',
      onCta: onSelectModel,
    );
  }
}
