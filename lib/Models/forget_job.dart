class ForgetJob {
  final int id;

  /// Origin chat, stored for future per-chat scoping. The current drain scrubs
  /// global memory and does not read this — the scrub works off [removedText].
  final String? chatId;
  final String removedText;
  final DateTime createdAt;

  ForgetJob({
    required this.id,
    required this.chatId,
    required this.removedText,
    required this.createdAt,
  });

  factory ForgetJob.fromMap(Map<String, dynamic> map) {
    return ForgetJob(
      id: map['id'] as int,
      chatId: map['chat_id'] as String?,
      removedText: map['removed_text'] as String? ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
          : DateTime.now(),
    );
  }
}
