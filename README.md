# keyboard_controller

A Flutter port of
[react-native-keyboard-controller](https://github.com/kirillzyusko/react-native-keyboard-controller):
frame-synced keyboard tracking, keyboard-aware layout and scrolling,
interactive drag-to-dismiss, and focused-input observation.

It works with ordinary Flutter text fields. No special widget replaces
`TextField`, no controller has to be threaded through your tree.

```dart
KeyboardAwareScrollView(
  bottomOffset: 20,
  child: Column(children: const [TextField(), TextField(), TextField()]),
)
```

## Why not just `MediaQuery.viewInsets`?

Because `viewInsets` tells you where the keyboard **is**, and almost everything
useful needs more than that:

| You want | `viewInsets` | this package |
|---|---|---|
| current keyboard height | ✅ | ✅ |
| where the keyboard is **going**, before it moves | ❌ | `onStart` |
| how long the transition will take | ❌ | `duration` |
| finger-driven movement | ❌ | `onInteractive` |
| keyboard appearance (light/dark) and type | ❌ | `KeyboardState` |
| the focused field's rect and caret position | ❌ | `focusedInput` |
| hide the keyboard but keep the caret | ❌ | `dismiss(keepFocus: true)` |
| hide it with no animation | ❌ | `dismiss(animated: false)` |
| `windowSoftInputMode` on Android | ❌ | `setInputMode` |

Knowing the destination before the animation starts is what separates scrolling
a field into view *with* the keyboard from scrolling it *after* the keyboard.

## Install

```yaml
dependencies:
  keyboard_controller: ^0.1.0
```

Nothing to initialise. The first use of `KeyboardController.instance` attaches
the platform observers and starts watching the focus tree.

## Widgets

### `KeyboardAwareScrollView`

Keeps the focused field — and the caret inside it — above the keyboard, moving
in step with the keyboard animation. Caret-aware, so a growing multiline field
keeps the line you are typing visible rather than its whole box.

```dart
KeyboardAwareScrollView(
  bottomOffset: 20,           // space between caret and keyboard
  extraKeyboardSpace: 0,      // extra scrollable room below
  snapToOffsets: const [120, 320],
  child: form,
)
```

Takes `child` like `SingleChildScrollView`, or `slivers` like
`CustomScrollView`. Call `assureFocusedInputVisible()` through a
`GlobalKey<KeyboardAwareScrollViewState>` after changing layout around the
field.

### `KeyboardAvoidingView`

```dart
KeyboardAvoidingView(
  behavior: KeyboardAvoidingBehavior.padding,
  child: child,
)
```

All four RNKC behaviours: `padding`, `height`, `position`,
`translateWithPadding`. It measures where it actually sits on screen, so a view
above a bottom bar or inside a sheet is padded by what the keyboard really
covers — not by the full keyboard height.

### `KeyboardStickyView`

Sticks content to the top of the keyboard with a `Transform`, so following the
keyboard costs no layout pass.

```dart
KeyboardStickyView(
  offset: const KeyboardStickyOffset(opened: 20),
  child: composer,
)
```

### `KeyboardToolbar`

A bar above the keyboard with prev/next arrows and a Done button. Navigation
runs over the Flutter focus tree, so the arrows move between plain
`TextField`s and disable themselves at the ends of the form.

```dart
Stack(children: [form, const KeyboardToolbar()])
```

### `KeyboardGestureArea`

Drag the keyboard away with a finger, the way iOS's interactive dismiss works.
The gesture is handled natively and **does not consume touches**, so scrolling
and tapping inside the area are unaffected. On iOS, UIKit moves the keyboard;
see "Interactive dismiss on iOS" below.

```dart
KeyboardGestureArea(offset: 20, child: ListView(children: messages))
```

Use `InteractiveKeyboard.enable()` to turn it on for the whole window instead.

### `KeyboardAnimationBuilder` / `KeyboardStateBuilder`

```dart
KeyboardAnimationBuilder(
  child: const ExpensiveComposer(),      // built once
  builder: (context, keyboard, child) => Transform.translate(
    offset: Offset(0, -keyboard.height),
    child: child,
  ),
)
```

`KeyboardAnimationBuilder` rebuilds per frame; `KeyboardStateBuilder` only when
the discrete state changes, with a `selector` so a widget that cares about
visibility is not rebuilt when the height changes.

### `OverKeyboardView`, `KeyboardExtender`, `KeyboardEffects`, `KeyboardBackgroundView`

Content around and behind the keyboard: a panel that appears without closing
the keyboard, buttons that read as part of it, and effects that blend through a
translucent backdrop.

## Imperative API

```dart
final keyboard = KeyboardController.instance;

keyboard.isVisible;
keyboard.state;                                  // height, type, appearance…
keyboard.metrics;                                // ValueListenable, per frame
keyboard.focusedInput;                           // ValueListenable
keyboard.focusedInputSelection;                  // caret geometry

await keyboard.dismiss();
await keyboard.dismiss(const DismissOptions(keepFocus: true));
keyboard.setFocusTo(FocusDirection.next);

keyboard.onKeyboardWillShow.listen((e) => print(e.height));

await keyboard.setEnabled(false);   // hand the keyboard back to the platform
keyboard.enabled;

await keyboard.setInputMode(AndroidSoftInputMode.adjustResize);  // Android
await keyboard.preload();                                        // iOS
```

Per-frame callbacks:

```dart
final remove = KeyboardController.instance.addHandler(
  KeyboardHandler(
    onStart: (e) {},        // destination values, before the animation
    onMove: (e) {},         // one frame of system-driven movement
    onInteractive: (e) {},  // one frame of finger-driven movement
    onEnd: (e) {},
  ),
);
```

## How the port differs from RNKC

RNKC's native code finds and measures the focused `EditText` / `UITextField`.
A Flutter `TextField` is not a native view — the engine owns only a hidden
input connection — so there is nothing there to measure. The equivalent
information lives in Dart: the focused `FocusNode` gives the rect, its
`EditableTextState` gives the text and caret geometry, and the focus tree gives
prev/next navigation. That is why everything here works with plain Flutter
text fields, and it is also more accurate than a native lookup would be.

Keyboard *movement* still comes from the platform, ported closely:

| | Android | iOS |
|---|---|---|
| frames | `WindowInsetsAnimationCompat.Callback` (emulated below API 30) | `CADisplayLink` on the keyboard view, corrected by the modelled spring/Bézier curve |
| interactive | `WindowInsetsController.controlWindowInsetsAnimation` | UIKit's own interactive dismiss, on a native scroll view under Flutter |
| keyboard colour | per-IME table (Gboard, SwiftKey, Samsung, Yandex, AOSP…) | private backdrop view, else appearance |

Deliberate differences, all for Flutter reasons:

- **Heights are raw IME insets in logical pixels**, matching
  `MediaQuery.viewInsets.bottom` rather than disagreeing with it. RNKC
  subtracts the Android navigation bar; that would put this package's numbers
  and Flutter's own numbers at odds.
- **The Android insets callback uses `DISPATCH_MODE_CONTINUE_ON_SUBTREE`**, not
  RNKC's `DISPATCH_MODE_STOP`. Flutter's `FlutterView` installs its own
  animation callback to drive `viewInsets`; stopping dispatch would freeze it.
- **`KeyboardAwareScrollView` has no `mode`.** RNKC's `"insets"` mode extends
  the scrollable area without reflowing content. Flutter has no content-inset
  concept, so there is one mode, matching RNKC's `"layout"`.
- **`KeyboardAvoidingView` always measures its absolute position**, so RNKC's
  `automaticOffset` flag does not exist and `keyboardVerticalOffset` is purely
  additive.
- **`OverKeyboardView` renders in Flutter's `Overlay`**, so it sits above all
  app content but under the keyboard's own pixels — Flutter paints the whole app
  into one view and the keyboard is a system window above it. Position the
  panel in the space above the keyboard and the behaviour is the same.
- **`KeyboardExtender` is the Android implementation on both platforms**
  (sticky view plus keyboard-coloured background). Embedding real views *inside*
  the iOS keyboard needs a native view to hand to UIKit, which a Flutter widget
  is not.
- **Interactive dismiss on iOS is UIKit's own.** An iOS app never moves the
  keyboard: UIKit does, and only for a native `UIScrollView` whose
  `keyboardDismissMode` is `.interactive` — all SwiftUI's
  `.scrollDismissesKeyboard(.interactively)` is, and what RNKC relies on. A
  Flutter list is not a `UIScrollView`, so the plugin gives UIKit one: an
  invisible scroll view under the Flutter view, whose pan recognizer is moved
  onto the Flutter view so every drag drives it too. It never takes a touch
  from Flutter. UIKit then moves the keyboard with the finger, and the
  keyboard-view observer ported from RNKC reports each frame as
  `onInteractive`. Because UIKit decides how the keyboard follows,
  `interpolator`, `offset` and `showOnSwipeUp` apply to Android only.
  **Not yet confirmed on a simulator or device.** (An earlier version moved the
  keyboard's window by hand. On current iOS the keys live in a window of their
  own, so they stayed put while layouts followed a keyboard that had not moved;
  it was removed.)
- **`dismiss(keepFocus: true)` goes through Flutter's own text-input channel**,
  not through a native input-view swap as RNKC does. Every Flutter field is
  already driven by that one channel, so hiding the keyboard there leaves the
  caret in place with no platform code and identical behaviour on both
  platforms. `animated: false` does still need the platform — `unfocus()`
  always animates — and is implemented on both.
- **There is no provider to mount, and the app's window configuration is left
  alone.** RNKC needs `<KeyboardProvider>` at the root and gives it
  `statusBarTranslucent`, `navigationBarTranslucent` and `preserveEdgeToEdge`,
  because React Native handles edge-to-edge poorly and RNKC ends up driving
  `decorFitsSystemWindows` itself. Flutter already owns that:
  `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)` and
  `SystemChrome.setSystemUIOverlayStyle` do the same job for the whole app, so
  this package only observes and never reconfigures your window.
- **On iOS, `KeyboardGestureArea.offset` is gesture slack only.** RNKC pairs
  `offset` with `textInputNativeID` and attaches an invisible
  `inputAccessoryView`, which genuinely grows the keyboard area. That needs a
  settable `inputAccessoryView`, and it is read-only on `UIResponder` —
  Flutter's first responder (`FlutterTextInputView`) does not redeclare it — so
  there is nothing to attach to. Here `offset` only widens the region in which
  a drag takes hold. On Android it behaves as in RNKC.
- **Where the plugin is absent** (web, desktop, widget tests) frames are
  synthesized from `viewInsets`. Heights and progress are real; `onStart` cannot
  report a destination before the animation and durations are `0`.

### Not ported, and what to use instead

- **`KeyboardChatScrollView`.** RNKC's chat scroll view exists because keeping a
  message list pinned to the bottom across keyboard transitions takes a lot of
  bookkeeping in React Native. Flutter's `ListView(reverse: true)` is already
  bottom-anchored, so a reverse list inside a `KeyboardAvoidingView` with the
  composer in a `KeyboardStickyView` gives the same behaviour in a few lines —
  see the chat page in [`example/`](example/lib/pages/chat_page.dart). Porting a
  thousand lines of chat-specific heuristics to replace that would be worse,
  not better.
- **`KeyboardToolbar.Group`.** Scoping prev/next to part of a form is what
  `FocusScope` already does: `fieldsInScopeOf` walks the focused node's
  enclosing scope, so wrapping a group of fields in a `FocusScope` confines the
  arrows to it.
- **`useResizeMode`.** RNKC's hook sets Android's `adjustResize` on mount.
  Flutter apps declare `windowSoftInputMode` in the manifest and are almost
  always on `adjustResize` already; call
  `setInputMode(AndroidSoftInputMode.adjustResize)` yourself if yours is not.
- **The toolbar's compound API** (`KeyboardToolbar.Prev`, `.Next`, `.Done`,
  `.Content`). `KeyboardToolbar` takes `content`, `background`, a `theme` and
  the three callbacks directly instead.

