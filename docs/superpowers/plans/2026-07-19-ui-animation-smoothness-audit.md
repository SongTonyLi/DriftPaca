# UI Animation Smoothness Audit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Audit every DriftPaca UI animation and deliver surgical fixes for confirmed jank, interruption, lifecycle, reduced-motion, and unnecessary-frame problems without changing the app's visual personality.

**Architecture:** Keep animation state local to existing widgets. Add one small motion-preference utility for semantic durations and `MediaQuery.disableAnimations`, then harden each confirmed surface in focused chat, continuous-effect, search, and model/navigation slices. Maintain `docs/ui_animation_audit_2026-07-19.md` as the coverage ledger tying every inspected surface to evidence, tests, and its final unchanged-or-fixed decision.

**Tech Stack:** Flutter, Dart 3.5.4, Material/Cupertino routes, `AnimationController`, `Ticker`, implicit animations, `flutter_test`, Hive test fixtures.

## Global Constraints

- Preserve current visual effects and product personality.
- Cover all supported platforms and mobile, tablet, and desktop breakpoints.
- Prefer micro-optimizations over reducing fidelity.
- Respect `MediaQuery.disableAnimations` for decorative and nonessential motion.
- Keep essential state changes understandable when animations are disabled.
- Avoid controller, ticker, timer, listener, and post-frame callback leaks.
- Handle repeated taps, reversals, route dismissal, and widget disposal safely.
- Add no dependencies and do not run package resolution.
- Run Flutter tests with `flutter test --no-pub`.
- Make surgical edits; do not run a broad formatter over existing files.
- Preserve all pre-existing working-tree changes. Never stage `debug-high-power-usage.md`, `lark-auth-qr.png`, `lark-config-qr.png`, `test/widgets/chat_app_bar_mobile_test.dart`, or `test/widgets/chat_page_safe_area_test.dart` as part of this work.

---

### Task 1: Verify and Preserve the Earlier Animation-Hardening Baseline

**Files:**
- Existing implementation: `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart`
- Existing implementation: `lib/Pages/chat_page/subwidgets/chat_list_view.dart`
- Existing implementation: `lib/Pages/main_page.dart`
- Existing implementation: `lib/Widgets/model_selection_bottom_sheet.dart`
- Existing test: `test/regression/g09_model_sheet_test.dart`
- Existing test: `test/regression/g14_large_theme_animation_test.dart`
- Existing test: `test/widgets/chat_bubble_test.dart`
- Existing test: `test/widgets/chat_list_view_test.dart`

**Interfaces:**
- Consumes: the uncommitted earlier-audit fixes already present in the working tree.
- Produces: a green baseline proving async refresh duration, deferred scroll safety, large-layout theme interpolation, and resettable copy feedback before new animation work starts.

- [ ] **Step 1: Inspect the baseline diff without changing it**

Run:

```bash
git diff -- \
  lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart \
  lib/Pages/chat_page/subwidgets/chat_list_view.dart \
  lib/Pages/main_page.dart \
  lib/Widgets/model_selection_bottom_sheet.dart \
  test/regression/g09_model_sheet_test.dart \
  test/widgets/chat_bubble_test.dart \
  test/widgets/chat_list_view_test.dart
git status --short --untracked-files=all
```

Expected: the four implementation fixes and their tests are present; the unrelated QR images, power note, mobile-app-bar test, and safe-area test remain unstaged.

- [ ] **Step 2: Run the focused baseline suite**

Run:

```bash
flutter test --no-pub \
  test/regression/g09_model_sheet_test.dart \
  test/regression/g14_large_theme_animation_test.dart \
  test/widgets/chat_list_view_test.dart \
  test/widgets/chat_bubble_test.dart
```

Expected: PASS. If a test fails, fix only the already-intended behavior before continuing.

- [ ] **Step 3: Verify the exact baseline contracts**

Confirm the implementation still contains these contracts:

```dart
// RefreshIndicator awaits the real request.
onRefresh: () {
  final refreshFuture = _fetchModels();
  _fetchOperation = CancelableOperation.fromFuture(refreshFuture);
  return refreshFuture;
}

// Deferred scroll state does not touch a disposed or detached controller.
if (!mounted || !_scrollController.hasClients) return;

// Large and mobile layouts both interpolate theme changes.
AnimatedTheme(
  duration: const Duration(milliseconds: 400),
  curve: Curves.easeInOutCubic,
  // ...
)

// Copy feedback restarts from the latest tap and cancels on disposal.
_copyFeedbackTimer?.cancel();
_copyFeedbackTimer = Timer(const Duration(seconds: 3), () {
  if (mounted) setState(() => _copied = false);
});
```

Expected: all four contracts are present and covered by the focused suite.

- [ ] **Step 4: Record the baseline in the eventual audit ledger**

Do not create the final ledger yet. Save these exact four entries for Task 7:

```markdown
| Model refresh indicator | `model_selection_bottom_sheet.dart` | Lifecycle | Fixed | Awaits `_fetchModels()` so the indicator lasts for the request |
| Scroll button deferred update | `chat_list_view.dart` | Lifecycle | Fixed | Guards `mounted` and `hasClients` |
| Large-layout mode theme | `main_page.dart` | Inconsistent | Fixed | Uses the same 400 ms `AnimatedTheme` contract as mobile |
| Copy feedback | `chat_bubble.dart` | Interruption | Fixed | Resettable timer survives repeated taps and cancels in `dispose` |
```

- [ ] **Step 5: Leave the baseline uncommitted until it is integrated with the related files**

Run:

```bash
git diff --check
```

Expected: no whitespace errors. Do not stage unrelated working-tree files.

---

### Task 2: Add Shared Motion Preferences Without Changing Normal Timings

**Files:**
- Create: `lib/Utils/motion.dart`
- Create: `test/utils/motion_test.dart`

