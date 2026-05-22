# Memory & Power Optimization Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce memory usage and power consumption across the app without changing any user-visible functionality.

**Architecture:** 10 targeted, independent optimizations across services, providers, models, and widgets. Each task is self-contained and can be committed independently. Changes are purely internal — same UI, same behavior, less waste.

**Tech Stack:** Flutter/Dart, Provider, SQLite, Hive

---

## File Map

| File | Changes |
|------|---------|
| `lib/Services/memory_service.dart` | Remove debug prints, bound conversation memory cache |
| `lib/Pages/chat_page/chat_page_view_model.dart` | Optimize text field change notifications |
| `lib/Models/ollama_message.dart` | Clear base64 cache after use, skip context array parsing |
| `lib/Pages/chat_page/subwidgets/chat_list_view.dart` | Clear bubble cache on chat switch, simplify scroll button animations |
| `lib/Providers/chat_provider.dart` | Throttle title generation updates, optimize notification proxy |
| `lib/Widgets/chat_drawer.dart` | Reduce blur radius |
| `lib/Pages/chat_page/chat_page.dart` | Reduce blur radius |
| `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart` | Reduce blur radius |
| `test/chat_page_view_model_test.dart` | Update test for new notification behavior |

---

### Task 1: Remove debug print statements from MemoryService

**Files:**
- Modify: `lib/Services/memory_service.dart`

These `print()` calls allocate strings and perform I/O on every memory update in production. There are 10+ of them.

- [ ] **Step 1: Remove all print statements**

In `lib/Services/memory_service.dart`, remove every line that starts with `// ignore: avoid_print` followed by a `print(...)` call. There are pairs at approximately lines 183-188, 193-194, 243-244, 249-251, 255-256, 272-273, 291-292, 299-300, 304-305, 310-311.

Replace the entire `triggerMemoryUpdate` method body (lines 178-198) with:

```dart
void triggerMemoryUpdate({
  required String chatId,
  required List<OllamaMessage> messages,
  bool skipAgentMemory = false,
}) {
  if (!isEnabled) return;
  if (_isUpdating) return;

  // Fire and forget
  _performUpdate(chatId: chatId, messages: messages, skipAgentMemory: skipAgentMemory);
}
```

In `_performUpdate` (lines 200-267), remove the print at line 243-244.

In `_callCloudModel` (lines 269-313), remove prints at lines 272-273, 291-292, 299-300, 304-305, 310-311. Keep the `debugPrint` calls (those are already stripped in release builds).

In `_parseAndSave` (line 315+), keep the existing `debugPrint` calls (release-safe).

- [ ] **Step 2: Run existing tests to verify no breakage**

Run: `cd /Users/songli/DriftPaca && flutter test test/services/memory_service_test.dart -v`
Expected: All tests pass (these test static parse logic, not print output).

- [ ] **Step 3: Commit**

```bash
git add lib/Services/memory_service.dart
git commit -m "Remove debug print statements from MemoryService"
```

---

### Task 2: Optimize text field change notifications

**Files:**
- Modify: `lib/Pages/chat_page/chat_page_view_model.dart:142-143`
- Modify: `test/chat_page_view_model_test.dart:129-136`

Currently `_onTextFieldChanged()` calls `notifyListeners()` on every keystroke. The only consumer that cares is the send button (enabled when text is non-empty). Change it to only notify on empty↔non-empty transitions.

- [ ] **Step 1: Update the existing test to reflect new behavior**

In `test/chat_page_view_model_test.dart`, replace the test at line 129-136:

```dart
test('textFieldController changes should notify only on empty/non-empty transitions', () {
  var notifyCount = 0;
  viewModel.addListener(() => notifyCount++);

  // Empty -> non-empty: should notify
  viewModel.textFieldController.text = 'T';
  expect(notifyCount, 1);

  // Non-empty -> non-empty: should NOT notify
  viewModel.textFieldController.text = 'Te';
  expect(notifyCount, 1);

  // Non-empty -> non-empty: should NOT notify
  viewModel.textFieldController.text = 'Test';
  expect(notifyCount, 1);

  // Non-empty -> empty: should notify
  viewModel.textFieldController.text = '';
  expect(notifyCount, 2);

  // Empty -> empty: should NOT notify
  viewModel.textFieldController.text = '';
  expect(notifyCount, 2);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/songli/DriftPaca && flutter test test/chat_page_view_model_test.dart --name "textFieldController changes" -v`