### API shape

React hooks have no Flutter equivalent, so `useKeyboardHandler` becomes a
`KeyboardHandler` passed to `addHandler` (which returns the function that
removes it), `useKeyboardState(selector)` becomes `KeyboardStateBuilder<T>`,
and `KeyboardEvents.addListener(name, cb)` becomes four `Stream`s. Beyond that:

- `KeyboardToolbar.opacity` is a `double` from `0` to `1`, not RNKC's
  two-character hex string.
- RNKC's `selection.start`/`end` points are `CaretPoint` here. Flutter already
  exports a `SelectionPoint`, and two classes of that name in one import would
  be ambiguous for anyone using both.
- `target` is `identityHashCode(FocusNode)` rather than a native view tag. It
  is comparable across events and means nothing else — there is no native view
  to have a tag.
- `parentScrollViewTarget` is `parentScrollable`, a `ScrollableState`. Matching
  scroll positions instead of tags also stays correct when scroll views nest.
- There is no `viewPositionInWindow` platform call; Dart measures directly.

## Platform support

| | Android | iOS |
|---|---|---|
| frame-synced tracking | ✅ API 21+ | ✅ |
| interactive drag | ✅ API 30+ | ⚠️ via UIKit, unconfirmed — see below |
| `setInputMode` / `setDefaultMode` | ✅ | n/a |
| `preload` | n/a | ✅ |
| `setTranslucent` / `KeyboardEffects` | n/a | ✅ |
| keyboard colour | ✅ | ✅ |

Android needs `minSdkVersion 24`.

## Status

The Dart layer is covered by tests, including the focused-input measurement and
caret geometry that everything else depends on. Both native halves compile:
the Android library builds with Gradle and the example app builds for the iOS
simulator.

The examples have been run on the iOS simulator, which is how the first iOS
interactive gesture was found not to work; its UIKit-based replacement has not
been run yet.
**Nothing has been profiled on a physical device yet**, and the simulator's
frame rate says nothing about a phone's.
