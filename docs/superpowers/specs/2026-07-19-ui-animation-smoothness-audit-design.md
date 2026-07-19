# UI Animation Smoothness Audit Design

**Date:** 2026-07-19

## Objective

Audit every user-triggered and continuous UI animation in DriftPaca, then fix confirmed smoothness, consistency, lifecycle, accessibility, and frame-cost problems without changing the app's visual personality.

The audit covers all supported platforms and the mobile, tablet, and desktop breakpoints. Existing uncommitted fixes from the earlier animation audit remain part of the baseline and must not be overwritten or reformatted broadly.

## Chosen Approach

Use an evidence-led surface audit rather than globally replacing durations and curves or redesigning the motion language.

For each animation surface:

1. Identify its trigger, controller or implicit animation, duration, curve, and teardown behavior.
2. Exercise the start, interrupted, reversed, repeated, and disposed states that the surface supports.
3. Classify it as correct, abrupt, inconsistent, lifecycle-unsafe, accessibility-unsafe, or frame-costly.
4. Change only confirmed defects or repeated inconsistencies.
5. Add focused regression coverage for each changed behavior.

Shared motion constants may be introduced only when at least two related surfaces need the same semantic timing. One-off effects retain local values when centralization would add indirection without improving consistency.

## Scope

### User-Triggered Motion

- Route pushes and pops.
- Dialog, context-menu, and bottom-sheet presentation and dismissal.
- Composer expansion and collapse.
- Welcome-state transitions.
- Chat bubble entrance, reveal, thinking-block expansion, image interaction, and action feedback.
- Chat scrolling and scroll-to-bottom affordances.
- Model-selection wheel, cards, dialogs, and selection feedback.
- Search-card expansion, progress changes, and completion states.
- Theme and incognito transitions.
- Settings controls and color selection.

### Continuous Motion

- Floating mesh-gradient backgrounds.
- Loading indicators, shimmers, and pulses.
- Streaming text and llama indicators.
- Memory status animations.
- Any repeating `AnimationController`, ticker, shader animation, or timer-driven visual state.

### Cross-Cutting Requirements

- Preserve current visual effects and product personality.
- Prefer micro-optimizations over reducing fidelity.
- Respect `MediaQuery.disableAnimations` for decorative and nonessential motion.
- Keep essential state changes understandable when animations are disabled.
- Avoid controller, ticker, timer, listener, and post-frame callback leaks.
- Handle repeated taps, reversals, route dismissal, and widget disposal safely.
- Avoid broad refactors, dependency additions, and repository-wide formatting.

## Architecture

### Animation Inventory

Create an audit table in a dedicated document. Each row records:

- Surface and file.
- Trigger and user-visible purpose.
- Current animation primitive.
- Duration and curve.
- Repeat or interruption behavior.
- Reduced-motion behavior.
- Finding and severity.
- Verification evidence.
- Resulting action.

The inventory is the coverage source of truth. A surface is complete only after it is classified and either verified unchanged or linked to a tested fix.

### Motion Semantics

Keep the current local architecture. Introduce a small shared motion utility only if the inventory confirms repeated inconsistencies across related surfaces.

If justified, the utility exposes semantic values rather than widget-specific names:

- quick feedback for icon and state changes;
- standard transition for local layout and visibility changes;
- emphasized transition for routes and major mode changes;
- standard entrance, exit, and emphasized curves;
- a reduced-motion duration resolver.

Widgets remain responsible for their own animation composition. The utility must not become a global animation framework or force visually distinct effects to share identical timings.

### Runtime Behavior

Animation state remains local to each widget:

1. A user action or provider update changes semantic state.
2. The widget resolves normal or reduced-motion timing from `MediaQuery`.
3. Existing implicit animations or controllers move toward the new state.
4. Repeated and reversed actions continue from the current animation value where possible instead of snapping or restarting from an endpoint.
5. Disposal cancels timers and tickers and prevents deferred callbacks from reading detached controllers.

Continuous effects run only while useful and visible. They pause or stop when their semantic loading state ends, when the widget is disposed, or when reduced motion disables a decorative loop.

## Finding Categories

### Abrupt

A visible state or geometry change snaps even though nearby or inverse behavior animates. Fix with the smallest suitable implicit or explicit transition.

### Inconsistent

Related surfaces use noticeably conflicting timings, curves, or entrance and exit behavior. Align semantically related transitions without flattening intentional differences.

### Lifecycle-Unsafe

A timer, ticker, listener, post-frame callback, or scroll operation can outlive its widget or detached controller. Cancel or guard the work and add an interruption regression test.

### Frame-Costly

An animation performs avoidable work per frame, such as allocating animation wrappers in builders, rebuilding static subtrees, running hidden loops, or recalculating invariant values. Hoist invariants, isolate repaints, pass static children, or stop off-state controllers while preserving output.

### Accessibility-Unsafe

Decorative motion ignores `MediaQuery.disableAnimations`, or disabling animation leaves an intermediate or confusing state. Decorative loops stop; essential transitions settle immediately to their final state.

## Error and Interruption Handling

- Async refresh and loading animations remain active until their underlying futures complete.
- Scroll animations verify `mounted` and `hasClients` before reading or moving a controller.
- Post-frame callbacks verify that their state and controller are still valid.
- Temporary feedback timers restart on repeated interaction and cancel in `dispose`.
- Animation callbacks check that the widget is still mounted before updating state.
- Route and sheet dismissal cannot leave repeating controllers or pending state updates behind.
- Reduced-motion changes during a widget's lifetime settle the animation into a valid state.

## Testing

### Widget Regression Tests

Every changed surface receives a focused test that verifies the defect, not merely the presence of an animation widget. Depending on the finding, tests inspect:

- the intermediate state before the duration elapses;
- the final state after completion;
- repeated or reversed interaction;
- removal or dismissal during a pending callback;
- controller and timer cleanup;
- reduced-motion final-state behavior;
- mobile, tablet, and desktop breakpoint behavior.

Exact duration assertions are limited to semantic timing contracts. Tests should prefer observable state and geometry so harmless implementation changes do not make the suite brittle.

### Static and Focused Validation

- Run the smallest relevant test file first.
- Run the complete changed-surface suite with `flutter test --no-pub`.
- Run `dart analyze` after focused tests pass.
- Check `git diff --check`.
- Inspect the final diff for accidental lockfile, generated-file, image, or broad formatting changes.

Do not run package resolution unless a dependency change becomes necessary; this design does not require one.

### Performance Verification

For continuous or frame-sensitive surfaces:

- confirm that inactive controllers stop;
- confirm static children are not rebuilt unnecessarily;
- confirm per-frame builders do not allocate avoidable animation objects;
- use targeted Flutter performance diagnostics when a static inspection or widget test cannot establish the finding;
- preserve appearance unless measured evidence shows that fidelity itself is the bottleneck.

## Deliverables

1. A complete animation inventory with findings and evidence.
2. Surgical fixes for every confirmed issue in the inventory.
3. Focused regression tests for each behavior change.
4. A concise summary of unchanged surfaces that were inspected and judged correct.
5. Verification results and any platform-specific limitations that could not be exercised locally.

## Non-Goals

- Rebranding the app's motion style.
- Replacing Flutter's animation system or adding a third-party motion package.
- Removing mesh, shimmer, pulse, or reveal effects solely to reduce work.
- Fixing unrelated layout, business-logic, or rendering defects discovered during the audit.
- Refactoring large widgets unless a narrow extraction is required to make an animation safe or testable.
