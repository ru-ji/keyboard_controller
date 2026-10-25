import 'package:flutter/widgets.dart';

/// Which phase of the keyboard transition an event belongs to.
///
/// Mirrors react-native-keyboard-controller's `onKeyboardMoveStart` /
/// `onKeyboardMove` / `onKeyboardMoveEnd` / `onKeyboardMoveInteractive`.
enum KeyboardTransition {
  /// Movement is about to begin. The event carries *destination* values.
  start,

  /// Movement progressed by one frame.
  move,

  /// Movement finished.
  end,

  /// Movement is being driven by a finger rather than by the system animation.
  interactive,
}

/// Keyboard appearance, as reported by the platform.
enum KeyboardAppearance { light, dark }

/// A single frame of keyboard movement.
///
/// The Flutter equivalent of RNKC's `NativeEvent`.
@immutable
class KeyboardEvent {
  const KeyboardEvent({
    required this.height,
    required this.progress,
    required this.duration,
    required this.target,
  });

  /// No keyboard, no movement.
  static const KeyboardEvent zero =
      KeyboardEvent(height: 0, progress: 0, duration: 0, target: -1);

  /// Visible keyboard height in logical pixels.
  final double height;

  /// `0` when fully closed, `1` when fully open.
  final double progress;

  /// Duration of the whole transition in milliseconds.
  ///
  /// `-1` while the keyboard is driven interactively by a finger.
  final int duration;

  /// Identity of the focused input, or `-1` when nothing is focused.
  ///
  /// See [FocusedInput.target] for how this is derived on Flutter.
  final int target;

  /// Whether this frame is part of an interactive (finger-driven) movement.
  bool get isInteractive => duration == -1;

  KeyboardEvent copyWith({
    double? height,
    double? progress,
    int? duration,
    int? target,
  }) =>
      KeyboardEvent(
        height: height ?? this.height,
        progress: progress ?? this.progress,
        duration: duration ?? this.duration,
        target: target ?? this.target,
      );

  @override
  bool operator ==(Object other) =>
      other is KeyboardEvent &&
      other.height == height &&
      other.progress == progress &&
      other.duration == duration &&
      other.target == target;

  @override
  int get hashCode => Object.hash(height, progress, duration, target);

  @override
  String toString() => 'KeyboardEvent(height: $height, progress: $progress, '
      'duration: $duration, target: $target)';
}

/// Payload of the discrete `keyboardWillShow` / `keyboardDidShow` /
/// `keyboardWillHide` / `keyboardDidHide` notifications.
@immutable
class KeyboardEventData {
  const KeyboardEventData({
    required this.height,
    required this.duration,
    required this.timestamp,
    required this.target,
    required this.type,
    required this.appearance,
  });

  /// Final keyboard height in logical pixels.
  final double height;

  /// Duration of the transition in milliseconds.
  final int duration;

  /// When the platform emitted the event.
  final DateTime timestamp;

  /// Identity of the focused input, or `-1`.
  final int target;

  /// Keyboard type requested by the focused input.
  ///
  /// Taken from the Flutter [TextInputType] of the focused field, so it stays
  /// correct even though the field is painted by Flutter rather than by a
  /// native text view.
  final TextInputType type;

  /// Light or dark keyboard.
  final KeyboardAppearance appearance;

  KeyboardEventData copyWith({
    double? height,
    int? duration,
    DateTime? timestamp,
    int? target,
    TextInputType? type,
    KeyboardAppearance? appearance,
  }) =>
      KeyboardEventData(
        height: height ?? this.height,
        duration: duration ?? this.duration,
        timestamp: timestamp ?? this.timestamp,
        target: target ?? this.target,
        type: type ?? this.type,
        appearance: appearance ?? this.appearance,
      );

  @override
  String toString() => 'KeyboardEventData(height: $height, duration: $duration, '
      'target: $target, type: ${type.index}, appearance: $appearance)';
}

/// A snapshot of the keyboard: [KeyboardEventData] plus visibility.
@immutable
class KeyboardState {
  const KeyboardState({required this.isVisible, required this.data});

