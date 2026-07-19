# UI Animation Audit — 2026-07-19

## Method

Every explicit animation, implicit animation, custom route, scroll animation,
repeating controller, ticker, shimmer, and timer-driven visual state under
`lib/Pages`, `lib/Widgets`, and `lib/preview_wheel.dart` was mapped and
classified.

The audit exercised normal motion, reduced motion, repeated interaction,
interruption, route dismissal, widget disposal, async completion, and detached
controller paths. Existing visual styling and normal durations were preserved
unless a confirmed delay or inconsistency caused visible jank.

## Findings

| Surface | File | Category | Decision | Evidence |
|---|---|---|---|---|
| Composer, incognito badge, and search pulse | `lib/Pages/chat_page/chat_page.dart` | Accessibility / lifecycle | Fixed | Existing durations resolve through `motionDuration`; decorative pulse stops under reduced motion; focus callback checks `mounted`. Covered by `chat_motion_test.dart` and `chat_page_prompt_tabs_test.dart`. |
| User entrance, assistant reveal/actions, copy/edit feedback, and link favicon | `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble.dart` | Abrupt / interruption / accessibility | Fixed | Removed the 450 ms invisible entrance delay, reduced scale travel, settled typewriter/action/copy/edit/favicon motion when disabled, and retained resettable copy feedback. Covered by `chat_motion_test.dart`, `chat_bubble_test.dart`, and `g05_bubble_stream_test.dart`. |
| Gallery route, drag snap-back, and page dots | `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_image.dart` | Accessibility / route boundary | Fixed | Route timing resolves to zero and the caller’s preference is propagated into the pushed page; snap-back and dots settle directly. Covered by `g06_bubble_image_test.dart`. |
| Thinking pulse, expand/collapse, and completion delay | `lib/Pages/chat_page/subwidgets/chat_bubble/chat_bubble_think_block.dart` | Interruption / frame cost | Fixed | Reused the pulse animation, replaced uncancelable delayed collapse with a timer, and let manual interaction cancel pending collapse. Covered by `g10_search_ui_test.dart`. |
| Streaming and resting llama | `lib/Pages/chat_page/subwidgets/chat_bubble/streaming_llama.dart` | Accessibility / continuous motion | Fixed | Running and sleep animations stop at valid static phases under reduced motion; app lifecycle resume uses the same state synchronizer. Covered by `chat_motion_test.dart`. |
| Scroll affordance, scroll animation, and awaiting-reply skeleton | `lib/Pages/chat_page/subwidgets/chat_list_view.dart` | Lifecycle / accessibility | Fixed | Deferred and direct scroll paths guard `mounted` and `hasClients`; button timing resolves through the motion preference; reduced motion uses a static skeleton. Covered by `chat_list_view_test.dart`. |
| Unconfigured-server welcome sequence | `lib/Pages/chat_page/subwidgets/chat_welcome.dart` | Accessibility | Fixed | Reduced motion skips decorative typing/cross-fade and renders the actionable final state. Covered by `chat_motion_test.dart`. |
| Normal and incognito welcome entrance | `lib/Pages/chat_page/subwidgets/welcome_scaffold.dart` | Accessibility / frame cost | Fixed | One-shot controller starts after dependencies are known and settles immediately when animations are disabled; existing stagger remains unchanged normally. Covered by `chat_motion_test.dart` and `g15_misc_small_test.dart`. |
| Mobile and large-layout theme interpolation | `lib/Pages/main_page.dart` | Inconsistent / accessibility | Fixed | Large layout now matches mobile `AnimatedTheme`; both keep the 400 ms normal transition and resolve to zero under reduced motion. Covered by `g14_large_theme_animation_test.dart`. |
| Model tint and info overlay | `lib/Pages/model_select_page/model_select_page.dart` | Accessibility | Fixed | Brand tint, info open, and info close settle directly when motion is disabled. Covered by `model_select_page_test.dart`. |
| Production model-selector route | `lib/Pages/model_select_page/model_select_route.dart` | Route / accessibility | Fixed | Preserved 340/240 ms normal timing, added an exit curve, and uses zero forward/reverse durations under reduced motion. Covered by `custom_route_motion_test.dart`. |
| Model wheel entrance, momentum, snap, and notch pulse | `lib/Pages/model_select_page/subwidgets/logo_wheel.dart` | Accessibility / interaction | Fixed | Reduced motion skips entrance/pulse and snaps selection directly; normal drag, momentum, haptics, and timing are preserved. Covered by `model_select_page_test.dart`. |
| Model center-disc content switch | `lib/Pages/model_select_page/subwidgets/wheel_center_disc.dart` | Accessibility | Fixed | Existing 320 ms switch resolves to zero under reduced motion. Covered by `model_select_page_test.dart`. |
| Theme preset swatch | `lib/Pages/settings_page/subwidgets/themes_settings.dart` | Accessibility / persistence | Fixed | Existing 200 ms swatch transition resolves to zero; gradient writes are now one atomic awaited Hive operation so UI/test transitions do not overlap persistence. Covered by `themes_settings_test.dart`, `gradient_settings_test.dart`, and `g15_misc_small_test.dart`. |
| Advanced chat settings reveal and scroll | `lib/Widgets/chat_configure_bottom_sheet.dart` | Abrupt / lifecycle / accessibility | Fixed | Advanced fields use `AnimatedSize` normally, render directly under reduced motion, and scroll only after layout with controller guards. Covered by `chat_configure_motion_test.dart`. |
| Full-screen mesh and welcome breathe | `lib/Widgets/floating_gradient_background.dart` | Continuous motion / frame cost | Fixed | Existing 24 fps throttle and idle stop remain; reduced motion renders a valid static generating/idle state and starts no ticker. Covered by `floating_gradient_background_test.dart`. |
| Liquid-glass context menu | `lib/Widgets/glass_context_menu.dart` | Route / accessibility | Fixed | Existing 250 ms scale/fade remains normally and resolves to a zero-duration route when disabled. Covered by `glass_context_menu_test.dart`. |
| Memory content switch and update pulse | `lib/Widgets/memory_bottom_sheet.dart` | Accessibility / duplication | Fixed | Flat-editor switch resolves to zero across the modal route boundary; duplicate private pulse controller was replaced by `PulsingIcon`. Covered by `g01_memory_sheet_test.dart`. |
| Memory status pulse | `lib/Widgets/memory_status_indicator.dart` | Continuous motion / accessibility | Fixed | Service state and motion preference are synchronized after build; reduced motion shows the updating state without scheduling pulse frames. Covered by `g07_memory_indicator_test.dart`. |
| Model-sheet refresh, drag snap-back, and info dialog | `lib/Widgets/model_selection_bottom_sheet.dart` | Async / frame cost / accessibility | Fixed | Refresh awaits the request, transition curves are reused, snap-back settles directly, and info route timing resolves to zero. Covered by `g09_model_sheet_test.dart`. |
| Shared status pulse | `lib/Widgets/pulsing_icon.dart` | Continuous motion / duplication | Fixed | Consolidated drawer and memory pulse implementations; runs normally and renders a static final state when disabled. Covered by `pulsing_icon_test.dart`. |
| Search-card entrance, expansion, pending rows, glyphs, and shimmer | `lib/Widgets/search_card.dart` | Accessibility / continuous motion | Fixed | Controllers settle directly, shimmer/spinners become static hourglass states, and switch/rotation durations resolve to zero. Covered by `g10_search_ui_test.dart`. |
| Search source snap-back, full dialog, and favicon pop | `lib/Widgets/search_detail_dialog.dart` | Route / accessibility | Fixed | Snap-back and dialog route settle directly, and uncached favicon arrival no longer starts a pop under reduced motion. Covered by `g10_search_ui_test.dart`. |
| Model-selector preview route | `lib/preview_wheel.dart` | Consistency / accessibility | Fixed | Preview now mirrors production 340/240 ms timing, reverse curve, and zero-duration reduced-motion behavior. Verified by source comparison with `model_select_route.dart`. |

