// lib/Constants/memory_constants.dart

class MemoryConstants {
  static const String defaultModel = 'gpt-oss:120b-cloud';

  static const int maxConversationMemoryTokens = 12000;
  static const int maxAgentMemoryTokens = 8000;
  static const int maxPerSectionTokens = 2000;
  static const int recentMessagesToKeep = 20;

  /// Estimates token count from text using chars/4 heuristic.
  static int estimateTokens(String text) => (text.length / 4).ceil();

  /// The summarization prompt sent to the cloud model.
  static String buildSummarizationPrompt({
    required String messagesText,
    String? existingConversationMemory,
    String? existingAgentMemory,
    List<String>? otherChatContexts,
  }) {
    final otherChatsBlock = otherChatContexts != null && otherChatContexts.isNotEmpty
        ? '\n\n## Context From Other Conversations:\nThese are memories from the user\'s other chat sessions. Extract any user-relevant information (preferences, facts, expertise, patterns) into agent memory. Do NOT merge these into the current conversation memory.\n${otherChatContexts.join('\n---\n')}'
        : '';

    return '''You are a comprehensive conversation memory manager. Your job is to create thorough, detailed memory that captures the FULL richness of conversations. Never lose important details.

## Guidelines:
- Conversation memory budget: up to $maxConversationMemoryTokens tokens (~${maxConversationMemoryTokens * 4} characters). Use as much as needed to be thorough.
- Agent memory budget: up to $maxAgentMemoryTokens tokens (~${maxAgentMemoryTokens * 4} characters). Build a rich, detailed user profile.
- Be COMPREHENSIVE — capture specifics, not just high-level summaries. Include names, numbers, technical details, exact preferences, specific examples, and concrete facts.
- Never discard prior context. Merge, extend, and enrich existing memory with new information.
- For agent memory: synthesize information from ALL conversations (current + other chats) to build the most complete user profile possible.

## Existing Conversation Memory:
${existingConversationMemory ?? 'None yet'}

## Existing Agent Memory:
${existingAgentMemory ?? 'None yet'}$otherChatsBlock

## Current Conversation Messages:
$messagesText

---

Return a JSON object with exactly these keys. Be detailed and thorough in every field:

{
  "conversation_memory": {
    "summary": "Detailed summary of what this conversation covers, its main goals, and key outcomes",
    "key_context": "All important facts, decisions, conclusions, technical details, code snippets discussed, specific solutions found",
    "user_requests": "What the user originally asked for, how the request evolved, what was delivered vs what was requested, any scope changes",
    "media_descriptions": "Detailed textual descriptions of all images, files, screenshots, or media discussed — describe content, not just existence",
    "current_state": "Exactly where the conversation stands now — what was just completed, what comes next",
    "errors_and_solutions": "Every error, bug, or problem encountered and exactly how it was resolved — so the same mistake is never repeated",
    "model_history": "Which AI models were used, what each was used for, how they performed, any model-specific observations",
    "unresolved_items": "All open questions, pending tasks, things to follow up on, known issues"
  },
  "agent_memory": {
    "user_profile": "Name, role, job title, background, team, company, timezone, any personal details shared across all conversations",
    "preferences": "Communication style, response format preferences, workflow habits, tool preferences, coding style, how they like to work",
    "learned_facts": "Every specific fact learned about the user across all conversations — projects they work on, technologies they use, problems they've solved, their environment/setup",
    "interests_and_expertise": "All topics discussed, domains of knowledge, skill levels in different areas, what they're learning, what they're expert in",
    "language_and_tone": "Primary language, formality level, verbosity preference, humor style, how they give feedback, communication patterns",
    "key_people": "People mentioned by the user across conversations — names, roles, relationships (coworkers, managers, friends, family), preferences and traits noted about them",
    "ongoing_projects": "Active projects, goals, deadlines the user is working toward — track progress and status across conversations",
    "past_conversation_refs": "Brief references to previous conversations — what topics were discussed, key outcomes, so the agent can naturally reference prior context (e.g. 'as we discussed when you were debugging X...')"
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