  final bool isVisible;
  final KeyboardEventData data;

  double get height => data.height;
  int get duration => data.duration;
  DateTime get timestamp => data.timestamp;
  int get target => data.target;
  TextInputType get type => data.type;
  KeyboardAppearance get appearance => data.appearance;

  @override
  String toString() => 'KeyboardState(isVisible: $isVisible, data: $data)';
}

/// Rect of the focused input, in logical pixels.
///
/// [x] / [y] are relative to the enclosing scrollable's content (or to the
/// window when the input is not inside one); [absoluteX] / [absoluteY] are
/// relative to the window.
@immutable
class FocusedInputLayout {
  const FocusedInputLayout({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.absoluteX,
    required this.absoluteY,
  });

  static const FocusedInputLayout zero = FocusedInputLayout(
    x: 0,
    y: 0,
    width: 0,
    height: 0,
    absoluteX: 0,
    absoluteY: 0,
  );

  final double x;
  final double y;
  final double width;
  final double height;
  final double absoluteX;
  final double absoluteY;

  FocusedInputLayout copyWith({double? height}) => FocusedInputLayout(
        x: x,
        y: y,
        width: width,
        height: height ?? this.height,
        absoluteX: absoluteX,
        absoluteY: absoluteY,
      );

  @override
  bool operator ==(Object other) =>
      other is FocusedInputLayout &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height &&
      other.absoluteX == absoluteX &&
      other.absoluteY == absoluteY;

  @override
  int get hashCode => Object.hash(x, y, width, height, absoluteX, absoluteY);

  @override
  String toString() => 'FocusedInputLayout(x: $x, y: $y, width: $width, '
      'height: $height, absoluteX: $absoluteX, absoluteY: $absoluteY)';
}

/// The currently focused text field and where it sits on screen.
@immutable
class FocusedInput {
  const FocusedInput({
    required this.target,
    required this.layout,
    this.parentScrollable,
    this.node,
  });

  /// Stable identity of the focused field for this process.
  ///
  /// The Flutter counterpart of RNKC's native view tag: it is derived from the
  /// [FocusNode], so it is comparable across events but carries no meaning.
  final int target;

  final FocusedInputLayout layout;

  /// The scrollable the field lives in, if any — the counterpart of RNKC's
  /// `parentScrollViewTarget`.
  final ScrollableState? parentScrollable;

  /// The focus node backing the field. `null` in synthesized events.
  final FocusNode? node;

  FocusedInput copyWith({FocusedInputLayout? layout}) => FocusedInput(
        target: target,
        layout: layout ?? this.layout,
        parentScrollable: parentScrollable,
        node: node,
      );

  @override
  String toString() =>
      'FocusedInput(target: $target, layout: $layout)';
}

/// One end of a selection, in coordinates local to the focused input.
///
/// Named `CaretPoint` rather than RNKC's `selection.start`/`end` shape name so
/// it cannot collide with Flutter's own `SelectionPoint`.
@immutable
class CaretPoint {
  const CaretPoint({
    required this.x,
    required this.y,
    required this.position,
  });

  /// Horizontal offset of the caret inside the input.
  final double x;

  /// Vertical offset of the caret inside the input.
  ///
  /// For [FocusedInputSelection.end] this is the *bottom* of the caret, which
  /// makes it usable as "how tall the input is up to the caret" — that is how
  /// [KeyboardAwareScrollView] keeps a growing multiline field in view.
  final double y;

  /// Character offset in the text.
  final int position;

  @override
  bool operator ==(Object other) =>
      other is CaretPoint &&
      other.x == x &&
      other.y == y &&
      other.position == position;

  @override
  int get hashCode => Object.hash(x, y, position);

  @override
  String toString() => 'CaretPoint(x: $x, y: $y, position: $position)';
}

/// Caret/selection geometry of the focused input.
@immutable
class FocusedInputSelection {
  const FocusedInputSelection({
    required this.target,
    required this.start,
    required this.end,
  });

  final int target;
  final CaretPoint start;
  final CaretPoint end;