## Framework Motion Verified Unchanged

- Standard `showDialog` and `showModalBottomSheet` calls without custom
  controllers continue to use Flutter’s platform motion and accessibility
  handling.
- Material button ink responses and `Hero` image interpolation remain framework
  managed.
- One-shot favicon pops still run after genuine network arrival when motion is
  enabled; cached favicons render immediately.
- The mesh background, shimmers, pulses, and streaming indicators retain their
  existing normal visual fidelity.

## Reduced Motion Guarantees

- Decorative welcome, pulse, shimmer, mesh, wheel-entrance, favicon-pop, and
  llama loops settle without scheduling continuous frames.
- Essential content and status remain visible in their final state.
- User-triggered expand/collapse, local switches, snap-back, and custom routes
  complete immediately.
- Motion preference is propagated explicitly across custom modal and pushed
  route boundaries where a nested `MediaQuery` would otherwise be lost.
- Normal motion keeps its existing durations and visual character except for
  the confirmed 450 ms invisible user-bubble delay, which was removed.

## Verification Limits

- `test/integration/agentic_search_flow_test.dart` requires
  `OLLAMA_CLOUD_API_KEY`; it could not run in this environment. Local search UI
  and state tests passed.
- Repo-wide `dart analyze` reports pre-existing warnings and info-level lints.
  Filtered analysis found no new errors in changed files; the remaining
  changed-file warnings are existing optional-key warnings in
  `chat_configure_bottom_sheet.dart` and existing test dependency lints.
