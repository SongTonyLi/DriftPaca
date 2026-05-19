import 'dart:convert';

class AgentMemory {
  final String userProfile;
  final String preferences;
  final String learnedFacts;
  final String interestsAndExpertise;
  final String languageAndTone;
  final String keyPeople;
  final String ongoingProjects;
  final String pastConversationRefs;
  final DateTime updatedAt;

  AgentMemory({
    this.userProfile = '',
    this.preferences = '',
    this.learnedFacts = '',
    this.interestsAndExpertise = '',
    this.languageAndTone = '',
    this.keyPeople = '',
    this.ongoingProjects = '',
    this.pastConversationRefs = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  bool get isEmpty =>
      userProfile.isEmpty &&
      preferences.isEmpty &&
      learnedFacts.isEmpty &&
      interestsAndExpertise.isEmpty &&
      languageAndTone.isEmpty &&
      keyPeople.isEmpty &&
      ongoingProjects.isEmpty &&
      pastConversationRefs.isEmpty;

  /// Converts a value that may be a String, List, or null to a String.
  static String _asString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is List) return value.join('\n');
    return value.toString();
  }

  factory AgentMemory.fromMap(Map<String, dynamic> map) {
    return AgentMemory(
      userProfile: _asString(map['user_profile']),
      preferences: _asString(map['preferences']),
      learnedFacts: _asString(map['learned_facts']),
      interestsAndExpertise: _asString(map['interests_and_expertise']),
      languageAndTone: _asString(map['language_and_tone']),
      keyPeople: _asString(map['key_people']),
      ongoingProjects: _asString(map['ongoing_projects']),
      pastConversationRefs: _asString(map['past_conversation_refs']),
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_profile': userProfile,
      'preferences': preferences,
      'learned_facts': learnedFacts,
      'interests_and_expertise': interestsAndExpertise,
      'language_and_tone': languageAndTone,
      'key_people': keyPeople,
      'ongoing_projects': ongoingProjects,
      'past_conversation_refs': pastConversationRefs,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  AgentMemory copyWith({
    String? userProfile,
    String? preferences,
    String? learnedFacts,
    String? interestsAndExpertise,
    String? languageAndTone,
    String? keyPeople,
    String? ongoingProjects,
    String? pastConversationRefs,
  }) {
    return AgentMemory(
      userProfile: userProfile ?? this.userProfile,
      preferences: preferences ?? this.preferences,
      learnedFacts: learnedFacts ?? this.learnedFacts,
      interestsAndExpertise: interestsAndExpertise ?? this.interestsAndExpertise,
      languageAndTone: languageAndTone ?? this.languageAndTone,
      keyPeople: keyPeople ?? this.keyPeople,
      ongoingProjects: ongoingProjects ?? this.ongoingProjects,
      pastConversationRefs: pastConversationRefs ?? this.pastConversationRefs,
    );
  }

  int get estimatedTokens {
    final total = userProfile.length +
        preferences.length +
        learnedFacts.length +
        interestsAndExpertise.length +
        languageAndTone.length +
        keyPeople.length +
        ongoingProjects.length +
        pastConversationRefs.length;
    return (total / 4).ceil();
  }

  String toPromptBlock() {
    final sections = <String>[];
    // System-managed: always reflects current time, not stored or editable
    final now = DateTime.now();
    sections.add('- **System Info**: Current time: ${now.toString().split('.').first} (${now.timeZoneName})');
    if (userProfile.isNotEmpty) sections.add('- **Profile**: $userProfile');
    if (preferences.isNotEmpty) sections.add('- **Preferences**: $preferences');
    if (learnedFacts.isNotEmpty) sections.add('- **Learned Facts**: $learnedFacts');
    if (interestsAndExpertise.isNotEmpty) sections.add('- **Interests & Expertise**: $interestsAndExpertise');
    if (languageAndTone.isNotEmpty) sections.add('- **Language & Tone**: $languageAndTone');
    if (keyPeople.isNotEmpty) sections.add('- **Key People**: $keyPeople');
    if (ongoingProjects.isNotEmpty) sections.add('- **Ongoing Projects & Goals**: $ongoingProjects');
    if (pastConversationRefs.isNotEmpty) sections.add('- **Past Conversations**: $pastConversationRefs');
    return sections.join('\n');
  }
}
