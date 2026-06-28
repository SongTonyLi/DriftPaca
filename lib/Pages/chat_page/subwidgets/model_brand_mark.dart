import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:llamaseek/Constants/brand_logos.dart';
import 'package:llamaseek/Models/ollama_model.dart';

/// The selected model's provider logo, sized to sit inline on the welcome CTA
/// pill in place of its default leading icon.
///
/// Full-colour brand marks (Qwen, DeepSeek, …) keep their own palette so the
/// provider stays recognisable; flat silhouettes — the Ollama fallback and
/// monochrome marks like OpenAI — are tinted to [tint] (the pill's accent) so
/// they read in both light and dark, matching the wheel's brand nodes.
class ModelBrandMark extends StatelessWidget {
  final OllamaModel model;
  final Color tint;
  final double size;

  const ModelBrandMark({
    super.key,
    required this.model,
    required this.tint,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    final brand = brandForModel(model);
    return SizedBox(
      width: size,
      height: size,
      child: SvgPicture.asset(
        brand.asset,
        fit: BoxFit.contain,
        colorFilter:
            brand.tinted ? ColorFilter.mode(tint, BlendMode.srcIn) : null,
      ),
    );
  }
}
