# LlamaSeek

Demo:

https://github.com/user-attachments/assets/f3e96b36-12ca-4aac-8e4a-7b1f0285a692


A beautiful, open-source AI chat client for [Ollama](https://ollama.com) with a modern glass-inspired UI.

## Features

- **Glass UI** -- frosted glass effects on the sidebar, prompt bar, and bottom sheets
- **Thinking visualization** -- pulsing sparkle animation while models reason, with duration tracking
- **Floating prompt bar** -- translucent, always-accessible input with backdrop blur
- **Compact chat layout** -- clean message bubbles with inline Copy and Regenerate actions
- **Sidebar with context menu** -- long-press any chat to rename or delete with an animated glass popup
- **Multi-model support** -- local Ollama or Ollama Cloud, switch models per conversation
- **Per-chat configuration** -- system prompts, temperature, and advanced options per conversation
- **Cross-platform** -- iOS, Android, macOS, Linux, Windows

## Getting Started

### Prerequisites

- [Flutter](https://flutter.dev/docs/get-started/install) 3.x+
- [Ollama](https://ollama.com) Ollama Cloud API key

### Run

```bash
git clone https://github.com/SongTonyLi/LlamaSeek.git
cd LlamaSeek
flutter pub get
flutter run
```

### iOS

```bash
# List connected devices to find your device ID
flutter devices

# Simulator
flutter run -d <simulator-id>

# Physical device (release build required)
flutter build ios --release
flutter install -d <device-id>
```

## Agent Memory

LlamaSeek uses a three-tier memory architecture to personalize conversations without cross-chat contamination.

```
                          +------------------+
                          |   User Message   |
                          +--------+---------+
                                   |
                    +--------------v---------------+
                    |  1. TOPIC SELECTION (pre-msg) |
                    |  Lightweight LLM call picks   |
                    |  relevant keys from Tier 2+3  |
                    +--------------+---------------+
                                   |
                    +--------------v---------------+
                    |    BUILD SYSTEM PROMPT        |
                    |                               |
                    |  +-------------------------+  |
                    |  | System Info (runtime)    |  |  <-- always injected
                    |  | Current time, timezone   |  |
                    |  +-------------------------+  |
                    |  | Tier 1: Stable Profile   |  |  <-- always injected
                    |  | Name, language, tone,    |  |
                    |  | role, communication style|  |
                    |  +-------------------------+  |
                    |  | Tier 2+3: Selected Only  |  |  <-- selectively injected
                    |  | [topic: Flutter dev] ... |  |
                    |  | [recent: debugging] ...  |  |
                    |  +-------------------------+  |
                    |  | Conversation Memory      |  |  <-- always (per-chat)
                    |  | Summary, key context ... |  |
                    |  +-------------------------+  |
                    +--------------+---------------+
                                   |
                    +--------------v---------------+
                    |       LLM RESPONSE            |
                    +--------------+---------------+
                                   |
                    +--------------v---------------+
                    |  2. MEMORY UPDATE (post-msg)  |
                    |  Fire-and-forget LLM call     |
                    +--------------+---------------+
                                   |
              +--------------------+--------------------+
              |                    |                     |
   +----------v----------+ +------v-------+ +-----------v-----------+
   | Tier 1: Profile     | | Tier 2: Topics | | Tier 3: Ephemeral   |
   | HIGH confidence only| | Create/Update/ | | Auto-expires (TTL)  |
   | Name, language,     | | Merge organic  | | "debugging crash",  |
   | tone, role, style   | | topic entries   | | "writing essay"     |
   +---------------------+ +----------------+ +-----------------------+
              |                    |                     |
              +--------------------+---------------------+
                                   |
                            +------v------+
                            |   SQLite DB  |
                            +-------------+
```

**Anti-contamination guarantees:**
- Profile only updates on high-confidence, stable observations
- Topic-specific knowledge is scoped and selectively injected per-conversation
- Ephemeral context auto-expires after 7-14 days
- If topic selection fails, only safe universal profile is injected
- Incognito chats skip agent memory entirely

## Architecture

```
lib/
  Constants/     App constants and config
  Extensions/    Dart extensions (markdown styling)
  Models/        Data models (chat, message, model)
  Pages/         Main pages (chat, settings)
  Providers/     State management (Provider)
  Services/      Business logic (database, API, web search)
  Utils/         Utilities (scroll physics, size observer)
  Widgets/       Reusable widgets (drawer, app bar, bottom sheets)
```

## Built With

- **Flutter** + **Provider** for state management
- **SQLite** for local chat persistence
- **Ollama API** for model inference
- **flutter_markdown** + **LaTeX** for rich content rendering

## License

This project is open source. See [LICENSE](LICENSE) for details.

## Acknowledgments

Originally forked from [Reins](https://github.com/ibrahimcetin/reins) by Ibrahim Cetin.
