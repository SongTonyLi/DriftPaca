import 'package:llamaseek/Models/api/tags_response.dart';
import 'package:llamaseek/Models/api/show_response.dart';
import 'package:llamaseek/Models/model_capabilities.dart';

/// Domain model representing an Ollama model.
/// Combines data from /api/tags and optionally /api/show.
class OllamaModel {
  final String name;
  final String model;
  final DateTime modifiedAt;
  final int size;
  final String digest;
  final String parameterSize;
  final String family;
  final String quantizationLevel;
  final String format;
  final String description;
  final int? contextLength;
  final ModelCapabilities? capabilities;

  OllamaModel({
    required this.name,
    required this.model,
    required this.modifiedAt,
    required this.size,
    required this.digest,
    required this.parameterSize,
    this.family = '',
    this.quantizationLevel = '',
    this.format = '',
    this.description = '',
    this.contextLength,
    this.capabilities,
  });

  /// Creates an OllamaModel from /api/tags and optional /api/show response
  factory OllamaModel.from(ApiTagsModel tagsModel, ApiShowResponse? showResponse) {
    final show = showResponse?.details;
    final tags = tagsModel.details;
    return OllamaModel(
      name: tagsModel.name,
      model: tagsModel.model,
      modifiedAt: tagsModel.modifiedAt,
      size: tagsModel.size,
      digest: tagsModel.digest,
      parameterSize: _pickFormatted(show?.parameterSize, tags.parameterSize),
      family: (show?.family ?? '').isNotEmpty
          ? show!.family : tags.family,
      quantizationLevel: (show?.quantizationLevel ?? '').isNotEmpty
          ? show!.quantizationLevel : tags.quantizationLevel,
      format: (show?.format ?? '').isNotEmpty
          ? show!.format : tags.format,
      description: showResponse?.description ?? '',
      contextLength: showResponse?.contextLength,
      capabilities: showResponse != null ? ModelCapabilities.fromList(showResponse.capabilities) : null,
    );
  }

  /// For backward compatibility with existing JSON serialization
  factory OllamaModel.fromJson(Map<String, dynamic> json) => OllamaModel(
        name: json["name"],
        model: json["model"],
        modifiedAt: DateTime.parse(json["modified_at"]),
        size: json["size"],
        digest: json["digest"],
        parameterSize: json["details"]?["parameter_size"] ?? json["parameter_size"] ?? '',
        family: json["family"] ?? json["details"]?["family"] ?? '',
        quantizationLevel: json["quantization_level"] ?? json["details"]?["quantization_level"] ?? '',
        format: json["format"] ?? json["details"]?["format"] ?? '',
        description: json["description"] ?? '',
        contextLength: json["context_length"],
        capabilities: null,
      );

  Map<String, dynamic> toJson() => {
        "name": name,
        "model": model,
        "modified_at": modifiedAt.toIso8601String(),
        "size": size,
        "digest": digest,
        "parameter_size": parameterSize,
        "family": family,
        "quantization_level": quantizationLevel,
        "format": format,
        "description": description,
        if (contextLength != null) "context_length": contextLength,
      };

  /// Picks the human-readable value (e.g. "7B") over a raw numeric string.
  /// If both are raw numbers, formats to B/M units.
  static String _pickFormatted(String? a, String b) {
    // Prefer whichever already has a letter suffix (e.g. "7B")
    if (a != null && a.isNotEmpty && a.contains(RegExp(r'[a-zA-Z]'))) return a;
    if (b.isNotEmpty && b.contains(RegExp(r'[a-zA-Z]'))) return b;
    // Both are numeric — format the first available
    final raw = a ?? b;
    if (raw.isEmpty) return '';
    final n = num.tryParse(raw);
    if (n == null) return raw;
    if (n >= 1e12) return '${(n / 1e12).toStringAsFixed(1)}T';
    if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(n % 1e9 == 0 ? 0 : 1)}B';
    if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(n % 1e6 == 0 ? 0 : 1)}M';
    return raw;
  }

  @override
  String toString() {
    return name;
  }

  @override
  int get hashCode => digest.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is OllamaModel && other.digest == digest;
  }
}
