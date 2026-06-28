import 'package:flutter/material.dart';
import 'package:llamaseek/Models/ollama_model.dart';

import 'model_brand_mark.dart';
import 'welcome_scaffold.dart';

/// The normal (non-incognito) empty-chat welcome, built on the shared
/// [WelcomeScaffold] so it matches the incognito screen's layout and entrance.
/// Uses the app's theme accent (derived from the user's gradient colours) and
/// invites the user to pick a model and start. Once a model is selected its
/// provider logo replaces the CTA's default icon.
class NormalWelcome extends StatelessWidget {
  final OllamaModel? selectedModel;
  final VoidCallback onSelectModel;

  const NormalWelcome({
    super.key,
    required this.selectedModel,
    required this.onSelectModel,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final model = selectedModel;
    return WelcomeScaffold(
      accent: accent,
      eyebrow: 'WELCOME',
      title: 'Start a conversation',
      ctaLabel: model?.name ?? 'Select a model to start',
      ctaLeading:
          model == null ? null : ModelBrandMark(model: model, tint: accent),
      onCta: onSelectModel,
    );
  }
}
