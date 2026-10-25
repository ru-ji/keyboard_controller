/// Flutter port of
/// [react-native-keyboard-controller](https://github.com/kirillzyusko/react-native-keyboard-controller):
/// frame-synced keyboard tracking, keyboard-aware layout and scrolling,
/// interactive drag-to-dismiss, and focused-input observation — all working
/// with ordinary Flutter [TextField]s.
///
/// Start from [KeyboardController] for state and imperative control, or drop in
/// one of the widgets:
///
/// - [KeyboardAvoidingView] — keep content clear of the keyboard
/// - [KeyboardAwareScrollView] — keep the focused field and caret visible
/// - [KeyboardStickyView] — stick content to the top of the keyboard
/// - [KeyboardToolbar] — prev/next/done bar above the keyboard
/// - [KeyboardGestureArea] — drag the keyboard away with a finger
/// - [KeyboardAnimationBuilder] / [KeyboardStateBuilder] — react to movement
/// - [OverKeyboardView], [KeyboardExtender], [KeyboardEffects],
///   [KeyboardBackgroundView] — content around and behind the keyboard
library;

export 'src/focus_traversal.dart' show FocusedInputTraversal;
export 'src/focused_input_observer.dart' show FocusedInputObserver;
export 'src/keyboard_controller.dart' show KeyboardController;
export 'src/types.dart';
export 'src/widgets/keyboard_animation_builder.dart';
export 'src/widgets/keyboard_avoiding_view.dart';
export 'src/widgets/keyboard_aware_scroll_view.dart';
export 'src/widgets/keyboard_background.dart';
export 'src/widgets/keyboard_gesture_area.dart';
export 'src/widgets/keyboard_sticky_view.dart';
export 'src/widgets/keyboard_toolbar.dart';
export 'src/widgets/over_keyboard_view.dart';