Expected: FAIL — current implementation notifies on every change.

- [ ] **Step 3: Implement the optimization**

In `lib/Pages/chat_page/chat_page_view_model.dart`, add a field after line 88 (`bool get hasText => ...`):

```dart
bool _lastHasText = false;
```

Replace `_onTextFieldChanged` (lines 142-144) with:

```dart
void _onTextFieldChanged() {
  final currentHasText = hasText;
  if (currentHasText != _lastHasText) {
    _lastHasText = currentHasText;
    notifyListeners();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/songli/DriftPaca && flutter test test/chat_page_view_model_test.dart -v`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/Pages/chat_page/chat_page_view_model.dart test/chat_page_view_model_test.dart
git commit -m "Only notify listeners on text field empty/non-empty transitions"
```

---

### Task 3: Clear base64 image cache after API call completes

**Files:**
- Modify: `lib/Models/ollama_message.dart:149-159`

Base64 encoded images (1.33x the file size) stay in `_cachedBase64Images` forever after the first API call. Add a method to clear the cache and call it from the provider after streaming completes.

- [ ] **Step 1: Add clearBase64Cache method to OllamaMessage**

In `lib/Models/ollama_message.dart`, after the `_base64EncodeImages` method (after line 159), add:

```dart
/// Releases the cached base64-encoded image data to free memory.
/// The cache will be rebuilt on the next API call if needed.
void clearBase64Cache() {
  _cachedBase64Images = null;
}
```

- [ ] **Step 2: Clear cache after streaming completes in ChatProvider**

In `lib/Providers/chat_provider.dart`, in the `_streamOllamaMessage` method, after line 419 (`streamingMessage?.createdAt = DateTime.now();`), add:

```dart
// Release base64 image data from all messages to free memory
for (final m in _messages) {
  m.clearBase64Cache();
}
```

- [ ] **Step 3: Run existing tests**

Run: `cd /Users/songli/DriftPaca && flutter test -v`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/Models/ollama_message.dart lib/Providers/chat_provider.dart
git commit -m "Clear base64 image cache after streaming completes"
```

---

### Task 4: Clear bubble cache on chat switch

**Files:**
- Modify: `lib/Pages/chat_page/subwidgets/chat_list_view.dart:60-69`

The `_bubbleCache` map grows indefinitely. When `didUpdateWidget` detects a chat switch (messages changed entirely), clear the stale entries.

- [ ] **Step 1: Add cache cleanup to didUpdateWidget**

In `lib/Pages/chat_page/subwidgets/chat_list_view.dart`, replace the `didUpdateWidget` method (lines 60-69) with:

```dart
@override
void didUpdateWidget(covariant ChatListView oldWidget) {
  super.didUpdateWidget(oldWidget);

  // Clear bubble cache when switching chats (message list replaced entirely)
  if (!identical(widget.messages, oldWidget.messages)) {
    _bubbleCache.clear();
  }

  // Add to the post frame callback to ensure that the scroll offset is
  // read after the widget has been updated.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Update the button visibility when the user switches chats,
    // regenerates a message or delete a message.
    _updateScrollToBottomButtonVisibility();
  });
}
```

- [ ] **Step 2: Run existing widget tests**

