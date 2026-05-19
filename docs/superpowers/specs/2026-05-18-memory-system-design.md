# Memory System Design — LlamaSeek

**Date:** 2026-05-18
**Goal:** Smooth multi-turn conversations that are personal across sessions using different models.

---

## Problem

When users switch models mid-conversation (e.g., Kimi → DeepSeek), the new model loses context — especially for capabilities the new model lacks (e.g., images sent to a text-only model). Conversations also lack personalization across sessions. There is no mechanism to carry context beyond raw message history.

## Solution Overview

Two memory types, both generated asynchronously by a dedicated summarization model (`gpt-oss-20b` via Ollama Cloud):

1. **Conversation Memory** — per-chat, tracks the flow and state of a conversation
2. **Agent Memory** — global, tracks learned information about the user across all chats

Memories are injected into the system prompt alongside the last 10 raw messages, giving the active model both high-level context and recent detail.

---

## 1. Data Models

### ConversationMemory (per-chat, 6 sections)

| Section | Purpose |
|---|---|
| `summary` | Main goal and what the conversation is about |
| `keyContext` | Important facts, decisions, conclusions reached |
| `mediaDescriptions` | Textual descriptions of all images/files discussed |
| `currentState` | Where the conversation is at now |
| `modelHistory` | Which models were used and for what purpose |
| `unresolvedItems` | Open questions, pending tasks |

### AgentMemory (global, 5 sections)

| Section | Purpose |
|---|---|
| `userProfile` | Name, role, occupation, background |
| `preferences` | Communication style, response format preferences |
| `learnedFacts` | Specific facts learned about the user across chats |
| `interestsAndExpertise` | Topics they discuss, domains of knowledge |
| `languageAndTone` | Primary language, formality level, verbosity preference |

---

## 2. Storage (Database Migration v4)

```sql
-- Conversation memory stored as JSON column in existing chats table
ALTER TABLE chats ADD COLUMN conversation_memory TEXT;

-- Agent memory as a standalone global table
CREATE TABLE agent_memory (
  id INTEGER PRIMARY KEY DEFAULT 1,
  user_profile TEXT DEFAULT '',
  preferences TEXT DEFAULT '',
  learned_facts TEXT DEFAULT '',
  interests_and_expertise TEXT DEFAULT '',
  language_and_tone TEXT DEFAULT '',
  updated_at DATETIME
);
```

Conversation memory is deleted with the chat (existing CASCADE behavior). Agent memory persists until user explicitly clears it.

---

## 3. Token Budgets

| Memory Type | Per Section Max | Total Max |
|---|---|---|
| Conversation Memory | ~1,500 tokens | ~8,000 tokens |
| Agent Memory | ~1,000 tokens | ~4,000 tokens |

- Combined ~12,000 tokens in system prompt — manageable for any model's context window
- Token estimation: `content.length / 4` (rough heuristic)
- Sections that are naturally short leave budget for denser sections
- The summarization prompt enforces these limits

---

## 4. MemoryService Architecture

New `MemoryService` class, separate from ChatProvider.

```dart
class MemoryService extends ChangeNotifier {
  final DatabaseService _db;
  final http.Client _httpClient;

  static const String _cloudBaseUrl = 'https://ollama.com';
  String _model = 'gpt-oss-20b'; // configurable in settings

  String? _apiKey;           // Read from Hive settings (cloud API key)
  bool _isUpdating = false;  // Drives the status indicator

  // Read current memories (for prompt injection)
  Future<ConversationMemory?> getConversationMemory(String chatId);
  Future<AgentMemory?> getAgentMemory();

  // Fire-and-forget async update
  void triggerMemoryUpdate({
    required String chatId,
    required List<OllamaMessage> messages,
  });

  // Management
  Future<void> deleteConversationMemory(String chatId);
  Future<void> clearAgentMemory();
  Future<void> updateConversationMemoryField(String chatId, String field, String value);
  Future<void> updateAgentMemoryField(String field, String value);
  
  // Resummarize when user edits exceed token limits
  Future<void> resummarizeMemory(String type, {String? chatId});
}
```

### Key Design Decisions

- **Own HTTP client** — always calls Ollama Cloud regardless of user's server mode
- **Concurrency guard** — `_isUpdating` prevents overlapping updates. If a new turn completes while update is in-flight, next turn captures latest state
- **Graceful degradation** — no API key → memory features silently disabled. API failure → log and move on
- **Resilient parsing** — try JSON parse → structured sections. If parse fails → store raw text as-is. Consuming model reads natural language either way

---

## 5. Summarization Prompt (sent to gpt-oss-20b)