**Interfaces:**
- Produces: `MotionDurations.quick`, `MotionDurations.standard`, `MotionDurations.emphasized`, `motionDuration(BuildContext, Duration)`, and `animationsDisabled(BuildContext)`.
- Consumed by: Tasks 3–6.

- [ ] **Step 1: Write the failing utility tests**

Create `test/utils/motion_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Utils/motion.dart';

void main() {
  testWidgets('motionDuration preserves normal timing', (tester) async {
    late Duration resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            resolved = motionDuration(context, MotionDurations.standard);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(resolved, MotionDurations.standard);
  });

  testWidgets('motionDuration settles immediately when animations are disabled',
      (tester) async {
    late Duration resolved;
    late bool disabled;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              disabled = animationsDisabled(context);
              resolved = motionDuration(context, MotionDurations.emphasized);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(disabled, isTrue);
    expect(resolved, Duration.zero);
  });
}
```

- [ ] **Step 2: Run the utility test to verify it fails**

Run:

```bash
flutter test --no-pub test/utils/motion_test.dart
```

Expected: FAIL because `lib/Utils/motion.dart` does not exist.

- [ ] **Step 3: Implement the minimal shared utility**

Create `lib/Utils/motion.dart`:

```dart
import 'package:flutter/material.dart';

abstract final class MotionDurations {
  static const quick = Duration(milliseconds: 200);
  static const standard = Duration(milliseconds: 300);
  static const emphasized = Duration(milliseconds: 400);
}

bool animationsDisabled(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

Duration motionDuration(BuildContext context, Duration normal) =>
    animationsDisabled(context) ? Duration.zero : normal;
```

- [ ] **Step 4: Run the utility test**

Run:

```bash
flutter test --no-pub test/utils/motion_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit the utility only**

Run:

```bash
git add lib/Utils/motion.dart test/utils/motion_test.dart
git diff --cached --check
git commit -m "feat: add reduced motion timing helpers"
```

Expected: one focused commit containing only the utility and its tests.

---

### Task 3: Make Chat Motion Interruptible and Reduced-Motion Safe

**Files:**
- Modify: `lib/Pages/chat_page/chat_page.dart`
- Modify: `lib/Pages/chat_page/subwidgets/chat_welcome.dart`
- Modify: `lib/Pages/chat_page/subwidgets/welcome_scaffold.dart`
- Modify: `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart`
- Modify: `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_think_block.dart`
- Modify: `lib/Pages/chat_page/subwidgets/chat_bubble/streaming_llama.dart`
- Modify: `lib/Pages/chat_page/subwidgets/chat_list_view.dart`
- Modify: `lib/Pages/main_page.dart`
- Modify: `test/regression/g05_bubble_stream_test.dart`
- Modify: `test/regression/g10_search_ui_test.dart`
- Modify: `test/regression/g14_large_theme_animation_test.dart`
- Modify: `test/regression/g15_misc_small_test.dart`
- Modify: `test/widgets/chat_list_view_test.dart`
- Create: `test/widgets/chat_motion_test.dart`

**Interfaces:**
- Consumes: `animationsDisabled` and `motionDuration` from Task 2.
- Produces: immediate reduced-motion chat states, cancelable thinking auto-collapse, guarded scroll animation, and a responsive user-bubble entrance.

- [ ] **Step 1: Write failing tests for reduced-motion welcome and bubble behavior**

Create `test/widgets/chat_motion_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/ollama_message.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_bubble/streaming_llama.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/chat_welcome.dart';
import 'package:llamaseek/Pages/chat_page/subwidgets/welcome_scaffold.dart';