Run: `cd /Users/songli/DriftPaca && flutter test test/widgets/chat_list_view_test.dart -v`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/Pages/chat_page/subwidgets/chat_list_view.dart
git commit -m "Clear bubble cache when switching chats"
```

---

### Task 5: Reduce BackdropFilter blur radius from 40 to 20

**Files:**
- Modify: `lib/Widgets/chat_drawer.dart:35` and `:389`
- Modify: `lib/Pages/chat_page/chat_page.dart:299`
- Modify: `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart:703`

40px blur is extremely GPU-intensive — each pixel samples a huge kernel. 20px is visually nearly identical but requires ~4x less GPU work (blur cost scales with radius squared).

- [ ] **Step 1: Reduce blur in chat_drawer.dart (sidebar)**

In `lib/Widgets/chat_drawer.dart`, change line 35:

```dart
filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
```

to:

```dart
filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
```

Also change the context menu blur at line 389 from `sigmaX: 40, sigmaY: 40` to `sigmaX: 20, sigmaY: 20`.

- [ ] **Step 2: Reduce blur in chat_page.dart (composer)**

In `lib/Pages/chat_page/chat_page.dart`, change line 299:

```dart
filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
```

to:

```dart
filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
```

- [ ] **Step 3: Reduce blur in chat_bubble.dart (edit popup)**

In `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart`, change line 703:

```dart
filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
```

to:

```dart
filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
```

- [ ] **Step 4: Verify visually**

Run the app: `cd /Users/songli/DriftPaca && flutter run`
Check these surfaces still look properly frosted glass:
- Sidebar drawer
- Chat composer input area
- Context menu (long-press a chat in sidebar)
- Edit popup (tap Edit on a user message)

- [ ] **Step 5: Commit**

```bash
git add lib/Widgets/chat_drawer.dart lib/Pages/chat_page/chat_page.dart lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart
git commit -m "Reduce BackdropFilter blur radius from 40 to 20"
```

---

### Task 6: Throttle title generation updates

**Files:**
- Modify: `lib/Providers/chat_provider.dart:597-642`

`generateTitleForCurrentChat` calls `updateChat()` for every streaming token during title generation. Each call writes to SQLite and fires `notifyListeners()`. Throttle to update at most every 100ms.

- [ ] **Step 1: Add throttling to title generation**

In `lib/Providers/chat_provider.dart`, replace the `generateTitleForCurrentChat` method (lines 597-642) with:

```dart
Future<void> generateTitleForCurrentChat() async {
  final associatedChat = currentChat;
  final message = _messages.firstOrNull;
  if (associatedChat == null || message == null) return;

  // Create a temp chat with necessary system prompt
  final chat = OllamaChat(
    model: associatedChat.model,
    systemPrompt: GenerateTitleConstants.systemPrompt,
  );

  try {
    // Generate a title for the message
    final stream = _ollamaService.generateStream(
      GenerateTitleConstants.prompt + message.content,
      chat: chat,
    );

    var title = "";
    final titleThrottle = Stopwatch()..start();
    await for (final titleMessage in stream) {
      // Ignore empty initial messages, preventing empty title
      if (title.isEmpty && titleMessage.content.isEmpty) {
        continue;
      }

      title += titleMessage.content;

      // Throttle title updates to at most every 100ms
      if (titleThrottle.elapsedMilliseconds >= 100) {
        titleThrottle.reset();
        if (title.startsWith("<think>")) {
          await updateChat(associatedChat, newTitle: "Thinking for a title...");
        } else {
          await updateChat(associatedChat, newTitle: title);
        }
      }
    }

    // Remove <think> tag and its content
    if (title.startsWith("<think>")) {
      title = title.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '');
    }

    // Final update with complete title
    await updateChat(associatedChat, newTitle: title.trim());
  } catch (_) {
    // Silently ignore title generation failures (e.g., cloud model errors)
  }
}
```

- [ ] **Step 2: Run existing tests**

Run: `cd /Users/songli/DriftPaca && flutter test -v`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/Providers/chat_provider.dart
git commit -m "Throttle title generation updates to 100ms intervals"
```

---

### Task 7: Bound conversation memory cache size

**Files:**
- Modify: `lib/Services/memory_service.dart:32`

The `_conversationMemoryCache` map grows unbounded — every chat's memory that's ever accessed stays in RAM. Cap it to the 20 most recently accessed entries.

- [ ] **Step 1: Add cache eviction logic**

In `lib/Services/memory_service.dart`, replace the cache declaration at line 32:

```dart
final Map<String, ConversationMemory> _conversationMemoryCache = {};
```