```
You are a conversation memory manager. Analyze the conversation and update two memory structures.

IMPORTANT: Each section must be concise. Conversation memory total must not exceed 8,000 tokens. Agent memory total must not exceed 4,000 tokens. Summarize, don't transcribe.

## Existing Conversation Memory:
{existing_conversation_memory_json or "None yet"}

## Existing Agent Memory:
{existing_agent_memory_json or "None yet"}

## Conversation Messages:
{all messages with role + content, images described as "[User sent an image]"}

---

Merge new information with existing memory. Don't discard prior context — update and extend it. Return a JSON object:

{
  "conversation_memory": {
    "summary": "...",
    "key_context": "...",
    "media_descriptions": "...",
    "current_state": "...",
    "model_history": "...",
    "unresolved_items": "..."
  },
  "agent_memory": {
    "user_profile": "...",
    "preferences": "...",
    "learned_facts": "...",
    "interests_and_expertise": "...",
    "language_and_tone": "..."
  }
}
```

---

## 6. System Prompt Injection (to the active model)

```
{user's custom system prompt, if any}

## Conversation Context
The following is a summary of earlier conversation history. Use it to maintain continuity.

- **Summary**: {summary}
- **Key Context**: {key_context}
- **Media Descriptions**: {media_descriptions}
- **Current State**: {current_state}
- **Model History**: {model_history}
- **Unresolved Items**: {unresolved_items}

## About This User
- **Profile**: {user_profile}
- **Preferences**: {preferences}
- **Interests & Expertise**: {interests_and_expertise}
- **Language & Tone**: {language_and_tone}

If images were described in the conversation memory but are not visible in recent messages, use the textual descriptions provided. Recent messages follow below for full detail.
```

Followed by the **last 10 raw messages** (images stripped if model lacks vision).

If no memory exists (first messages, no API key), skip memory injection and send all messages as-is (backward compatible).

---

## 7. Integration with Chat Flow

```
User sends message (or edits+resends)
  → ChatProvider.displayUserMessage()
  → ChatProvider.sendPrompt()
      → memoryService.getConversationMemory(chatId)    // read current (may be stale, OK)
      → memoryService.getAgentMemory()
      → OllamaService builds system prompt with memory injection
      → Send last 10 messages to active model
      → Stream response
      → Response complete
      → memoryService.triggerMemoryUpdate(chatId, messages)  // fire-and-forget
      → Star starts glowing
      → Background: call gpt-oss-20b, parse, save to DB
      → Star stops glowing
```

### Trigger Points (all fire-and-forget)

- `sendPrompt` completes
- `regenerateMessage` completes
- Edit+resend completes

---

## 8. Summarization Status Indicator

- Small star icon near the chat input area
- **Glowing/pulsing animation** = `gpt-oss-20b` is actively summarizing
- **Static/dim** = idle, memories are current
- Driven by `MemoryService.isUpdating` via `ChangeNotifier`

---

## 9. UI — Memory Viewer/Editor

### Conversation Memory (per-chat, in sidebar)

- Long-press chat in sidebar → context menu now has **"Memory"** option (alongside Rename, Delete)
- Opens a page/bottom sheet showing the 6 sections, each editable
- NOT accessible during active conversation — only from sidebar
- On save: check token count. If over limit → warning dialog:
  - "Memory exceeds the allowed size. Please reduce the content, or it will be automatically resummarized to fit."
  - [Reduce Manually] / [Auto-Resummarize]
  - Auto-Resummarize fires gpt-oss-20b to condense

### Agent Memory (global, in sidebar)

- New tile at bottom of sidebar, above Settings: **"Agent Memory"**
- Opens a page/bottom sheet showing the 5 sections, each editable
- Same token overflow behavior as conversation memory

### Summarization Model Setting

- In Settings page: new "Memory Model" option
- Defaults to `gpt-oss-20b`
- Uses the existing Ollama Cloud API key

---

## 10. Edit+Resend Bug Fix

**Current behavior:** User edits a mid-conversation message → original is updated in-place → all messages after it are deleted → model re-responds.

**New behavior:** User edits a mid-conversation message → original message stays unchanged → edited text is added as a **new user message at the bottom** → all existing messages preserved → model responds to the new message → memory update fires.

---

## 11. Edge Cases

| Scenario | Behavior |
|---|---|
| No cloud API key | Memory features silently disabled, app works as before |
| gpt-oss-20b call fails | Log error, move on. Chat functions normally without memory |
| First messages of new chat | No memory exists yet. Send all messages, no memory injection |
| Chat deletion | Conversation memory deleted with chat (CASCADE) |
| Model switch mid-chat | Memory block includes model_history. Images stripped for text-only models. Media descriptions provide textual fallback |
| Concurrent turns while summarizing | In-flight update finishes. Next turn uses whatever memory is available |
| User edits memory beyond token limit | Warning + auto-resummarize option |
