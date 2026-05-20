// lib/Constants/memory_constants.dart

import 'dart:convert';

class MemoryConstants {
  static const String defaultModel = 'gpt-oss:120b-cloud';

  static const int maxConversationMemoryTokens = 12000;
  static const int maxProfileTokens = 2000;
  static const int maxPerSectionTokens = 2000;
  static const int recentMessagesToKeep = 20;
  static const int recentMessagesForSelection = 5;

  /// Estimates token count from text using chars/4 heuristic.
  static int estimateTokens(String text) => (text.length / 4).ceil();

  /// The summarization prompt sent to the cloud model after each LLM response.
  static String buildSummarizationPrompt({
    required String messagesText,
    String? existingConversationMemory,
    String? existingProfile,
    List<Map<String, dynamic>>? existingTopics,
    List<Map<String, dynamic>>? existingEphemeral,
  }) {
    final topicsBlock = existingTopics != null && existingTopics.isNotEmpty
        ? existingTopics.map((t) => '- "${t['topic_key']}": ${t['content']}').join('\n')
        : 'No topics yet';

    final ephemeralBlock = existingEphemeral != null && existingEphemeral.isNotEmpty
        ? existingEphemeral.map((e) => '- "${e['context_key']}": ${e['content']}').join('\n')
        : 'No ephemeral context yet';

    return '''You are a memory manager for a chat application. Analyze the conversation and update structured memory.

## Rules:
- **Profile updates**: Only update profile fields when you have HIGH confidence. Profile stores stable, universal traits (name, language, communication style). Do NOT infer profile traits from a single conversation topic. A user discussing physics homework does NOT mean their role is "physics student" unless they explicitly say so.
  - Confidence levels: "high" = user explicitly stated it or it\'s been consistent across context. "medium" = reasonable inference but not confirmed. "low" = speculation.
  - Only "high" confidence updates will be applied. Be conservative.
- **Topic updates**: Create, update, or merge topic entries. Topics are domain-specific knowledge (e.g., "Flutter development", "quantum mechanics homework"). Use descriptive but general keys. Merge similar topics when they overlap.
  - Actions: "create" (new topic), "update" (modify existing topic content), "merge" (combine two topics — specify "from" and "into")
- **Ephemeral updates**: Short-lived context about what the user is currently doing. Things like "debugging a crash" or "writing an essay". Default TTL: 7 days, max: 14 days.
- **Conversation memory**: Detailed summary of THIS conversation only.

## Existing Stable Profile:
${existingProfile ?? 'None yet'}

## Existing Topics:
$topicsBlock

## Existing Ephemeral Context:
$ephemeralBlock

## Existing Conversation Memory:
${existingConversationMemory ?? 'None yet'}

## Current Conversation Messages:
$messagesText

---

Return a JSON object with exactly this structure:

{
  "conversation_memory": {
    "summary": "Detailed summary of this conversation",
    "key_context": "Important facts, decisions, technical details",
    "user_requests": "What the user asked for and how it evolved",
    "media_descriptions": "Descriptions of images/files discussed",
    "current_state": "Where the conversation stands now",
    "errors_and_solutions": "Problems encountered and how they were resolved",
    "model_history": "Which models were used and how they performed",
    "unresolved_items": "Open questions or pending tasks"
  },
  "profile_updates": {
    "name": { "value": "string or null if no update", "confidence": "high|medium|low" },
    "primary_language": { "value": "string or null", "confidence": "high|medium|low" },
    "tone_and_formality": { "value": "string or null", "confidence": "high|medium|low" },
    "role_and_background": { "value": "string or null", "confidence": "high|medium|low" },
    "communication_style": { "value": "string or null", "confidence": "high|medium|low" }
  },
  "topic_updates": [
    { "action": "create|update|merge", "key": "topic key", "content": "topic content", "from": "only for merge" }
  ],
  "ephemeral_updates": [
    { "action": "create", "key": "context key", "content": "context content", "ttl_days": 7 }
  ]
}

Return ONLY the JSON object, no other text.''';
  }

  /// Prompt for the lightweight topic selection call before each message.
  static String buildSelectionPrompt({
    required String recentMessagesText,
    String? conversationSummary,
    required List<String> topicKeys,
    required List<String> ephemeralKeys,
  }) {
    final allKeys = [...topicKeys, ...ephemeralKeys];
    final keysBlock = allKeys.map((k) => '- "$k"').join('\n');

    final summaryBlock = conversationSummary != null && conversationSummary.isNotEmpty
        ? '\n\n## Conversation Summary:\n$conversationSummary'
        : '';

    return '''You are a relevance filter. Given recent chat messages and a list of memory topic keys, return ONLY the keys that are relevant to the current conversation.

## Recent Messages:
$recentMessagesText$summaryBlock

## Available Memory Keys:
$keysBlock

---

Return a JSON object with exactly this structure:
{
  "relevant_keys": ["key1", "key2"]
}

Rules:
- Only include keys whose content would genuinely help answer the current conversation
- When in doubt, exclude — it\'s better to miss a marginally relevant topic than to inject irrelevant context
- Return an empty array if nothing is relevant

Return ONLY the JSON object, no other text.''';
  }

  /// Builds the memory injection block for the active model's system prompt.
  static String buildMemoryInjection({
    required String profileBlock,
    required String relevantContextBlock,
    required String conversationMemoryBlock,
  }) {
    final parts = <String>[];

    if (profileBlock.isNotEmpty) {
      parts.add('''## About This User
$profileBlock''');
    }

    if (relevantContextBlock.isNotEmpty) {
      parts.add('''## Relevant Context
$relevantContextBlock''');
    }

    if (conversationMemoryBlock.isNotEmpty) {
      parts.add('''## Conversation Context
The following is a summary of earlier conversation history. Use it to maintain continuity.

$conversationMemoryBlock''');
    }

    if (parts.isNotEmpty) {
      parts.add(
        'If images were described in the conversation memory but are not visible in recent messages, use the textual descriptions provided. Recent messages follow below for full detail.',
      );
    }

    return parts.join('\n\n');
  }

  /// Prompt for resummarizing memory that exceeds token limits.
  static String buildResummarizationPrompt(String memoryContent, int tokenLimit) {
    return '''The following memory content exceeds the allowed size (~$tokenLimit tokens / ~${tokenLimit * 4} characters). Condense it while preserving all key information. Return the condensed text only, no explanation.

$memoryContent''';
  }
}
