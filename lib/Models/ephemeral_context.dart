class EphemeralContext {
  static const int defaultTtlDays = 7;
  static const int maxTtlDays = 14;

  final int? id;
  final String contextKey;
  final String content;
  final String? sourceChatId;
  final DateTime createdAt;
  final DateTime expiresAt;

  EphemeralContext({
    this.id,
    required this.contextKey,
    required this.content,
    this.sourceChatId,
    DateTime? createdAt,
    DateTime? expiresAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        expiresAt = expiresAt ??
            (createdAt ?? DateTime.now()).add(const Duration(days: defaultTtlDays));

  factory EphemeralContext.withTtlDays({
    int? id,
    required String contextKey,
    required String content,
    String? sourceChatId,
    required int ttlDays,
  }) {
    final now = DateTime.now();
    final clampedDays = ttlDays.clamp(1, maxTtlDays);
    return EphemeralContext(
      id: id,
      contextKey: contextKey,
      content: content,
      sourceChatId: sourceChatId,
      createdAt: now,
      expiresAt: now.add(Duration(days: clampedDays)),
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  int get daysRemaining => expiresAt.difference(DateTime.now()).inDays;

  factory EphemeralContext.fromMap(Map<String, dynamic> map) {
    return EphemeralContext(
      id: map['id'] as int?,
      contextKey: map['context_key'] as String? ?? '',
      content: map['content'] as String? ?? '',
      sourceChatId: map['source_chat_id'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'])
          : DateTime.now(),
      expiresAt: map['expires_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['expires_at'])
          : DateTime.now().add(const Duration(days: defaultTtlDays)),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'context_key': contextKey,
      'content': content,
      'source_chat_id': sourceChatId,
      'created_at': createdAt.millisecondsSinceEpoch,
      'expires_at': expiresAt.millisecondsSinceEpoch,
    };
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'context_key': contextKey,
      'content': content,
      'source_chat_id': sourceChatId,
      'created_at': createdAt.millisecondsSinceEpoch,
      'expires_at': expiresAt.millisecondsSinceEpoch,
    };
  }

  int get estimatedTokens => ((contextKey.length + content.length) / 4).ceil();

  String toPromptEntry() => '- **[recent: $contextKey]**: $content';

  EphemeralContext copyWith({
    int? id,
    String? contextKey,
    String? content,
    String? sourceChatId,
    DateTime? expiresAt,
  }) {
    return EphemeralContext(
      id: id ?? this.id,
      contextKey: contextKey ?? this.contextKey,
      content: content ?? this.content,
      sourceChatId: sourceChatId ?? this.sourceChatId,
      createdAt: createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
