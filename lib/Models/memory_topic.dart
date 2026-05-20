class MemoryTopic {
  final int? id;
  final String topicKey;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  MemoryTopic({
    this.id,
    required this.topicKey,
    required this.content,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory MemoryTopic.fromMap(Map<String, dynamic> map) {
    return MemoryTopic(
      id: map['id'] as int?,
      topicKey: map['topic_key'] as String? ?? '',
      content: map['content'] as String? ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'])
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'topic_key': topicKey,
      'content': content,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'topic_key': topicKey,
      'content': content,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  int get estimatedTokens => ((topicKey.length + content.length) / 4).ceil();

  String toPromptEntry() => '- **[$topicKey]**: $content';

  MemoryTopic copyWith({
    int? id,
    String? topicKey,
    String? content,
  }) {
    return MemoryTopic(
      id: id ?? this.id,
      topicKey: topicKey ?? this.topicKey,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