with:

```dart
/// LRU-style cache: most recently accessed entry is last.
/// Capped at [_maxConversationCacheSize] entries.
final Map<String, ConversationMemory> _conversationMemoryCache = {};
static const int _maxConversationCacheSize = 20;
```

Then in the `getConversationMemory` method (lines 66-76), replace it with:

```dart
Future<ConversationMemory?> getConversationMemory(String chatId) async {
  if (_conversationMemoryCache.containsKey(chatId)) {
    // Move to end (most recently used)
    final value = _conversationMemoryCache.remove(chatId)!;
    _conversationMemoryCache[chatId] = value;
    return value;
  }

  final memory = await _db.getConversationMemory(chatId);
  if (memory != null) {
    _conversationMemoryCache[chatId] = memory;
    // Evict oldest if over capacity
    while (_conversationMemoryCache.length > _maxConversationCacheSize) {
      _conversationMemoryCache.remove(_conversationMemoryCache.keys.first);
    }
  }
  return memory;
}
```

Also update `updateConversationMemoryField` (lines 533-539) to maintain the cap:

```dart
Future<void> updateConversationMemoryField(
  String chatId,
  ConversationMemory memory,
) async {
  _conversationMemoryCache.remove(chatId); // Remove old position
  _conversationMemoryCache[chatId] = memory; // Add at end (most recent)
  while (_conversationMemoryCache.length > _maxConversationCacheSize) {
    _conversationMemoryCache.remove(_conversationMemoryCache.keys.first);
  }
  await _db.updateConversationMemory(chatId, memory);
  notifyListeners();
}
```

- [ ] **Step 2: Run existing tests**

Run: `cd /Users/songli/DriftPaca && flutter test test/services/memory_service_test.dart -v`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/Services/memory_service.dart
git commit -m "Cap conversation memory cache at 20 entries with LRU eviction"
```

---

### Task 8: Skip parsing unused context array from Ollama responses

**Files:**
- Modify: `lib/Models/ollama_message.dart:61-84`

The `context` field (a large `List<int>` of token IDs) is parsed from every Ollama JSON response but is never used in chat mode (only relevant for stateless `/api/generate`). Skip parsing it to avoid large list allocations.

- [ ] **Step 1: Remove context parsing from fromJson**

In `lib/Models/ollama_message.dart`, in the `fromJson` factory (lines 61-84), change lines 76-78:

```dart
context: json["context"] != null
    ? List<int>.from(json["context"].map((x) => x))
    : null,
```

to:

```dart
// context array skipped — large token ID list unused in chat mode
```

- [ ] **Step 2: Run existing tests**

Run: `cd /Users/songli/DriftPaca && flutter test -v`
Expected: All tests pass. No test depends on the `context` field.

- [ ] **Step 3: Commit**

```bash
git add lib/Models/ollama_message.dart
git commit -m "Skip parsing unused context token array from Ollama responses"
```

---

### Task 9: Simplify scroll-to-bottom button animations

**Files:**
- Modify: `lib/Pages/chat_page/subwidgets/chat_list_view.dart:143-187`

Three layered implicit animations (`AnimatedPositioned` + `AnimatedScale` + `AnimatedOpacity`) run simultaneously on the scroll-to-bottom button. Replace with a single `AnimatedScale` + `AnimatedOpacity` pair — `AnimatedPositioned` is unnecessary since the button's position only changes when the composer padding changes (not on show/hide).

- [ ] **Step 1: Simplify the button widget tree**

In `lib/Pages/chat_page/subwidgets/chat_list_view.dart`, replace the scroll-to-bottom button block (lines 143-187) with:

```dart
Positioned(
  right: 16,
  bottom: _scrollToBottomButtonBottomOffset(),
  child: AnimatedScale(
    scale: _isScrollToBottomButtonVisible ? 1.0 : 0.0,
    duration: const Duration(milliseconds: 250),
    curve: _isScrollToBottomButtonVisible ? Curves.easeOutBack : Curves.easeIn,
    child: AnimatedOpacity(
      opacity: _isScrollToBottomButtonVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !_isScrollToBottomButtonVisible,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.78),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: IconButton(
            onPressed: _scrollToBottom,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
            tooltip: 'Scroll to latest',
            style: IconButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.82),
              minimumSize: const Size(40, 40),
              maximumSize: const Size(40, 40),
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    ),
  ),
),
```

The key change: `AnimatedPositioned` → `Positioned`. The bottom offset is driven by composer padding which changes rarely, not by show/hide. This removes one implicit animation controller.

- [ ] **Step 2: Run existing widget tests**

Run: `cd /Users/songli/DriftPaca && flutter test test/widgets/chat_list_view_test.dart -v`
Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/Pages/chat_page/subwidgets/chat_list_view.dart
git commit -m "Replace AnimatedPositioned with Positioned on scroll-to-bottom button"
```