  @override
  bool operator ==(Object other) =>
      other is FocusedInputSelection &&
      other.target == target &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(target, start, end);

  @override
  String toString() =>
      'FocusedInputSelection(target: $target, start: $start, end: $end)';
}

/// Text of the focused input after a change.
@immutable
class FocusedInputText {
  const FocusedInputText({required this.target, required this.text});

  final int target;
  final String text;

  @override
  String toString() => 'FocusedInputText(target: $target, text: $text)';
}

/// Where [KeyboardController.setFocusTo] should move the focus.
enum FocusDirection {
  next,
  prev,

  /// Restore focus to the field that had it last.
  current,
}

/// How [KeyboardController.dismiss] should behave.
@immutable
class DismissOptions {
  const DismissOptions({this.keepFocus = false, this.animated = true});

  /// Keep the caret in the field after hiding the keyboard.
  final bool keepFocus;

  /// Animate the keyboard away rather than hiding it instantly.
  final bool animated;
}

/// Values of `android.view.WindowManager.LayoutParams.softInputMode`, for
/// [KeyboardController.setInputMode].
abstract final class AndroidSoftInputMode {
  static const int adjustNothing = 48;
  static const int adjustPan = 32;
  static const int adjustResize = 16;
  static const int adjustUnspecified = 0;
  static const int isForwardNavigation = 256;
  static const int maskAdjust = 240;
  static const int maskState = 15;
  static const int modeChanged = 512;
  static const int stateAlwaysHidden = 3;
  static const int stateAlwaysVisible = 5;
  static const int stateHidden = 2;
  static const int stateUnchanged = 1;
  static const int stateUnspecified = 0;
  static const int stateVisible = 4;
}

/// How a [KeyboardGestureArea] maps finger movement onto keyboard position.
enum KeyboardInterpolator {
  /// The keyboard only follows the finger while the finger is over it — the
  /// way iOS's interactive dismiss behaves.
  ios,

  /// The keyboard follows the finger one-to-one from anywhere in the area.
  linear,
}

/// Per-frame keyboard callbacks, the equivalent of RNKC's `useKeyboardHandler`.
///
/// Every callback is optional; register with
/// [KeyboardController.addHandler].
@immutable
class KeyboardHandler {
  const KeyboardHandler({
    this.onStart,
    this.onMove,
    this.onEnd,
    this.onInteractive,
  });

  /// Movement is about to begin; the event carries destination values.
  final ValueChanged<KeyboardEvent>? onStart;

  /// One frame of system-driven movement.
  final ValueChanged<KeyboardEvent>? onMove;

  /// Movement finished.
  final ValueChanged<KeyboardEvent>? onEnd;

  /// One frame of finger-driven movement.
  final ValueChanged<KeyboardEvent>? onInteractive;

  void dispatch(KeyboardTransition transition, KeyboardEvent event) {
    switch (transition) {
      case KeyboardTransition.start:
        onStart?.call(event);
      case KeyboardTransition.move:
        onMove?.call(event);
      case KeyboardTransition.end:
        onEnd?.call(event);
      case KeyboardTransition.interactive:
        onInteractive?.call(event);
    }
  }
}

/// Focused-input callbacks, the equivalent of RNKC's `useFocusedInputHandler`.
@immutable
class FocusedInputHandler {
  const FocusedInputHandler({this.onChangeText, this.onSelectionChange});

  final ValueChanged<FocusedInputText>? onChangeText;
  final ValueChanged<FocusedInputSelection>? onSelectionChange;
}

/// Which discrete keyboard notification fired.
enum KeyboardNotificationKind { willShow, didShow, willHide, didHide }

/// A discrete keyboard notification and its payload.
///
/// The Flutter equivalent of RNKC's `KeyboardEvents.addListener(name, cb)`.
@immutable
class KeyboardNotification {
  const KeyboardNotification(this.kind, this.data);

  final KeyboardNotificationKind kind;
  final KeyboardEventData data;

  @override
  String toString() => 'KeyboardNotification($kind, $data)';
}
