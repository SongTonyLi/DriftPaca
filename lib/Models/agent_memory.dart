import 'dart:convert';

class AgentMemory {
  final String name;
  final String primaryLanguage;
  final String toneAndFormality;
  final String roleAndBackground;
  final String communicationStyle;
  final DateTime updatedAt;

  AgentMemory({
    this.name = '',
    this.primaryLanguage = '',
    this.toneAndFormality = '',
    this.roleAndBackground = '',
    this.communicationStyle = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  bool get isEmpty =>
      name.isEmpty &&
      primaryLanguage.isEmpty &&
      toneAndFormality.isEmpty &&
      roleAndBackground.isEmpty &&
      communicationStyle.isEmpty;

  static String _asString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is List) return value.join('\n');
    return value.toString();
  }

  factory AgentMemory.fromMap(Map<String, dynamic> map) {
    return AgentMemory(
      name: _asString(map['name']),
      primaryLanguage: _asString(map['primary_language']),
      toneAndFormality: _asString(map['tone_and_formality']),
      roleAndBackground: _asString(map['role_and_background']),
      communicationStyle: _asString(map['communication_style']),
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'primary_language': primaryLanguage,
      'tone_and_formality': toneAndFormality,
      'role_and_background': roleAndBackground,
      'communication_style': communicationStyle,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  AgentMemory copyWith({
    String? name,
    String? primaryLanguage,
    String? toneAndFormality,
    String? roleAndBackground,
    String? communicationStyle,
  }) {
    return AgentMemory(
      name: name ?? this.name,
      primaryLanguage: primaryLanguage ?? this.primaryLanguage,
      toneAndFormality: toneAndFormality ?? this.toneAndFormality,
      roleAndBackground: roleAndBackground ?? this.roleAndBackground,
      communicationStyle: communicationStyle ?? this.communicationStyle,
    );
  }

  int get estimatedTokens {
    final total = name.length +
        primaryLanguage.length +
        toneAndFormality.length +
        roleAndBackground.length +
        communicationStyle.length;
    return (total / 4).ceil();
  }

  String toPromptBlock() {
    final sections = <String>[];
    final now = DateTime.now();
    sections.add('- **System Info**: Current time: ${now.toString().split('.').first} (${now.timeZoneName})');
    if (name.isNotEmpty) sections.add('- **Name**: $name');
    if (primaryLanguage.isNotEmpty) sections.add('- **Language**: $primaryLanguage');
    if (toneAndFormality.isNotEmpty) sections.add('- **Tone & Formality**: $toneAndFormality');
    if (roleAndBackground.isNotEmpty) sections.add('- **Role & Background**: $roleAndBackground');
    if (communicationStyle.isNotEmpty) sections.add('- **Communication Style**: $communicationStyle');
    return sections.join('\n');
  }
}
