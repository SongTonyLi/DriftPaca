# Open-webui Integration Design

## Problem

The Reins Flutter app connects directly to Ollama and lacks three features:
1. **Thinking tokens not streamed** — `OllamaMessage.fromJson()` only reads `message.content`, ignoring `message.thinking`
2. **No internet search** — Not implemented at all
3. **Attachments limited to images** — Only `ImagePicker` for photos, no documents

## Solution

Add open-webui as a backend option. Open-webui runs locally (like Ollama on `localhost:11434`, open-webui on `localhost:3000`) and already handles all three features server-side. The Flutter app just needs a new API client that speaks the OpenAI-compatible protocol.

## Architecture

```
Current:  Flutter app  →  Ollama API (/api/chat)
New:      Flutter app  →  Open-webui API (/api/chat/completions)  →  Ollama
```

Both backend modes coexist. User selects in Settings. Direct Ollama mode is unchanged (with thinking token fix applied). Open-webui mode enables all three features.

## Feature 1: Thinking Token Streaming

### Direct Ollama mode (fix)
- `OllamaMessage.fromJson()` now reads `json["message"]["thinking"]`
- Add `String? thinking` field to `OllamaMessage`
- During streaming, accumulate `thinking` separately: `streamingMessage.thinking += received.thinking`
- `toChatJson()` includes `thinking` field for multi-turn context
- Store `thinking` in database (new column)

### Open-webui mode
- SSE delta includes `reasoning_content` field alongside `content`
- Parse both from each chunk: `delta["content"]` and `delta["reasoning_content"]`
- Map `reasoning_content` → `OllamaMessage.thinking`
- Same accumulation and storage as above

### UI (both modes)
- Existing `ThinkBlockWidget` works as-is — just fed from `message.thinking` instead of parsing `<think>` tags from content
- Keep `<think>` tag fallback for models that embed inline (e.g., title generation)
- `ChatBubble._buildMessageContent()` checks `message.thinking` first, falls back to `ThinkBlockParser.tryParse()`

## Feature 2: Internet Search

### How it works
- User taps globe toggle icon in the input bar (next to `+` button)
- Toggle state stored in `ChatPageViewModel.webSearchEnabled`
- When sending a message with search enabled, the request includes `"features": {"web_search": true}`
- Open-webui server handles everything: query generation, search API calls, page fetching, RAG context injection
- Response streams back with search-informed content
- Source URLs returned in the SSE stream's top-level `sources` field

### UI
- Globe icon button between `+` (attachments) and the text field
- Active state: filled icon with accent color
- The `sources` from the response are displayed below the message bubble as tappable URL chips
- "Searching the web..." status shown during the search phase (before content starts streaming)

### Direct Ollama mode
- Search toggle hidden (not supported without open-webui)

## Feature 3: File Attachments

### How it works
- `+` button shows a bottom sheet: "Photo Library" / "Choose File"
- "Photo Library" — existing `ImagePicker` flow (unchanged)
- "Choose File" — uses `file_picker` package, allows any file type
- Selected file is uploaded to open-webui: `POST /api/v1/files/` (multipart form data)
- Server returns file object with `id`
- File ID included in chat request: `"files": [{"type": "file", "id": "file-uuid"}]`
- Open-webui extracts text (PDF, DOCX, TXT, CSV, etc.), embeds, and injects as RAG context

### UI
- File attachments shown as chips in the attachment row (filename + file type icon + remove button)
- Image attachments continue to show as thumbnail previews
- Both file chips and image thumbnails coexist in the same attachment row

### Direct Ollama mode
- File picker hidden for non-image files (not supported without open-webui)
- Image attachment works as before (base64 in message)

## New Files

### `lib/Services/openwebui_service.dart`
OpenAI-compatible API client. Key methods:
- `chatCompletionStream()` — POST `/api/chat/completions`, returns `Stream<ChatCompletionChunk>`
- `uploadFile()` — POST `/api/v1/files/`, returns file ID
- `listModels()` — GET `/api/models`, returns available models
- `deleteFile()` — DELETE `/api/v1/files/{id}`

SSE parser: split on `\n`, strip `data: ` prefix, parse JSON, detect `[DONE]`.

### `lib/Models/chat_completion_chunk.dart`
Data model for OpenAI SSE chunks:
- `choices[0].delta.content`
- `choices[0].delta.reasoning_content`
- `choices[0].finish_reason`
- Top-level `sources` (search results)

