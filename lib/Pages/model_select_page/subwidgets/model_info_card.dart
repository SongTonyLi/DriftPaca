import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:llamaseek/Constants/brand_logos.dart';
import 'package:llamaseek/Models/ollama_model.dart';

/// The "original" model info window — a faithful port of the bottom sheet's
/// `_ModelInfoCard`: a frosted rounded card with a header (logo / name / family
/// / capability badges), a description, a specifications table, the digest, and
/// a Select button. Readme fetching is intentionally omitted (the wheeler isn't
/// wired to OllamaService); it falls back to the model description or a
/// generated summary.
class ModelInfoCard extends StatelessWidget {
  final OllamaModel model;
  final BrandLogo brand;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final double maxWidth;
  final double maxHeight;

  const ModelInfoCard({
    super.key,
    required this.model,
    required this.brand,
    required this.onSelect,
    required this.onClose,
    required this.maxWidth,
    required this.maxHeight,
  });

  static String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  static String _formatContextLength(int ctx) {
    if (ctx >= 1000000) return '${(ctx / 1000000).toStringAsFixed(1)}M';
    if (ctx >= 1000) return '${(ctx / 1000).toStringAsFixed(0)}K';
    return ctx.toString();
  }

  static String _fallbackDescription(OllamaModel model) {
    final parts = <String>[];
    final baseName =
        model.name.contains(':') ? model.name.split(':').first : model.name;
    if (model.family.isNotEmpty) {
      parts.add('A ${model.family}-family model');
    } else {
      parts.add('$baseName model');
    }
    if (model.parameterSize.isNotEmpty) {
      parts.add('with ${model.parameterSize} parameters');
    }
    if (model.quantizationLevel.isNotEmpty) {
      parts.add('quantized to ${model.quantizationLevel}');
    }
    final caps = <String>[];
    if (model.capabilities?.thinking == true) caps.add('extended thinking');
    if (model.capabilities?.vision == true) caps.add('vision');
    if (model.capabilities?.tools == true) caps.add('tool use');
    if (caps.isNotEmpty) parts.add('supporting ${caps.join(', ')}');
    return '${parts.join(', ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final caps = model.capabilities;
    final hasCaps =
        caps != null && (caps.vision || caps.tools || caps.thinking);

    final specs = <({IconData icon, String label, String value})>[
      if (model.family.isNotEmpty)
        (icon: Icons.account_tree_rounded, label: 'Family', value: model.family),
      if (model.parameterSize.isNotEmpty)
        (icon: Icons.memory_rounded, label: 'Parameters', value: model.parameterSize),
      if (model.quantizationLevel.isNotEmpty)
        (icon: Icons.compress_rounded, label: 'Quantization', value: model.quantizationLevel),
      if (model.format.isNotEmpty)
        (icon: Icons.inventory_2_outlined, label: 'Format', value: model.format.toUpperCase()),
      (icon: Icons.sd_storage_outlined, label: 'Disk', value: _formatSize(model.size)),
      if (model.contextLength != null)
        (icon: Icons.token_rounded, label: 'Context', value: '${_formatContextLength(model.contextLength!)} tokens'),
    ];

    return Material(
      color: Colors.transparent,
      child: Container(
        width: maxWidth,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          // Solid (no BackdropFilter): blur under the 3D flip is what lagged and
          // flickered. The dimmed barrier behind makes the card legible anyway.
          color: cs.surface.withValues(alpha: 0.985),
          borderRadius: BorderRadius.circular(24),
          border:
              Border.all(color: cs.outline.withValues(alpha: 0.12), width: 0.5),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 46,
                offset: const Offset(0, 16)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                            color: cs.onSurface.withValues(alpha: 0.06)),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 34,
                          height: 34,
                          child: SvgPicture.asset(
                            brand.asset,
                            fit: BoxFit.contain,
                            colorFilter: brand.isFallback
                                ? ColorFilter.mode(
                                    cs.onSurface.withValues(alpha: 0.8),
                                    BlendMode.srcIn)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                model.name,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              if (model.family.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  model.family.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                    color: cs.primary.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                              if (hasCaps) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    if (caps.thinking)
                                      const _CardBadge('Think',
                                          Icons.auto_awesome, Color(0xFF9C6ADE)),
                                    if (caps.vision)
                                      const _CardBadge('Vision',
                                          Icons.visibility_rounded, Color(0xFF3D8BD4)),
                                    if (caps.tools)
                                      const _CardBadge('Tools',
                                          Icons.handyman_rounded, Color(0xFFCF8523)),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          iconSize: 20,
                          icon: Icon(Icons.close,
                              color: cs.onSurface.withValues(alpha: 0.55)),
                          onPressed: onClose,
                        ),
                      ],
                    ),
                  ),

                  // Description
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Text(
                      model.description.isNotEmpty
                          ? model.description
                          : _fallbackDescription(model),
                      style: TextStyle(
                          fontSize: 13.5,
                          height: 1.55,
                          color: cs.onSurfaceVariant),
                    ),
                  ),

                  // Specifications
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: Text(
                      'SPECIFICATIONS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.onSurface.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < specs.length; i++)
                            _SpecRow(
                              icon: specs[i].icon,
                              label: specs[i].label,
                              value: specs[i].value,
                              isLast: i == specs.length - 1,
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Digest
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Text(
                      model.digest.length > 16
                          ? 'sha256:${model.digest.substring(0, 12)}...'
                          : model.digest,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                      ),
                    ),
                  ),

                  // Select
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onSelect,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Select Model',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }
}

class _SpecRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isLast;
  const _SpecRow({
    required this.icon,
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(icon,
                  size: 15, color: cs.onSurfaceVariant.withValues(alpha: 0.45)),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
              const Spacer(),
              Text(value,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
            ],
          ),
        ),
        if (!isLast)
          Divider(height: 1, color: cs.onSurface.withValues(alpha: 0.05)),
      ],
    );
  }
}

class _CardBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _CardBadge(this.label, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                  letterSpacing: 0.1)),
        ],
      ),
    );
  }
}
