# Privacy Policy

**Last updated: May 20, 2026**

## Overview

DriftPaca is an open-source AI chat client. Your privacy is important to us. This policy explains what data DriftPaca handles and how.

## Data Collection

DriftPaca does **not** collect, store, or transmit any personal data to us or any third parties. We have no servers, no analytics, and no tracking.

## Data Storage

All data — including chat history, settings, and preferences — is stored **locally on your device** in a private **SQLite database** (via the `sqflite` library) and a small key-value store. Nothing leaves your device unless you explicitly connect to a server or enable features described below.

### Where the database lives

The database file is placed in the operating system's standard per-application private directory, which is sandboxed from other apps:

- **iOS / iPadOS** — the app's `Documents` container (covered by iOS Data Protection)
- **Android** — the app's internal storage / databases directory
- **macOS** — the app's Application Support / Documents container
- **Windows** — the app's local AppData directory
- **Linux** — the app's Application Support directory

DriftPaca never writes chat data to shared locations, iCloud, Google Drive, or any cloud backup that DriftPaca itself controls. Platform-level backups (such as iCloud Backup or Android Auto Backup) may still capture the app's sandbox if you have those enabled in your OS settings.

### What is stored in the database

The SQLite database contains the following tables:

- `chats` — chat id, title, selected model, system prompt, advanced options, per-chat conversation memory, incognito flag
- `messages` — message id, content, model "thinking" trace, image references, role (user/assistant/system), timestamp; deleting a chat cascade-deletes its messages
- `agent_memory` — Tier 1 stable profile (name, primary language, tone, role, communication style)
- `agent_memory_topics` — Tier 2 topic-scoped knowledge entries
- `agent_memory_ephemeral` — Tier 3 short-lived context with an automatic expiry timestamp
- `cleanup_jobs` — queue of image files to be deleted after their owning messages are removed

Attached images are stored as files under the app's private documents directory and referenced by relative path from the `messages` table. Deleting a chat or message removes both the database row and the underlying image files.

### Encryption at rest

DriftPaca does not apply application-level encryption (such as SQLCipher) to the database file. The database is protected by:

1. The operating system's **app sandbox**, which prevents other apps from reading DriftPaca's files
2. The operating system's **device disk encryption** — iOS Data Protection, Android File-Based Encryption, macOS FileVault (when enabled), Windows BitLocker (when enabled), or your Linux disk-encryption scheme

For maximum protection, keep your device's screen lock and full-disk encryption turned on.

### Incognito chats and deletion

Chats started in **Incognito** mode are flagged with `is_incognito = 1` and are excluded from agent memory aggregation, so nothing from them flows into your stable profile, topic store, or ephemeral context. Deleting a chat or clearing memory permanently removes the corresponding rows; if you uninstall DriftPaca, your OS will delete the app's entire sandbox, including the database.

## Network Communication

DriftPaca may communicate with the following services based on your configuration:

### Ollama Server (Local or Cloud)

When you configure a local Ollama server or enter an Ollama Cloud API key, your **chat messages, system prompts, and conversation history** are sent to that server for AI processing. DriftPaca does not intercept, log, or have access to any of these communications. You are responsible for the privacy practices of the Ollama server you connect to.

- **Local mode**: Data is sent to the server address you provide (e.g., your own machine).
- **Cloud mode**: Data is sent to Ollama Cloud (ollama.com) using your API key.

### Memory Feature

If you enable the memory feature, **conversation summaries and profile data** (such as name, language, and communication preferences) are sent to Ollama Cloud for summarization. This data is used to personalize your conversations. Memory data is stored locally on your device and only transmitted when summarization is needed.

### Web Search (DuckDuckGo)

When you enable web search for a conversation, your **search queries** are sent to DuckDuckGo (duckduckgo.com) to retrieve relevant results. DriftPaca then fetches content from the returned web pages to provide context for AI responses. Web search is disabled by default and only activates when you explicitly enable it.

## Transport Security

All connections from DriftPaca to remote services are encrypted with **TLS (HTTPS)**:

- **Ollama Cloud** (`https://ollama.com`) — chat, model listing, and memory summarization traffic
- **DuckDuckGo** (`https://html.duckduckgo.com`) — web search queries
- **Fetched web pages** — TLS is used whenever the source page is served over HTTPS

DriftPaca keeps a persistent HTTPS connection per service so the TLS session is reused across requests, reducing handshake overhead without weakening encryption. Certificate validation is performed by the operating system's standard trust store.

A **local Ollama** server is reached over plain HTTP at `http://localhost:11434` because the traffic never leaves your machine. If you point DriftPaca at a remote Ollama server, configure it with an HTTPS URL to keep that traffic encrypted.

## Third-Party Services

DriftPaca does not integrate any analytics, advertising, or tracking services. The only third-party services used are:

- **Ollama** (ollama.com) — for AI model inference, only when you configure it
- **DuckDuckGo** (duckduckgo.com) — for web search, only when you enable it

## Open Source

DriftPaca is open source. You can inspect the full source code to verify our privacy practices at: https://github.com/SongTonyLi/DriftPaca

## Contact

If you have questions about this privacy policy, please open an issue on our GitHub repository.
