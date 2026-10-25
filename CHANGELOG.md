## 0.1.0

A full port of react-native-keyboard-controller, replacing the
interactive-drag-only 0.0.1.

### Added

* `KeyboardController` — keyboard state, per-frame handlers, will/did
  notifications, `dismiss` (with `keepFocus` / `animated`), `setFocusTo`,
  `setInputMode` / `setDefaultMode`, `preload`, `setTranslucent`, keyboard
  colour and corner radius.
* Focused-input observation that works with plain Flutter text fields: rect,
  text, caret geometry and prev/next traversal, all read from the Flutter focus
  tree rather than from native views.
* `KeyboardAwareScrollView`, `KeyboardToolbar`, `KeyboardStickyView`,
  `KeyboardGestureArea`, `KeyboardStateBuilder`, `OverKeyboardView`,
  `KeyboardExtender`, `KeyboardEffects`, `KeyboardBackgroundView`.
* Native keyboard tracking on both platforms: `WindowInsetsAnimation` on
  Android (emulated below API 30), `CADisplayLink` plus a modelled animation
  curve on iOS.
* Interactive drag-to-dismiss on iOS, via a pan recognizer on the keyboard
  window. Experimental.
* Frames synthesized from `viewInsets` where the plugin has no native half, so
  the widgets work on web, desktop and in widget tests.
* `setEnabled` / `enabled` — stop and resume tracking, handing the keyboard
  back to the platform default. RNKC's `useKeyboardController`.

### Changed

* `KeyboardAnimationBuilder`'s builder now receives a `KeyboardEvent` (height,
  progress, duration, target) instead of a bare height.
* `KeyboardAvoidingView` takes a `behavior` and measures its own position on
  screen, instead of always padding by the full keyboard height.
* `KeyboardController` is an instance (`KeyboardController.instance`) rather
  than a namespace of context-based statics; `KeyboardState` now carries the
  full platform payload.
* `InteractiveKeyboard.enable()` gained `interpolator`, `showOnSwipeUp` and
  `enableSwipeToDismiss`, and is now supported on iOS.

## 0.0.1

* Interactive keyboard drag-to-dismiss on Android (API 30+), ported from
  react-native-keyboard-controller's `KeyboardGestureArea`.
* Keyboard tracking helpers: `KeyboardController`, `KeyboardAvoidingView`,
  `KeyboardAnimationBuilder`.
* iOS interactive drag not implemented.
