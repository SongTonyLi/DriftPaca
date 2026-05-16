# Streaming Markdown Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render markdown, LaTeX, and syntax-highlighted code during streaming (not just after completion), throttled at 60fps.

**Architecture:** Replace the binary `StreamingTextRenderer` / `MarkdownBody` switch in `_AssistantBubble` with a single `MarkdownBody` code path that always renders formatted markdown. Throttle content updates to one rebuild per frame using `addPostFrameCallback`. Add horizontal scroll support for wide tables via `IntrinsicColumnWidth` in the stylesheet.

**Tech Stack:** Flutter, `flutter_markdown`, `flutter_markdown_latex`, `SchedulerBinding`

---

### Task 1: Add 60fps throttle to `_AssistantBubbleState`

**Files:**
- Modify: `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart:162-267`

- [ ] **Step 1: Add `dart:ui` import and throttle state fields**

At the top of the file, add the import:

```dart
import 'package:flutter/scheduler.dart';
```

In `_AssistantBubbleState` (after line 178), add:

```dart
class _AssistantBubbleState extends State<_AssistantBubble> {
  bool _wasStreaming = false;
  String _throttledContent = '';
  bool _updatePending = false;
```

- [ ] **Step 2: Add `_scheduleContentUpdate` method**

Add this method to `_AssistantBubbleState`, after `didUpdateWidget`:

```dart
void _scheduleContentUpdate() {
  if (_updatePending) return;
  _updatePending = true;
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (mounted) {
      setState(() {
        _throttledContent = widget.message.content;
        _updatePending = false;
      });
    }
  });
}
```

- [ ] **Step 3: Update `didUpdateWidget` to use throttle during streaming**

Replace the existing `didUpdateWidget` method:

```dart
@override
void didUpdateWidget(_AssistantBubble old) {
  super.didUpdateWidget(old);
  if (old.isStreaming && !widget.isStreaming) {
    _wasStreaming = true;
    // Stream ended — show final content immediately
    _throttledContent = widget.message.content;
    _updatePending = false;
  } else if (widget.isStreaming) {
    _scheduleContentUpdate();
  } else {
    // Not streaming — keep content in sync
    _throttledContent = widget.message.content;
  }
}
```

- [ ] **Step 4: Replace `_buildContent` to always use MarkdownBody**

Replace the `_buildContent` method:

```dart
Widget _buildContent(BuildContext context, String data) {
  return widget.buildMarkdown(context, data);
}
```

- [ ] **Step 5: Update `_buildMessageContent` to use throttled content during streaming**

In `_buildMessageContent`, change every call that passes `widget.message.content` to a helper that picks the right content based on streaming state. Replace the method:

```dart
Widget _buildMessageContent(BuildContext context) {
  final content = widget.isStreaming ? _throttledContent : widget.message.content;

  if (widget.message.thinking != null &&
      widget.message.thinking!.isNotEmpty) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ThinkBlockWidget(
          content: widget.message.thinking!,
          isComplete: content.isNotEmpty,
        ),
        if (content.isNotEmpty) ...[
          const SizedBox(height: 4),
          _buildContent(context, content),
        ],
      ],
    );
  }

  final parsed = ThinkBlockParser.tryParse(
    widget.isStreaming ? _throttledContent : widget.message.content,
  );

  if (parsed != null) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ThinkBlockWidget(
          content: parsed.thinkContent,
          isComplete: parsed.isThinkingComplete,
        ),
        if (parsed.responseContent.isNotEmpty) ...[
          const SizedBox(height: 4),
          _buildContent(context, parsed.responseContent),
        ],
      ],
    );
  }

  return _buildContent(context, content);
}
```

- [ ] **Step 6: Hot reload and verify**

Run: `kill -USR1 $(pgrep -f flutter_tools.*run)` or press `r` in the flutter run terminal.

Expected: During streaming, markdown renders incrementally. Code blocks gain syntax highlighting as they grow. LaTeX renders when delimiters close. No per-word fade-in animation — text appears formatted at ~60fps.

- [ ] **Step 7: Commit**