Widget reducedMotionHost(Widget child) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('server welcome settles directly on its actionable state',
      (tester) async {
    await tester.pumpWidget(
      reducedMotionHost(
        const ChatWelcome(
          showingState: CrossFadeState.showFirst,
          secondChildScale: 0.0,
        ),
      ),
    );

    expect(find.text('Tap to configure a server address'), findsOneWidget);
    expect(find.text('Welcome to DriftPaca!'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('welcome scaffold skips its decorative entrance',
      (tester) async {
    await tester.pumpWidget(
      reducedMotionHost(
        WelcomeScaffold(
          eyebrow: 'WELCOME',
          title: 'Start a conversation',
          ctaLabel: 'Start',
          accent: Colors.blue,
          onCta: () {},
        ),
      ),
    );

    expect(
      tester.widget<Opacity>(find.byType(Opacity).first).opacity,
      1.0,
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('streaming answer renders its full current text with reduced motion',
      (tester) async {
    final message = OllamaMessage(
      'A complete current token batch.',
      role: OllamaMessageRole.assistant,
    );

    await tester.pumpWidget(
      reducedMotionHost(ChatBubble(message: message, isStreaming: true)),
    );
    await tester.pump();

    expect(
      find.textContaining(
        'complete current token batch',
        findRichText: true,
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(reducedMotionHost(const SizedBox.shrink()));
  });

  testWidgets('new user bubble begins entering on the next frame',
      (tester) async {
    final message = OllamaMessage(
      'New prompt',
      role: OllamaMessageRole.user,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatBubble(message: message, animate: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final entrance = tester.widget<FadeTransition>(
      find.byType(FadeTransition).first,
    );
    expect(entrance.opacity.value, greaterThan(0.0));
  });

  testWidgets('running llama is static with reduced motion', (tester) async {
    await tester.pumpWidget(
      reducedMotionHost(const StreamingLlama(isRunning: true)),
    );
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
```

- [ ] **Step 2: Add a failing interruption test for thinking auto-collapse**

Append to `test/regression/g10_search_ui_test.dart`:

```dart
testWidgets('manual expand wins over pending thinking auto-collapse',
    (tester) async {
  var complete = false;
  late StateSetter rebuild;

  await tester.pumpWidget(
    _host(
      StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;
          return ThinkBlockWidget(
            content: 'Reasoning',
            isComplete: complete,
            isStreaming: !complete,
          );
        },
      ),
    ),
  );

  complete = true;
  rebuild(() {});
  await tester.pump();
  await tester.tap(find.textContaining('Thought'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));

  final transition = tester.widget<SizeTransition>(find.byType(SizeTransition));
  expect(transition.sizeFactor.value, 1.0);
}
```

- [ ] **Step 3: Add a failing detached-scroll test**

Append to `test/widgets/chat_list_view_test.dart`:

```dart
testWidgets('scroll-to-latest ignores a detached scroll controller',
    (tester) async {
  final messages = <OllamaMessage>[
    OllamaMessage('Message', role: OllamaMessageRole.assistant),
  ];
  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        height: 300,
        child: ChatListView(
          messages: messages,
          isAwaitingReply: false,
        ),
      ),
    ),
  );

  final state = tester.state(find.byType(ChatListView)) as dynamic;
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  state.debugScrollToBottom();

  expect(tester.takeException(), isNull);
}
```

Expose only this test seam in `ChatListView`:

```dart
@visibleForTesting
void debugScrollToBottom() => _scrollToBottom();
```

- [ ] **Step 4: Run the new chat tests and verify the failures**

Run:

```bash
flutter test --no-pub \
  test/widgets/chat_motion_test.dart \
  test/regression/g10_search_ui_test.dart \
  test/widgets/chat_list_view_test.dart
```

Expected: FAIL because reduced motion is not handled, thinking auto-collapse can override a later tap, and `_scrollToBottom` reads a detached controller.

- [ ] **Step 5: Make welcome animations settle immediately when disabled**

In `chat_welcome.dart`, return the final actionable child when animations are disabled:

```dart
if (animationsDisabled(context)) {
  return _ChatConfigureServerAddressButton();
}
```

In `welcome_scaffold.dart`, synchronize the one-shot controller from dependencies:

```dart
@override
void didChangeDependencies() {
  super.didChangeDependencies();
  if (animationsDisabled(context)) {
    _entrance.value = 1.0;
  } else if (_entrance.value == 0.0 && !_entrance.isAnimating) {
    _entrance.forward();
  }
}
```

Create `_entrance` in `initState` without immediately calling `forward()`.

- [ ] **Step 6: Remove the delayed invisible user-bubble entrance**

Replace the 450 ms delayed start and 0.4 scale origin in `_UserBubbleEntranceState` with:

```dart
_controller = AnimationController(
  duration: const Duration(milliseconds: 280),
  vsync: this,
  value: widget.animate ? 0.0 : 1.0,
);
_scale = Tween<double>(begin: 0.92, end: 1.0).animate(
  CurvedAnimation(
    parent: _controller,
    curve: const Cubic(0.16, 1.0, 0.3, 1.0),
  ),
);
```

Start or settle it from `didChangeDependencies`:

```dart
if (!widget.animate || animationsDisabled(context)) {
  _controller.value = 1.0;
} else if (_controller.value == 0.0 && !_controller.isAnimating) {
  _controller.forward();
}
```

Expected: new messages remain expressive but begin responding on the next frame instead of staying invisible for 450 ms.

- [ ] **Step 7: Make assistant reveal and llama loops reduced-motion safe**

In `_AssistantBubbleState`, track `_animationsDisabled` from `didChangeDependencies`. When disabled:

```dart
_animationsDisabled = animationsDisabled(context);
if (_animationsDisabled) {
  _targetContent = widget.message.content;
  _targetThinking = _displayThinking(widget.message.thinking);
  _revealedLength = _targetContent.length;
  _revealedThinkingLength = _targetThinking.length;
  _revealProgress = _revealedLength.toDouble();
  _thinkingRevealProgress = _revealedThinkingLength.toDouble();
  _stopRevealTicker();
}
```

Before `_ensureRevealTicker()` starts a ticker, return after settling the full target when `_animationsDisabled` is true.

In `StreamingLlama`, add `_animationsDisabled`, update it in `didChangeDependencies`, and make `_applyMode()` stop at a valid static phase:

```dart
if (_animationsDisabled) {
  _controller.stop();
  _controller.value = widget.isRunning ? 0.0 : _sleepPhase;
  return;
}
```

- [ ] **Step 8: Make thinking completion cancelable**

Add:

```dart
Timer? _autoCollapseTimer;
bool _animationsDisabled = false;
late final Animation<double> _pulseOpacity;
```

Create `_pulseOpacity` once in `initState`. Replace the completion delay with:

```dart
_autoCollapseTimer?.cancel();
if (_userToggle == null && !widget.keepExpandedWhenComplete) {
  _autoCollapseTimer = Timer(
    motionDuration(context, const Duration(milliseconds: 300)),
    () {
      if (!mounted || _userToggle != null) return;
      setState(() => _userToggle = false);
      if (_animationsDisabled) {
        _expandController.value = 0.0;
      } else {
        _expandController.reverse();
      }
    },
  );
}
```

At the start of `_toggle()`:

```dart
_autoCollapseTimer?.cancel();
```

Cancel the timer in `dispose()`. Use `_pulseOpacity` in the `FadeTransition` instead of allocating a new tween animation in `build`.

- [ ] **Step 9: Guard and shorten scroll state changes under reduced motion**

Implement:

```dart
void _scrollToBottom() {
  if (!mounted || !_scrollController.hasClients) return;
  _scrollController.animateTo(
    0.0,
    duration: motionDuration(
      context,
      const Duration(milliseconds: 300),
    ),
    curve: Curves.easeOutCubic,
  );
}
```

Drive the floating button's scale curve from `showScrollButton`, not the stale raw scroll flag:

```dart
curve: showScrollButton ? Curves.easeOutBack : Curves.easeIn,
```

Use `motionDuration` for the button scale and opacity.

- [ ] **Step 10: Apply reduced-motion durations to the composer and search pulse**

In `chat_page.dart`, resolve the existing composer and incognito durations through `motionDuration(context, ...)`. Do not change their normal 400 ms and 300 ms values.

When `animationsDisabled(context)` is true, stop `_searchPulseController` and set its value to `0.0`; do not call `repeat`.

In both `AnimatedTheme` instances in `main_page.dart`, preserve the existing
400 ms normal duration and resolve it through:

```dart
duration: motionDuration(
  context,
  const Duration(milliseconds: 400),
),
```

Guard the focus post-frame callback:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (mounted) _inputFocusNode.requestFocus();
});
```

- [ ] **Step 11: Run the focused chat suite**

Run:

```bash
flutter test --no-pub \
  test/widgets/chat_motion_test.dart \
  test/regression/g05_bubble_stream_test.dart \
  test/regression/g10_search_ui_test.dart \
  test/regression/g14_large_theme_animation_test.dart \
  test/regression/g15_misc_small_test.dart \
  test/widgets/chat_list_view_test.dart \
  test/widgets/chat_bubble_test.dart \
  test/widgets/chat_page_prompt_tabs_test.dart
```

Expected: PASS, no pending timers or tickers at teardown.

- [ ] **Step 12: Commit only the chat-motion slice**

Run:

```bash
git add \
  lib/Pages/chat_page/chat_page.dart \
  lib/Pages/chat_page/subwidgets/chat_welcome.dart \
  lib/Pages/chat_page/subwidgets/welcome_scaffold.dart \
  lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart \
  lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_think_block.dart \
  lib/Pages/chat_page/subwidgets/chat_bubble/streaming_llama.dart \
  lib/Pages/chat_page/subwidgets/chat_list_view.dart \
  lib/Pages/main_page.dart \
  test/regression/g05_bubble_stream_test.dart \
  test/regression/g10_search_ui_test.dart \
  test/regression/g14_large_theme_animation_test.dart \
  test/regression/g15_misc_small_test.dart \
  test/widgets/chat_list_view_test.dart \
  test/widgets/chat_bubble_test.dart \
  test/widgets/chat_page_prompt_tabs_test.dart \
  test/widgets/chat_motion_test.dart
git diff --cached --check
git commit -m "fix: smooth and interrupt chat motion"
```

Expected: no QR images, power note, or unrelated layout tests are staged.

---

### Task 4: Stop Decorative Continuous Effects When Motion Is Disabled

**Files:**
- Create: `lib/Widgets/pulsing_icon.dart`
- Modify: `lib/Widgets/chat_drawer.dart`
- Modify: `lib/Widgets/memory_bottom_sheet.dart`
- Modify: `lib/Widgets/memory_status_indicator.dart`
- Modify: `lib/Widgets/floating_gradient_background.dart`
- Create: `test/widgets/pulsing_icon_test.dart`
- Modify: `test/regression/g07_memory_indicator_test.dart`
- Modify: `test/widgets/floating_gradient_background_test.dart`

**Interfaces:**
- Consumes: `animationsDisabled` from Task 2.
- Produces: `PulsingIcon`, a shared status indicator that is animated normally and static under reduced motion.

- [ ] **Step 1: Write the failing shared pulse tests**

Create `test/widgets/pulsing_icon_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Widgets/pulsing_icon.dart';

Widget host({required bool disabled}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disabled),
        child: const Scaffold(
          body: PulsingIcon(
            icon: Icons.auto_awesome,
            size: 20,
            color: Colors.blue,
          ),
        ),
      ),
    );

void main() {
  testWidgets('pulses while motion is enabled', (tester) async {
    await tester.pumpWidget(host(disabled: false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('renders static while motion is disabled', (tester) async {
    await tester.pumpWidget(host(disabled: true));
    await tester.pump();
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
```

- [ ] **Step 2: Add reduced-motion background and memory tests**

Append to `test/widgets/floating_gradient_background_test.dart`:

```dart
testWidgets('reduced motion paints generation without scheduling frames',
    (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: FloatingGradientBackground(
          meshA: Color(0xFF4FB4FF),
          meshB: Color(0xFFFF73B3),
          canvas: Color(0xFFF4E9FF),
          idleColor: Color(0xFFFFFFFF),
          isGenerating: true,
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.binding.hasScheduledFrame, isFalse);
});
```

Change the existing `_host` helper in
`test/regression/g07_memory_indicator_test.dart` to:

```dart
Widget _host(
  _FakeMemoryService service, {
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: ChangeNotifierProvider<MemoryService>.value(
        value: service,
        child: const Scaffold(body: MemoryStatusIndicator()),
      ),
    ),
  );
}
```

Then append:

```dart
testWidgets('reduced motion shows updating state without pulsing',
    (tester) async {
  final service = _FakeMemoryService()..setState(updating: true);
  await tester.pumpWidget(_host(service, disableAnimations: true));
  await tester.pump();

  expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  expect(tester.binding.hasScheduledFrame, isFalse);
});
```

- [ ] **Step 3: Run the continuous-effect tests to verify they fail**

Run:

```bash
flutter test --no-pub \
  test/widgets/pulsing_icon_test.dart \
  test/widgets/floating_gradient_background_test.dart \
  test/regression/g07_memory_indicator_test.dart
```

Expected: FAIL because `PulsingIcon` does not exist and existing loops ignore `disableAnimations`.

- [ ] **Step 4: Implement `PulsingIcon`**

Create `lib/Widgets/pulsing_icon.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:llamaseek/Utils/motion.dart';

class PulsingIcon extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color color;

  const PulsingIcon({
    super.key,
    required this.icon,
    required this.size,
    required this.color,
  });

  @override
  State<PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _opacity = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (animationsDisabled(context)) {
      _controller
        ..stop()
        ..value = 1.0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: Icon(widget.icon, size: widget.size, color: widget.color),
      );
}
```

- [ ] **Step 5: Replace both duplicate private pulse widgets**

In `chat_drawer.dart`, replace `_PulsingIcon` call sites with `PulsingIcon` and remove the private class.

In `memory_bottom_sheet.dart`, replace `_PulsingStarIcon` call sites with:

```dart
PulsingIcon(
  icon: Icons.auto_awesome,
  size: 20,
  color: colorScheme.primary,
)
```

Remove `_PulsingStarIcon` and its state class.

- [ ] **Step 6: Make `MemoryStatusIndicator` synchronize both service and motion state**

Change `_syncAnimation` to:

```dart
void _syncAnimation({
  required bool isUpdating,
  required bool disabled,
}) {
  if (disabled) {
    _controller
      ..stop()
      ..value = 1.0;
  } else if (isUpdating) {
    if (!_controller.isAnimating) _controller.repeat(reverse: true);
  } else {
    _controller
      ..stop()
      ..value = 0.0;
  }
}
```

Capture `final disabled = animationsDisabled(context);` and pass both values through the guarded post-frame callback.

- [ ] **Step 7: Make the mesh settle to a static valid state**

Add `_animationsDisabled` to `_FloatingGradientBackgroundState`. Synchronize it from `didChangeDependencies`:

```dart
void _syncMotionPreference() {
  final disabled = animationsDisabled(context);
  if (_animationsDisabled == disabled) return;
  _animationsDisabled = disabled;
  if (disabled) {
    _ticker.stop();
    _introActive = false;
    _mesh.welcome = false;
    _mesh.opacity = widget.isGenerating ? 1.0 : 0.0;
    _glassOpacity.value = _mesh.opacity;
    _repaint.value++;
  } else if (widget.isGenerating) {
    _resetClock = true;
    _ticker.start();
  } else if (widget.isWelcome) {
    _startWelcomeIntro();
  }
}
```

Ensure `_startWelcomeIntro` and all `didUpdateWidget` ticker starts return early or settle directly when `_animationsDisabled` is true.

- [ ] **Step 8: Run the focused continuous-effect suite**

Run:

```bash
flutter test --no-pub \
  test/widgets/pulsing_icon_test.dart \
  test/widgets/floating_gradient_background_test.dart \
  test/regression/g07_memory_indicator_test.dart \
  test/regression/g01_memory_sheet_test.dart
```

Expected: PASS and no scheduled frame for reduced-motion decorative effects.

- [ ] **Step 9: Commit the continuous-effect slice**

Run:

```bash
git add \
  lib/Widgets/pulsing_icon.dart \
  lib/Widgets/chat_drawer.dart \
  lib/Widgets/memory_bottom_sheet.dart \
  lib/Widgets/memory_status_indicator.dart \
  lib/Widgets/floating_gradient_background.dart \
  test/widgets/pulsing_icon_test.dart \
  test/widgets/floating_gradient_background_test.dart \
  test/regression/g07_memory_indicator_test.dart
git diff --cached --check
git commit -m "fix: stop decorative motion when disabled"
```

Expected: only continuous-effect files are committed.

---

### Task 5: Make Search Progress Transitions Reduced-Motion Safe

**Files:**
- Modify: `lib/Widgets/search_card.dart`
- Modify: `lib/Widgets/search_detail_dialog.dart`
- Modify: `lib/Pages/chat_page/subwidgets/chat_list_view.dart`
- Modify: `test/regression/g10_search_ui_test.dart`
- Modify: `test/widgets/chat_list_view_test.dart`

**Interfaces:**
- Consumes: Task 2 motion helpers.
- Produces: static reduced-motion pending states and zero-duration custom search dialogs when motion is disabled.

- [ ] **Step 1: Write reduced-motion search tests**

Append to `test/regression/g10_search_ui_test.dart`:

```dart
testWidgets('pending search rows are static when animations are disabled',
    (tester) async {
  final segment = SearchCardSegment(
    query: 'q',
    urls: [
      SearchURLStatus(
        url: 'https://example.com',
        domain: 'example.com',
        state: SearchURLState.pending,
      ),
    ],
  );

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: SearchCard(segment: segment)),
      ),
    ),
  );
  await tester.pump();

  expect(find.byType(Shimmer), findsNothing);
  expect(find.byIcon(Icons.hourglass_top_rounded), findsWidgets);
  expect(tester.binding.hasScheduledFrame, isFalse);
});
```

Import `package:shimmer/shimmer.dart`.

- [ ] **Step 2: Add reduced-motion skeleton and nested-dialog tests**

Append to `test/widgets/chat_list_view_test.dart`:

```dart
testWidgets('awaiting-reply skeleton is static when animations are disabled',
    (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: ChatListView(
            messages: [],
            isAwaitingReply: true,
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  expect(find.byType(Shimmer), findsNothing);
  expect(tester.binding.hasScheduledFrame, isFalse);
});
```

Add `import 'package:shimmer/shimmer.dart';`.

Add this observer near the top of `test/regression/g10_search_ui_test.dart`:

```dart
class _RecordingObserver extends NavigatorObserver {
  Route<dynamic>? pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed = route;
  }
}
```

Append this test:

```dart
testWidgets('full search-source dialog has zero transition duration '
    'when animations are disabled', (tester) async {
  final observer = _RecordingObserver();
  final segment = SearchCardSegment(
    query: 'q',
    isComplete: true,
    sources: [
      SearchSource(
        url: 'https://example.com',
        domain: 'example.com',
        title: 'Example source',
        content: 'Full source content',
      ),
    ],
  );

  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [observer],
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: SearchDetailDialog(segment: segment)),
      ),
    ),
  );
  await tester.drag(
    find.text('Example source'),
    const Offset(-100, 0),
  );
  await tester.pump();

  expect(observer.pushed!.transitionDuration, Duration.zero);
  expect(observer.pushed!.reverseTransitionDuration, Duration.zero);
});
```

- [ ] **Step 3: Run the search tests to verify they fail**

Run:

```bash
flutter test --no-pub \
  test/regression/g10_search_ui_test.dart \
  test/widgets/chat_list_view_test.dart
```

Expected: FAIL because shimmer/spinners still animate and custom durations ignore the motion preference.

- [ ] **Step 4: Make search-card controllers settle under reduced motion**

Add `_animationsDisabled`, synchronize it in `didChangeDependencies`, and set:

```dart
_entranceController.value = 1.0;
_expandController.value = _expanded ? 1.0 : 0.0;
```

when disabled. Otherwise keep the existing 250 ms entrance and 200 ms expansion.

Use `motionDuration` for `AnimatedRotation` and `_StatusGlyph`'s `AnimatedSwitcher`.

- [ ] **Step 5: Replace reduced-motion shimmer and spinners with static status**

In `_UrlRow`:

```dart
final disabled = animationsDisabled(context);
// ...
child: isPending && !disabled
    ? Shimmer.fromColors(/* existing colors and period */)
    : titleText,
```

In `_StatusGlyph` and the card header, use:

```dart
const Icon(
  Icons.hourglass_top_rounded,
  key: ValueKey('pending'),
  size: 13,
)
```

when animations are disabled; retain existing progress indicators normally.

In `ChatListView._buildSkeletonLoader`, return the existing static skeleton column without `Shimmer.fromColors` when animations are disabled.

- [ ] **Step 6: Respect reduced motion in `SearchDetailDialog` custom transitions**

Resolve all custom `showGeneralDialog` and slide-controller durations through `motionDuration`. When disabled, set the controller directly to its target rather than calling `forward`.

Normal durations and curves remain unchanged.

- [ ] **Step 7: Run the search suite**

Run:

```bash
flutter test --no-pub \
  test/regression/g10_search_ui_test.dart \
  test/widgets/chat_list_view_test.dart \
  test/integration/agentic_search_flow_test.dart
```

Expected: PASS; reduced-motion pending UI schedules no decorative frames.

- [ ] **Step 8: Commit the search slice**

Run:

```bash
git add \
  lib/Widgets/search_card.dart \
  lib/Widgets/search_detail_dialog.dart \
  lib/Pages/chat_page/subwidgets/chat_list_view.dart \
  test/regression/g10_search_ui_test.dart \
  test/widgets/chat_list_view_test.dart
git diff --cached --check
git commit -m "fix: stabilize search progress transitions"
```

Expected: one search-focused commit.

---

### Task 6: Smooth Model Selection, Custom Routes, and Local State Transitions

**Files:**
- Modify: `lib/Pages/model_select_page/model_select_page.dart`
- Modify: `lib/Pages/model_select_page/model_select_route.dart`
- Modify: `lib/Pages/model_select_page/subwidgets/logo_wheel.dart`
- Modify: `lib/Pages/model_select_page/subwidgets/wheel_center_disc.dart`
- Modify: `lib/preview_wheel.dart`
- Modify: `lib/Widgets/model_selection_bottom_sheet.dart`
- Modify: `lib/Widgets/glass_context_menu.dart`
- Modify: `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart`
- Modify: `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_image.dart`
- Modify: `lib/Widgets/chat_configure_bottom_sheet.dart`
- Modify: `lib/Pages/settings_page/subwidgets/themes_settings.dart`
- Modify: `test/model_select_page_test.dart`
- Modify: `test/regression/g09_model_sheet_test.dart`
- Modify: `test/widgets/themes_settings_test.dart`
- Create: `test/widgets/custom_route_motion_test.dart`
- Create: `test/widgets/chat_configure_motion_test.dart`

**Interfaces:**
- Consumes: Task 2 motion helpers.
- Produces: directionally correct route exits, immediate reduced-motion final states, direct wheel snapping when disabled, and animated advanced-settings layout.

- [ ] **Step 1: Add reduced-motion model-selection tests**

Append to `test/model_select_page_test.dart`:

```dart
testWidgets('reduced motion opens model info without an intermediate frame',
    (tester) async {
  _phoneSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: ModelSelectPage(models: _models),
      ),
    ),
  );

  await tester.tap(find.byIcon(Icons.info_outline));
  await tester.pump();

  expect(find.text('SPECIFICATIONS'), findsOneWidget);
});
```

Add a wheel test that taps a `BrandNode` under reduced motion, pumps one frame, and asserts the newly selected model label is already present without a pending frame.

Use this exact test:

```dart
testWidgets('reduced motion snaps a tapped wheel node in one frame',
    (tester) async {
  _phoneSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: ModelSelectPage(
          models: _models,
          currentModelName: 'qwen3:8b',
        ),
      ),
    ),
  );
  await tester.pump();

  await tester.tap(find.byType(BrandNode).last, warnIfMissed: false);
  await tester.pump();

  expect(find.text('llama3.2:3b'), findsWidgets);
});
```

- [ ] **Step 2: Add custom-route timing tests**

Create `test/widgets/custom_route_motion_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/model_capabilities.dart';
import 'package:llamaseek/Models/ollama_model.dart';
import 'package:llamaseek/Pages/model_select_page/model_select_route.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:provider/provider.dart';

class RecordingObserver extends NavigatorObserver {
  Route<dynamic>? pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed = route;
  }
}

class _RouteChatProvider extends ChangeNotifier implements ChatProvider {
  @override
  Future<List<OllamaModel>> fetchAvailableModels() async => [_model];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _model = OllamaModel(
  name: 'qwen3:8b',
  model: 'qwen3:8b',
  modifiedAt: DateTime(2024),
  size: 1,
  digest: 'digest',
  parameterSize: '8B',
  family: 'qwen',
  quantizationLevel: 'Q4_K_M',
  format: 'gguf',
  contextLength: 32768,
  capabilities: const ModelCapabilities(completion: true),
);

Widget _host({
  required RecordingObserver observer,
  required bool disableAnimations,
}) {
  return ChangeNotifierProvider<ChatProvider>.value(
    value: _RouteChatProvider(),
    child: MaterialApp(
      navigatorObservers: [observer],
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModelSelectWheel(context: context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('model route preserves its normal timing', (tester) async {
    final observer = RecordingObserver();
    await tester.pumpWidget(
      _host(observer: observer, disableAnimations: false),
    );
    await tester.tap(find.text('open'));
    await tester.pump();

    expect(
      observer.pushed!.transitionDuration,
      const Duration(milliseconds: 340),
    );
    expect(
      observer.pushed!.reverseTransitionDuration,
      const Duration(milliseconds: 240),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('model route has zero timing with reduced motion',
      (tester) async {
    final observer = RecordingObserver();
    await tester.pumpWidget(
      _host(observer: observer, disableAnimations: true),
    );
    await tester.tap(find.text('open'));
    await tester.pump();

    expect(observer.pushed!.transitionDuration, Duration.zero);
    expect(observer.pushed!.reverseTransitionDuration, Duration.zero);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
```

- [ ] **Step 3: Add an advanced-settings layout test**

Create `test/widgets/chat_configure_motion_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llamaseek/Models/chat_configure_arguments.dart';
import 'package:llamaseek/Providers/chat_provider.dart';
import 'package:llamaseek/Widgets/chat_configure_bottom_sheet.dart';
import 'package:provider/provider.dart';

class _ConfigureChatProvider extends ChangeNotifier implements ChatProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host({required bool disableAnimations}) {
  return ChangeNotifierProvider<ChatProvider>.value(
    value: _ConfigureChatProvider(),
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(
          body: ChatConfigureBottomSheet(
            arguments: ChatConfigureArguments.defaultArguments,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('advanced settings expand smoothly after layout',
      (tester) async {
    await tester.pumpWidget(_host(disableAnimations: false));
    await tester.tap(find.text('Show Advanced Configurations'));
    await tester.pump();

    expect(find.byType(AnimatedSize), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Max Tokens'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('advanced settings settle immediately with reduced motion',
      (tester) async {
    await tester.pumpWidget(_host(disableAnimations: true));
    await tester.tap(find.text('Show Advanced Configurations'));
    await tester.pump();

    expect(find.text('Max Tokens'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 4: Run the new model and route tests to verify failures**

Run:

```bash
flutter test --no-pub \
  test/model_select_page_test.dart \
  test/widgets/custom_route_motion_test.dart \
  test/widgets/chat_configure_motion_test.dart
```

Expected: FAIL because controller-based model motion, routes, and advanced-layout changes do not yet resolve reduced motion.

- [ ] **Step 5: Make model page controllers settle directly**

In `ModelSelectPage`:

```dart
void _openInfo() {
  // existing geometry capture
  if (animationsDisabled(context)) {
    _infoCtrl.value = 1.0;
  } else {
    _infoCtrl.forward();
  }
}

void _closeInfo() {
  if (animationsDisabled(context)) {
    _infoCtrl.value = 0.0;
  } else {
    _infoCtrl.reverse();
  }
}
```

Resolve the brand-color `TweenAnimationBuilder` duration with `motionDuration`.

- [ ] **Step 6: Make the logo wheel direct and static under reduced motion**

Track `_animationsDisabled` in `didChangeDependencies`.

When disabled:

```dart
_entrance.value = 1.0;
```

and replace `_animateRotation`'s controller path with:

```dart
if (_animationsDisabled) {
  _setRotation(target);
  return;
}
```

In `_NotchPulse`, skip `forward(from: 0)` and keep value `1.0` when disabled.

Use `motionDuration` for `WheelCenterDisc`'s `AnimatedSwitcher`.

- [ ] **Step 7: Make model routes directionally correct and reduced-motion aware**

In both `model_select_route.dart` and `preview_wheel.dart`:

```dart
final disabled = animationsDisabled(context);
return Navigator.of(context).push<OllamaModel>(
  PageRouteBuilder<OllamaModel>(
    transitionDuration:
        disabled ? Duration.zero : const Duration(milliseconds: 340),
    reverseTransitionDuration:
        disabled ? Duration.zero : const Duration(milliseconds: 240),
    // ...
    transitionsBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
      child: child,
    ),
  ),
);
```

- [ ] **Step 8: Apply the same reduced-motion rule to custom overlays**

Use `motionDuration(context, existingDuration)` for:

- `showGlassContextMenu`;
- `_showEditPopup`;
- custom model-information dialogs in `model_selection_bottom_sheet.dart`;
- image-gallery `PageRouteBuilder`;
- image-gallery snap-back controller;
- theme swatch `AnimatedContainer`.

Do not alter the existing normal durations or curves except adding a matching `reverseCurve` where a custom route currently reuses an entrance-only curve on exit.

- [ ] **Step 9: Animate advanced settings after layout, not inside `setState`**

Change the button to update state only:

```dart
onPressed: () {
  setState(() {
    _showAdvancedConfigurations = !_showAdvancedConfigurations;
  });
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.animateTo(
      _showAdvancedConfigurations
          ? _scrollController.position.maxScrollExtent
          : _scrollController.position.minScrollExtent,
      duration: motionDuration(
        context,
        const Duration(milliseconds: 400),
      ),
      curve: Curves.easeOutCubic,
    );
  });
},
```

Wrap the advanced field column in:

```dart
AnimatedSize(
  duration: motionDuration(
    context,
    const Duration(milliseconds: 300),
  ),
  curve: Curves.easeOutCubic,
  alignment: Alignment.topCenter,
  child: _showAdvancedConfigurations
      ? Column(children: advancedConfigurationFields)
      : const SizedBox.shrink(),
)
```

Keep the existing field widgets and callbacks unchanged.

- [ ] **Step 10: Run the model/navigation/local-transition suite**

Run:

```bash
flutter test --no-pub \
  test/model_select_page_test.dart \
  test/widgets/custom_route_motion_test.dart \
  test/widgets/chat_configure_motion_test.dart \
  test/regression/g09_model_sheet_test.dart \
  test/widgets/themes_settings_test.dart \
  test/widgets/chat_bubble_test.dart
```

Expected: PASS.

- [ ] **Step 11: Commit the model/navigation slice**

Run:

```bash
git add \
  lib/Pages/model_select_page/model_select_page.dart \
  lib/Pages/model_select_page/model_select_route.dart \
  lib/Pages/model_select_page/subwidgets/logo_wheel.dart \
  lib/Pages/model_select_page/subwidgets/wheel_center_disc.dart \
  lib/preview_wheel.dart \
  lib/Widgets/model_selection_bottom_sheet.dart \
  lib/Widgets/glass_context_menu.dart \
  lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart \
  lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_image.dart \
  lib/Widgets/chat_configure_bottom_sheet.dart \
  lib/Pages/settings_page/subwidgets/themes_settings.dart \
  test/model_select_page_test.dart \
  test/regression/g09_model_sheet_test.dart \
  test/widgets/themes_settings_test.dart \
  test/widgets/custom_route_motion_test.dart \
  test/widgets/chat_configure_motion_test.dart
git diff --cached --check
git commit -m "fix: align model and route motion"
```

Expected: only files in this slice are committed.

---

### Task 7: Complete the Audit Ledger and Verify the Whole Change

**Files:**
- Create: `docs/ui_animation_audit_2026-07-19.md`
- Verify: every implementation and test file changed in Tasks 1–6.

**Interfaces:**
- Consumes: all findings and test evidence from Tasks 1–6.
- Produces: the final coverage ledger and verification record.

- [ ] **Step 1: Create the complete inventory**

Create `docs/ui_animation_audit_2026-07-19.md` with this header and table shape:

```markdown
# UI Animation Audit — 2026-07-19

## Method

Every explicit animation, implicit animation, custom route, scroll animation,
repeating controller, ticker, shimmer, and timer-driven visual state under
`lib/Pages` and `lib/Widgets` was mapped and classified. Normal visual styling
was preserved; fixes target interruption, lifecycle, reduced motion, and
avoidable per-frame work.

## Findings

| Surface | File | Category | Decision | Evidence |
|---|---|---|---|---|
```

Include one row for every file returned by:

```bash
rg -l --glob '*.dart' \
  'Animated[A-Z]|AnimationController|Tween|PageRouteBuilder|FadeTransition|SlideTransition|ScaleTransition|AnimatedSwitcher|AnimatedCrossFade|TweenAnimationBuilder|animateTo\\(|Shimmer|FloatingGradient|createTicker|Timer\\.' \
  lib/Pages lib/Widgets | sort
```

Each row must say either `Fixed` with a test/behavior reference or `Verified unchanged` with the reason no modification was warranted. Do not use `TBD`, `TODO`, or blank evidence.

- [ ] **Step 2: Add a reduced-motion coverage section**

Document these exact guarantees:

```markdown
## Reduced Motion Guarantees

- Decorative welcome, pulse, shimmer, mesh, wheel-entrance, and llama loops
  settle without scheduling continuous frames.
- Essential content and status remain visible in their final state.
- User-triggered expand/collapse and route changes complete immediately.
- Normal motion keeps its existing durations and visual character.
```

- [ ] **Step 3: Run all focused animation tests**

Run:

```bash
flutter test --no-pub \
  test/utils/motion_test.dart \
  test/widgets/chat_motion_test.dart \
  test/widgets/pulsing_icon_test.dart \
  test/widgets/floating_gradient_background_test.dart \
  test/widgets/custom_route_motion_test.dart \
  test/widgets/chat_configure_motion_test.dart \
  test/model_select_page_test.dart \
  test/regression/g05_bubble_stream_test.dart \
  test/regression/g07_memory_indicator_test.dart \
  test/regression/g09_model_sheet_test.dart \
  test/regression/g10_search_ui_test.dart \
  test/regression/g14_large_theme_animation_test.dart \
  test/regression/g15_misc_small_test.dart \
  test/widgets/chat_bubble_test.dart \
  test/widgets/chat_list_view_test.dart \
  test/widgets/chat_page_prompt_tabs_test.dart \
  test/widgets/themes_settings_test.dart
```

Expected: PASS.

- [ ] **Step 4: Run broad static verification**

Run:

```bash
dart analyze
git diff --check
```

Expected: analyzer exits successfully and the diff has no whitespace errors. If unrelated pre-existing analyzer failures appear, record their exact messages and verify no changed file introduces a new error.

- [ ] **Step 5: Check repository hygiene**

Run:

```bash
git status --short --untracked-files=all
git diff --stat HEAD^
git diff --name-only HEAD^
```

Expected:

- `pubspec.lock` is unchanged.
- No generated files are added.
- `debug-high-power-usage.md`, both QR images, `test/widgets/chat_app_bar_mobile_test.dart`, and `test/widgets/chat_page_safe_area_test.dart` remain outside this task's commits.
- No broad whitespace-only churn appears.

- [ ] **Step 6: Commit the final audit ledger**

Run:

```bash
git add docs/ui_animation_audit_2026-07-19.md
git diff --cached --check
git commit -m "docs: record UI animation audit"
```

Expected: one documentation-only commit.

- [ ] **Step 7: Perform the completion check**

Confirm:

```text
Correctness: every changed behavior has a focused regression test.
Completeness: every animation-bearing file appears in the audit ledger.
Grounding: findings cite code inspection or test evidence.
Formatting: no broad formatter churn or ignored artifacts were staged.
Safety: no external side effect, dependency update, push, or release occurred.
```

Expected: all five checks are true before reporting completion.
