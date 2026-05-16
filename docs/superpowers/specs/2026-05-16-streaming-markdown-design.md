# Streaming Markdown Rendering with 60fps Throttle

## Problem

During token streaming, LlamaSeek renders plain text with a per-word fade-in animation (`StreamingTextRenderer`). Markdown formatting, LaTeX equations, and code syntax highlighting only render after the full response completes. This creates a jarring "flash" when the response finishes and all formatting appears at once.

Open WebUI solves this by re-parsing and rendering markdown on every frame (throttled to 60fps). Code blocks highlight as they grow, LaTeX renders the instant delimiters close, tables build row by row.

## Design

### Approach: All-MarkdownBody at 60fps

Replace the binary streaming/completion rendering switch with a single code path: always render with `MarkdownBody`, even during streaming. Throttle content updates to 60fps using Flutter's `addPostFrameCallback` (equivalent to `requestAnimationFrame`).

### Why not the split/hybrid approach

A split approach (MarkdownBody for completed blocks + StreamingTextRenderer for active text) was considered and rejected because:
- **Flash at the seam**: Content transitioning from plain text to formatted markdown causes a visible visual jump
- **Layout shift**: Code blocks and LaTeX equations change dimensions when they switch from plain text to rendered, pushing content around
- **Long blocks**: Code blocks stay as unformatted plain text for their entire streaming duration

### Architecture

```
Token arrives (from SSE stream)
    |
ChatProvider.notifyListeners()  [every token, as today]
    |
_AssistantBubble.didUpdateWidget()
    |  (content changed?)
    |
_scheduleContentUpdate()
    |  (if no update pending, schedule via addPostFrameCallback)
    |
[~16ms frame boundary]
    |
setState() with latest content
    |
MarkdownBody rebuilds with full markdown/LaTeX/code rendering
    |
User sees formatted text appearing at 60fps
```

### Changes required

#### 1. `chat_bubble.dart` — `_AssistantBubbleState`

Convert to use throttled markdown rendering during streaming:

- Add `_throttledContent` field and `_updatePending` flag
- In `didUpdateWidget`: when streaming and content changes, call `_scheduleContentUpdate()` instead of rebuilding immediately
- `_scheduleContentUpdate()`: if no update pending, use `SchedulerBinding.instance.addPostFrameCallback` to schedule a `setState` that updates `_throttledContent`
- `_buildContent()`: always return `MarkdownBody` (remove the `StreamingTextRenderer` branch). During streaming, pass `_throttledContent`; after completion, pass `widget.message.content` directly.

#### 2. `chat_bubble.dart` — `_buildMarkdown`

Add a custom table builder that wraps tables in `SingleChildScrollView(scrollDirection: Axis.horizontal)` so wide tables scroll instead of overflowing.

#### 3. No changes needed

- `streaming_text_renderer.dart` — kept for potential future use but no longer called during streaming
- `chat_provider.dart` — continues to `notifyListeners()` on every token as today
- `ollama_service.dart` — no changes

### Edge cases

| Scenario | Behavior |
|----------|----------|
| Incomplete code block (no closing ```) | `flutter_markdown` renders as plain text until fences close |
| Incomplete LaTeX (unclosed `$` or `$$`) | Rendered as literal text until delimiters close |
| Incomplete table | Partial pipe syntax rendered as text until table structure is valid |
| Very rapid tokens | Batched by 60fps throttle — multiple tokens per frame, one rebuild |
| Empty content | No MarkdownBody rendered (existing guard) |
| Stream completes | Final `setState` with full content, throttle cancelled |

### Performance considerations

- `flutter_markdown` parses and builds the full widget tree on each rebuild. For typical chat messages (< 2000 words), this is fast enough at 60fps.
- The throttle ensures at most 60 rebuilds/second regardless of token arrival rate.
- For very long responses, the markdown parsing cost grows linearly but remains bounded by the throttle.
- The `MarkdownBody`'s `selectable: true` flag adds some overhead; this is acceptable since Flutter's widget diffing minimizes actual repaints.

### Table rendering improvement

Wrap tables in a horizontal scroll container to handle wide tables on narrow screens:

```dart
// Custom table builder for MarkdownBody
class ScrollableTableBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // Default table rendering + SingleChildScrollView wrapper
  }
}
```

This applies to both streaming and completed messages.