```bash
git add lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart
git commit -m "Render markdown during streaming with 60fps throttle

Replace StreamingTextRenderer with MarkdownBody during streaming.
Content updates are throttled to one rebuild per frame via
addPostFrameCallback, matching Open WebUI's requestAnimationFrame
approach."
```

---

### Task 2: Add horizontal scroll for wide tables

**Files:**
- Modify: `lib/Extensions/markdown_stylesheet_extension.dart:38-59`

- [ ] **Step 1: Set `tableColumnWidth` to `IntrinsicColumnWidth`**

`flutter_markdown` already wraps tables in `SingleChildScrollView` when `tableColumnWidth` is `IntrinsicColumnWidth` or `FixedColumnWidth`. Add this to the `.copyWith()` call in `markdown_stylesheet_extension.dart`:

```dart
    return MarkdownStyleSheet.fromTheme(
      theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          bodyMedium: theme.textTheme.bodyLarge,
        ),
      ),
    ).copyWith(
      textScaler: MediaQuery.textScalerOf(this).clamp(
        minScaleFactor: 0.8,
        maxScaleFactor: 2.0,
      ),
      // Inline code
      code: codeFont,
      // Code blocks
      codeblockDecoration: BoxDecoration(
        color: codeBlockBg,
        borderRadius: BorderRadius.circular(10),
      ),
      codeblockPadding: const EdgeInsets.all(14),
      codeblockAlign: WrapAlignment.start,
      // Tables — intrinsic width enables horizontal scroll for wide tables
      tableColumnWidth: const IntrinsicColumnWidth(),
    );
```

- [ ] **Step 2: Hot reload and verify**

Run: `kill -USR1 $(pgrep -f flutter_tools.*run)`

Test by sending a prompt that generates a wide table (e.g., "Create a table comparing 5 programming languages across 6 features"). The table should scroll horizontally on narrow screens instead of overflowing.

- [ ] **Step 3: Commit**

```bash
git add lib/Extensions/markdown_stylesheet_extension.dart
git commit -m "Enable horizontal scroll for wide markdown tables

Set tableColumnWidth to IntrinsicColumnWidth so flutter_markdown
wraps tables in SingleChildScrollView automatically."
```

---

### Task 3: Clean up unused StreamingTextRenderer import

**Files:**
- Modify: `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart:15`

- [ ] **Step 1: Remove the unused import**

Remove this line from the imports at the top of `chat_bubble.dart`:

```dart
import 'streaming_text_renderer.dart';
```

- [ ] **Step 2: Verify no compile errors**

Run: `kill -USR1 $(pgrep -f flutter_tools.*run)`

Expected: Hot reload succeeds with no errors. The `streaming_text_renderer.dart` file is kept in the codebase but no longer imported by `chat_bubble.dart`.

- [ ] **Step 3: Commit**

```bash
git add lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart
git commit -m "Remove unused StreamingTextRenderer import"
```

---

### Task 4: End-to-end verification

- [ ] **Step 1: Test streaming with markdown formatting**

Send a prompt like: "Explain quicksort with a code example in Python, include the time complexity formula using LaTeX notation, and a comparison table of sorting algorithms."

Verify during streaming:
- Paragraphs render with proper markdown formatting as they arrive
- Code blocks get syntax highlighting as the code streams in
- `$$O(n \log n)$$` renders as a centered equation when the closing `$$` arrives
- Tables render row by row as content arrives
- Wide tables scroll horizontally
- The stop button still works to cancel streaming
- After streaming completes, the message looks identical to how it looked before this change

- [ ] **Step 2: Test edge cases**

1. **Rapid tokens**: Verify no frame drops or jank during fast streaming
2. **Empty message**: Start and immediately stop a stream — no crash
3. **Think blocks**: Test with a model that outputs `<think>...</think>` blocks — verify thinking section still works
4. **Very long response**: Let a response run for 1000+ words — verify performance stays smooth
5. **Scroll position**: Verify auto-scroll still works during streaming (content scrolls down as new text appears)

- [ ] **Step 3: Test completed messages**

Navigate between existing chat conversations. Verify:
- Previously saved messages still render markdown/LaTeX/tables correctly
- No visual regression compared to before