---

### Task 10: Optimize ChatProvider → ViewModel notification proxy

**Files:**
- Modify: `lib/Pages/chat_page/chat_page_view_model.dart:114-143`

Every `ChatProvider.notifyListeners()` call triggers `ChatPageViewModel.notifyListeners()` via the proxy, even when no ViewModel-specific state changed. Track the last-seen relevant state and skip redundant notifications.

- [ ] **Step 1: Add state tracking fields**

In `lib/Pages/chat_page/chat_page_view_model.dart`, after line 95 (`late final StreamSubscription _settingsSubscription;`), add:

```dart
// Tracked state for skipping redundant notifications from ChatProvider
int _lastMessageCount = 0;
String? _lastChatId;
bool _lastIsStreaming = false;
bool _lastIsThinking = false;
String? _lastErrorMessage;
```

- [ ] **Step 2: Replace the notification proxy**

Replace `_onChatProviderChanged` (lines 138-140) with:

```dart
void _onChatProviderChanged() {
  final messageCount = _chatProvider.messages.length;
  final chatId = _chatProvider.currentChat?.id;
  final isStreaming = _chatProvider.isCurrentChatStreaming;
  final isThinking = _chatProvider.isCurrentChatThinking;
  final errorMessage = _chatProvider.currentChatError?.message;

  if (messageCount != _lastMessageCount ||
      chatId != _lastChatId ||
      isStreaming != _lastIsStreaming ||
      isThinking != _lastIsThinking ||
      errorMessage != _lastErrorMessage) {
    _lastMessageCount = messageCount;
    _lastChatId = chatId;
    _lastIsStreaming = isStreaming;
    _lastIsThinking = isThinking;
    _lastErrorMessage = errorMessage;
    notifyListeners();
  }
}
```

- [ ] **Step 3: Run existing tests**

Run: `cd /Users/songli/DriftPaca && flutter test test/chat_page_view_model_test.dart -v`
Expected: All tests pass. The "ChatProvider changes should notify ViewModel listeners" test still passes because the fake provider's `triggerNotifyListeners()` is called from a clean state where all tracked fields differ from defaults.

- [ ] **Step 4: Verify the proxy test still triggers notification**

Check the test at line 175-182: it calls `fakeChatProvider.triggerNotifyListeners()` after setup. At that point `_lastChatId` is `null` and `_chatProvider.currentChat?.id` is also `null`, `_lastMessageCount` is `0` and messages is empty — so nothing changed. This test will fail.

Fix the test to ensure state actually changes before checking notification:

In `test/chat_page_view_model_test.dart`, replace the test at line 175-182:

```dart
test('ChatProvider changes should notify ViewModel listeners', () {
  var notified = false;
  viewModel.addListener(() => notified = true);

  // Change state so the notification proxy detects a difference
  fakeChatProvider.setMessages([
    OllamaMessage('Hello', role: OllamaMessageRole.user),
  ]);
  fakeChatProvider.triggerNotifyListeners();

  expect(notified, isTrue);
});
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /Users/songli/DriftPaca && flutter test test/chat_page_view_model_test.dart -v`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/Pages/chat_page/chat_page_view_model.dart test/chat_page_view_model_test.dart
git commit -m "Skip redundant ChatProvider to ViewModel notification forwarding"
```