### `lib/Models/uploaded_file.dart`
Data model for uploaded file reference:
- `id` — UUID from open-webui
- `filename` — display name
- `type` — "file"

## Modified Files

### `lib/Models/ollama_message.dart`
- Add `String? thinking` field
- Parse `thinking` from both Ollama (`message.thinking`) and OpenAI (`reasoning_content`) formats
- `toChatJson()` includes `thinking` when present
- `toDatabaseMap()` / `fromDatabase()` handle new `thinking` column
- `updateMetadataFrom()` copies thinking field
- Add `List<String>? sources` for search result URLs

### `lib/Services/ollama_service.dart`
- `_processStream()` unchanged (already works, just needs `fromJson` fix in OllamaMessage)

### `lib/Services/database_service.dart`
- Add `thinking` TEXT column to messages table (migration)
- Add `sources` TEXT column (JSON-encoded list of URLs)

### `lib/Providers/chat_provider.dart`
- `_streamOllamaMessage()` accumulates `thinking` alongside `content`
- New method `_streamOpenWebUIMessage()` for the OpenAI SSE path
- `sendPrompt()` accepts `webSearchEnabled` and `files` parameters
- Route to correct streaming method based on backend mode

### `lib/Pages/chat_page/chat_page_view_model.dart`
- Add `bool webSearchEnabled` toggle state
- Add `List<UploadedFile> _attachedFiles` for non-image files
- `pickFile()` method using `file_picker`, uploads to open-webui
- `removeFile()` method, deletes from open-webui
- `sendMessage()` passes search and file params to provider

### `lib/Pages/chat_page/chat_page.dart`
- Add globe toggle button in input bar (between `+` and text field)
- `_handleAttachmentButton()` shows bottom sheet with "Photo Library" / "Choose File"
- Conditionally show/hide search toggle and file option based on backend mode

### `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart`
- `_buildMessageContent()` checks `message.thinking` field first, then falls back to `ThinkBlockParser`
- Add sources display below message when `message.sources` is not empty

### `lib/Pages/chat_page/subwidgets/chat_text_field.dart`
- Support additional action buttons (search toggle) — passed via new parameter or widget composition

### `lib/Pages/settings_page/`
- Backend mode selector: "Ollama Direct" / "Open-webui"
- Open-webui URL field (default: `http://localhost:3000`)
- Open-webui API key field
- Stored in Hive settings box

### `pubspec.yaml`
- Add `file_picker` dependency

## Settings & Configuration

New Hive settings keys:
- `backendMode` — `"ollama"` (default) or `"openwebui"`
- `openwebuiAddress` — URL string (default: `http://localhost:3000`)
- `openwebuiApiKey` — Bearer token string

## Database Migration

Add to existing messages table:
```sql
ALTER TABLE messages ADD COLUMN thinking TEXT;
ALTER TABLE messages ADD COLUMN sources TEXT;
```

Handle migration in `DatabaseService.open()` via version increment.

## SSE Parsing (Open-webui path)

Port from open-webui's `streaming/index.ts`:
```dart
Stream<ChatCompletionChunk> _processSSEStream(Stream<String> stream) async* {
  String buffer = '';
  await for (var chunk in stream) {
    buffer += chunk;
    final lines = buffer.split('\n');
    buffer = lines.removeLast(); // Keep incomplete line

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (!trimmed.startsWith('data: ')) continue;

      final data = trimmed.substring(6);
      if (data.startsWith('[DONE]')) return;

      final json = jsonDecode(data);
      yield ChatCompletionChunk.fromJson(json);
    }
  }
}
```

## Request Format (Open-webui path)

```json
{
  "model": "deepseek-r1:latest",
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user", "content": "What is quantum computing?"}
  ],
  "stream": true,
  "features": {
    "web_search": true
  },
  "files": [
    {"type": "file", "id": "abc-123-def"}
  ]
}
```

## Error Handling

- Open-webui server unreachable: show connection error (same pattern as existing Ollama errors)
- File upload fails: show error toast, don't send message
- Search fails server-side: open-webui handles gracefully, response still works without search context
- Invalid API key: 401/403 → "Invalid API key" error message

## Testing Plan

- Thinking tokens: test with DeepSeek-R1 model, verify streaming display + collapse behavior
- Search: toggle on, send question, verify response includes web context and source URLs
- Files: upload PDF and TXT, verify content is used in response
- Backend switching: verify Ollama direct mode still works unchanged
- Persistence: verify thinking content and sources survive app restart (DB storage)
- iOS simulator: test all three features end-to-end
