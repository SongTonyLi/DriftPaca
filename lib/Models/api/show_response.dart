/// Response from POST /api/show
class ApiShowResponse {
  final String modelfile;
  final String parameters;
  final String template;
  final String description;
  final ApiShowModelDetails details;
  final Map<String, dynamic> modelInfo;
  final List<String> capabilities;

  ApiShowResponse({
    required this.modelfile,
    required this.parameters,
    required this.template,
    required this.description,
    required this.details,
    required this.modelInfo,
    required this.capabilities,
  });

  factory ApiShowResponse.fromJson(Map<String, dynamic> json) {
    final modelInfo = json['model_info'] as Map<String, dynamic>? ?? {};

    // Extract description: prefer explicit field, fall back to SYSTEM line in modelfile
    var description = (json['description'] as String?) ?? '';
    if (description.isEmpty) {
      final modelfile = (json['modelfile'] as String?) ?? '';
      final systemMatch = RegExp(r'^SYSTEM\s+"?(.+?)"?\s*$', multiLine: true)
          .firstMatch(modelfile);
      if (systemMatch != null) {
        description = systemMatch.group(1) ?? '';
        // Trim to first sentence for brevity
        final dotIdx = description.indexOf('. ');
        if (dotIdx > 0 && dotIdx < 200) {
          description = description.substring(0, dotIdx + 1);
        }
        if (description.length > 200) {
          description = '${description.substring(0, 197)}...';
        }
      }
    }

    return ApiShowResponse(
      modelfile: json['modelfile'] ?? '',
      parameters: json['parameters'] ?? '',
      template: json['template'] ?? '',
      description: description,
      details: ApiShowModelDetails.fromJson(json['details'] ?? {}),
      modelInfo: modelInfo,
      capabilities: json['capabilities'] != null
          ? List<String>.from(json['capabilities'])
          : [],
    );
  }

  /// Context length extracted from model_info, if available.
  int? get contextLength {
    for (final key in modelInfo.keys) {
      if (key.endsWith('.context_length')) {
        return modelInfo[key] as int?;
      }
    }
    return null;
  }
}

/// Model details from /api/show response
class ApiShowModelDetails {
  final String parentModel;
  final String format;
  final String family;
  final List<String>? families;
  final String parameterSize;
  final String quantizationLevel;

  ApiShowModelDetails({
    required this.parentModel,
    required this.format,
    required this.family,
    this.families,
    required this.parameterSize,
    required this.quantizationLevel,
  });

  factory ApiShowModelDetails.fromJson(Map<String, dynamic> json) {
    return ApiShowModelDetails(
      parentModel: json['parent_model'] ?? '',
      format: json['format'] ?? '',
      family: json['family'] ?? '',
      families: json['families'] != null ? List<String>.from(json['families']) : null,
      parameterSize: json['parameter_size'] ?? '',
      quantizationLevel: json['quantization_level'] ?? '',
    );
  }
}
