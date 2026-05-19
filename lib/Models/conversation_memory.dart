import 'dart:convert';

class ConversationMemory {
  final String summary;
  final String keyContext;
  final String mediaDescriptions;
  final String currentState;
  final String modelHistory;
  final String unresolvedItems;
  final String errorsAndSolutions;
  final String userRequests;
  final DateTime updatedAt;

  ConversationMemory({
    this.summary = '',
    this.keyContext = '',
    this.mediaDescriptions = '',
    this.currentState = '',
    this.modelHistory = '',
    this.unresolvedItems = '',
    this.errorsAndSolutions = '',
    this.userRequests = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  bool get isEmpty =>
      summary.isEmpty &&
      keyContext.isEmpty &&
      mediaDescriptions.isEmpty &&
      currentState.isEmpty &&
      modelHistory.isEmpty &&
      unresolvedItems.isEmpty &&
      errorsAndSolutions.isEmpty &&
      userRequests.isEmpty;

  factory ConversationMemory.fromJson(String jsonString) {
    try {
      final map = jsonDecode(jsonString) as Map<String, dynamic>;
      return ConversationMemory.fromMap(map);
    } catch (_) {
      return ConversationMemory(summary: jsonString);
    }
  }

  /// Converts a value that may be a String, List, or null to a String.
  static String _asString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is List) return value.join('\n');
    return value.toString();
  }

  factory ConversationMemory.fromMap(Map<String, dynamic> map) {
    return ConversationMemory(
      summary: _asString(map['summary']),
      keyContext: _asString(map['key_context']),
      mediaDescriptions: _asString(map['media_descriptions']),
      currentState: _asString(map['current_state']),
      modelHistory: _asString(map['model_history']),
      unresolvedItems: _asString(map['unresolved_items']),
      errorsAndSolutions: _asString(map['errors_and_solutions']),
      userRequests: _asString(map['user_requests']),
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'])
          : null,
    );
  }

  String toJson() {
    return jsonEncode({
      'summary': summary,
      'key_context': keyContext,
      'media_descriptions': mediaDescriptions,
      'current_state': currentState,
      'model_history': modelHistory,
      'unresolved_items': unresolvedItems,
      'errors_and_solutions': errorsAndSolutions,
      'user_requests': userRequests,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    });
  }

  ConversationMemory copyWith({
    String? summary,
    String? keyContext,
    String? mediaDescriptions,
    String? currentState,
    String? modelHistory,
    String? unresolvedItems,
    String? errorsAndSolutions,
    String? userRequests,
  }) {
    return ConversationMemory(
      summary: summary ?? this.summary,
      keyContext: keyContext ?? this.keyContext,
      mediaDescriptions: mediaDescriptions ?? this.mediaDescriptions,
      currentState: currentState ?? this.currentState,
      modelHistory: modelHistory ?? this.modelHistory,
      unresolvedItems: unresolvedItems ?? this.unresolvedItems,
      errorsAndSolutions: errorsAndSolutions ?? this.errorsAndSolutions,
      userRequests: userRequests ?? this.userRequests,
    );
  }

  int get estimatedTokens {
    final total = summary.length +
        keyContext.length +
        mediaDescriptions.length +
        currentState.length +
        modelHistory.length +
        unresolvedItems.length +
        errorsAndSolutions.length +
        userRequests.length;
    return (total / 4).ceil();
  }

  String toPromptBlock() {
    final sections = <String>[];
    if (summary.isNotEmpty) sections.add('- **Summary**: $summary');
    if (keyContext.isNotEmpty) sections.add('- **Key Context**: $keyContext');
    if (userRequests.isNotEmpty) sections.add('- **User Requests**: $userRequests');
    if (mediaDescriptions.isNotEmpty) sections.add('- **Media Descriptions**: $mediaDescriptions');
    if (currentState.isNotEmpty) sections.add('- **Current State**: $currentState');
    if (errorsAndSolutions.isNotEmpty) sections.add('- **Errors & Solutions**: $errorsAndSolutions');
    if (modelHistory.isNotEmpty) sections.add('- **Model History**: $modelHistory');
    if (unresolvedItems.isNotEmpty) sections.add('- **Unresolved Items**: $unresolvedItems');
    return sections.join('\n');
  }
}
