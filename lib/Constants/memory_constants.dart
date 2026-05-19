// lib/Constants/memory_constants.dart

class MemoryConstants {
  static const String defaultModel = 'gpt-oss-20b';

  static const int maxConversationMemoryTokens = 8000;
  static const int maxAgentMemoryTokens = 4000;
  static const int maxPerSectionTokens = 1500;
  static const int recentMessagesToKeep = 10;

  /// Estimates token count from text using chars/4 heuristic.
  static int estimateTokens(String text) => (text.length / 4).ceil();

  /// The summarization prompt sent to gpt-oss-20b.
  static String buildSummarizationPrompt({
    required String messagesText,
    String? existingConversationMemory,
    String? existingAgentMemory,
  }) {
    return '''You are a conversation memory manager. Analyze the conversation and update two memory structures.

IMPORTANT: Be concise. Conversation memory total must not exceed $maxConversationMemoryTokens tokens (~${maxConversationMemoryTokens * 4} characters). Agent memory total must not exceed $maxAgentMemoryTokens tokens (~${maxAgentMemoryTokens * 4} characters). Summarize, don't transcribe.

## Existing Conversation Memory:
${existingConversationMemory ?? 'None yet'}

## Existing Agent Memory:
${existingAgentMemory ?? 'None yet'}

## Conversation Messages:
$messagesText

---

Merge new information with existing memory. Don't discard prior context — update and extend it. Return a JSON object with exactly these keys:

{
  "conversation_memory": {
    "summary": "Main goal and what this conversation is about",
    "key_context": "Important facts, decisions, conclusions reached",
    "media_descriptions": "Textual descriptions of all images/files discussed",
    "current_state": "Where the conversation is at now",
    "model_history": "Which models were used and for what purpose",
    "unresolved_items": "Open questions, pending tasks"
  },
  "agent_memory": {
    "user_profile": "Name, role, background if mentioned",
    "preferences": "Communication style, response format preferences",
    "learned_facts": "Specific facts learned about the user",
    "interests_and_expertise": "Topics they discuss, domains of knowledge",
    "language_and_tone": "Primary language, formality level, verbosity preference"
  }
}

Return ONLY the JSON object, no other text.''';
  }

  /// Builds the memory injection block for the active model's system prompt.
  static String buildMemoryInjection({
    required String conversationMemoryBlock,
    required String agentMemoryBlock,
  }) {
    final parts = <String>[];

    if (conversationMemoryBlock.isNotEmpty) {
      parts.add('''
## Conversation Context
The following is a summary of earlier conversation history. Use it to maintain continuity.

$conversationMemoryBlock''');
    }

    if (agentMemoryBlock.isNotEmpty) {
      parts.add('''
## About This User
$agentMemoryBlock''');
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
