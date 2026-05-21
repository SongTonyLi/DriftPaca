# Privacy Policy

**Last updated: May 20, 2026**

## Overview

DriftPaca is an open-source AI chat client. Your privacy is important to us. This policy explains what data DriftPaca handles and how.

## Data Collection

DriftPaca does **not** collect, store, or transmit any personal data to us or any third parties. We have no servers, no analytics, and no tracking.

## Data Storage

All data — including chat history, settings, and preferences — is stored **locally on your device** using an on-device database. Nothing leaves your device unless you explicitly connect to a server or enable features described below.

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

## Third-Party Services

DriftPaca does not integrate any analytics, advertising, or tracking services. The only third-party services used are:

- **Ollama** (ollama.com) — for AI model inference, only when you configure it
- **DuckDuckGo** (duckduckgo.com) — for web search, only when you enable it

## Open Source

DriftPaca is open source. You can inspect the full source code to verify our privacy practices at: https://github.com/SongTonyLi/DriftPaca

## Contact

If you have questions about this privacy policy, please open an issue on our GitHub repository.
