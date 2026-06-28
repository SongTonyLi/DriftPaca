import 'package:flutter/material.dart';
import 'package:llamaseek/Models/ollama_model.dart';

/// A provider "brand" shown for a model on the wheel: its logo, an accent colour
/// (used for the node glow and the brand-tinted mesh) and a display label.
///
/// Models are matched to a brand by scanning their family/name for a known
/// keyword (see [brandForModel]); anything we don't recognise falls back to the
/// neutral Ollama mark so the wheel never shows a blank node.
@immutable
class BrandLogo {
  /// Stable id, e.g. `qwen`. The fallback brand uses `ollama`.
  final String key;

  /// SVG asset path.
  final String asset;

  /// Accent colour for the glow + mesh tint. Lightness is clamped per app mode
  /// at paint time, so a very dark/very light brand colour still reads.
  final Color accent;

  /// Human label, e.g. `Qwen`.
  final String label;

  /// True if the mark is a single-colour (`currentColor`) silhouette that must
  /// be tinted to the foreground to read in both light and dark (e.g. OpenAI).
  final bool monochrome;

  const BrandLogo({
    required this.key,
    required this.asset,
    required this.accent,
    required this.label,
    this.monochrome = false,
  });

  /// True for the catch-all Ollama mark (an unrecognised model).
  bool get isFallback => key == 'ollama';

  /// Whether to draw the logo tinted to the foreground (fallback or monochrome
  /// marks) instead of in its own colours.
  bool get tinted => isFallback || monochrome;
}

const String _dir = 'assets/images/model_logos';

/// Catch-all for models whose family/name we don't recognise. Uses the existing
/// bundled Ollama mark and a neutral slate accent.
const BrandLogo kOllamaBrand = BrandLogo(
  key: 'ollama',
  asset: 'assets/images/ollama.svg',
  accent: Color(0xFF7D7D85),
  label: 'Ollama',
);

/// Every known provider brand. Accent colours are sampled from each logo's own
/// palette (see the `*-color.svg` sources).
const List<BrandLogo> kBrands = [
  BrandLogo(key: 'openai', asset: '$_dir/openai.svg', accent: Color(0xFF10A37F), label: 'OpenAI', monochrome: true),
  BrandLogo(key: 'qwen', asset: '$_dir/qwen.svg', accent: Color(0xFF6B57F0), label: 'Qwen'),
  BrandLogo(key: 'deepseek', asset: '$_dir/deepseek.svg', accent: Color(0xFF4D6BFE), label: 'DeepSeek'),
  BrandLogo(key: 'gemma', asset: '$_dir/gemma.svg', accent: Color(0xFF446EFF), label: 'Gemma'),
  BrandLogo(key: 'gemini', asset: '$_dir/gemini.svg', accent: Color(0xFF3186FF), label: 'Gemini'),
  BrandLogo(key: 'mistral', asset: '$_dir/mistral.svg', accent: Color(0xFFFA500F), label: 'Mistral'),
  BrandLogo(key: 'chatglm', asset: '$_dir/chatglm.svg', accent: Color(0xFF3D6BFF), label: 'ChatGLM'),
  BrandLogo(key: 'kimi', asset: '$_dir/kimi.svg', accent: Color(0xFF1783FF), label: 'Kimi'),
  BrandLogo(key: 'minimax', asset: '$_dir/minimax.svg', accent: Color(0xFFE2167E), label: 'MiniMax'),
  BrandLogo(key: 'nvidia', asset: '$_dir/nvidia.svg', accent: Color(0xFF74B71B), label: 'NVIDIA'),
  BrandLogo(key: 'essentialai', asset: '$_dir/essentialai.svg', accent: Color(0xFF6A46AC), label: 'Essential AI'),
];

/// Keyword → brand key, checked (in order, first match wins) against the
/// lowercased `"<family> <name>"` of a model. Multiple keywords can map to one
/// brand (e.g. `mixtral`/`codestral` → mistral, `glm` → chatglm).
const List<(String, String)> _matchers = [
  ('gpt-oss', 'openai'),
  ('gpt', 'openai'),
  ('openai', 'openai'),
  ('qwen', 'qwen'),
  ('deepseek', 'deepseek'),
  ('gemma', 'gemma'),
  ('gemini', 'gemini'),
  ('mixtral', 'mistral'),
  ('ministral', 'mistral'),
  ('codestral', 'mistral'),
  ('devstral', 'mistral'),
  ('mistral', 'mistral'),
  ('chatglm', 'chatglm'),
  ('glm', 'chatglm'),
  ('moonshot', 'kimi'),
  ('kimi', 'kimi'),
  ('minimax', 'minimax'),
  ('nemotron', 'nvidia'),
  ('nvidia', 'nvidia'),
  ('essential', 'essentialai'),
];

final Map<String, BrandLogo> _byKey = {for (final b in kBrands) b.key: b};

/// Look up a brand by its stable [key]; the Ollama fallback for unknown keys.
BrandLogo brandByKey(String key) => _byKey[key] ?? kOllamaBrand;

/// Resolve the brand for a model from its family + name. Unrecognised models get
/// the Ollama fallback mark.
BrandLogo brandForModel(OllamaModel model) =>
    brandForFamilyName('${model.family} ${model.name}');

/// Resolve a brand from an arbitrary `"family name"` string (exposed for tests
/// and the preview harness).
BrandLogo brandForFamilyName(String familyName) {
  final hay = familyName.toLowerCase();
  for (final (needle, key) in _matchers) {
    if (hay.contains(needle)) return _byKey[key] ?? kOllamaBrand;
  }
  return kOllamaBrand;
}
