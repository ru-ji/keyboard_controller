import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'focused_input_observer.dart';
import 'platform_channel.dart';
import 'types.dart';

/// Keyboard tracking and imperative keyboard control.
///
/// The Flutter port of react-native-keyboard-controller's `KeyboardController`
/// module plus its `useKeyboardHandler` / `useKeyboardAnimation` /
/// `useReanimatedFocusedInput` hooks, which are all fed by the same singleton
/// here.
///
/// Nothing needs wrapping: the first access to [instance] attaches the native
/// observers and starts watching the focus tree, so widgets and handlers work
/// anywhere in the tree.
///
/// ```dart
/// final remove = KeyboardController.instance.addHandler(
///   KeyboardHandler(
///     onStart: (e) => print('keyboard going to ${e.height}'),
///     onMove: (e) => print('frame at ${e.height}'),
///   ),
/// );
/// ```
class KeyboardController {
  KeyboardController._() {
    _observer = FocusedInputObserver(
      onLayout: _handleFocusedInputLayout,
      onText: _handleFocusedInputText,
      onSelection: _handleFocusedInputSelection,
      onFocusPosition: _handleFocusPosition,
    );
    _channel.onMessage = _handleMessage;
  }

  /// The one controller. Creating it starts the observers.
  static final KeyboardController instance = KeyboardController._().._start();

  final KeyboardControllerChannel _channel = KeyboardControllerChannel();
  late final FocusedInputObserver _observer;

  final ValueNotifier<KeyboardEvent> _metrics =
      ValueNotifier<KeyboardEvent>(KeyboardEvent.zero);
  final ValueNotifier<FocusedInput?> _focusedInput =
      ValueNotifier<FocusedInput?>(null);
  final ValueNotifier<({int index, int count})> _focusPosition =
      ValueNotifier<({int index, int count})>((index: 0, count: 0));
  final StreamController<KeyboardNotification> _notifications =
      StreamController<KeyboardNotification>.broadcast();

  final List<KeyboardHandler> _handlers = <KeyboardHandler>[];
  final List<FocusedInputHandler> _inputHandlers = <FocusedInputHandler>[];

  bool _isClosed = true;
  bool _enabled = true;
  double _persistentHeight = 0;

  /// Last field that had focus. Kept separately from [_focusedInput] so a
  /// momentary blur — focus passing through a scope node on its way to the
  /// next field — does not look like a first focus.
  int _lastFocusTarget = -1;
  KeyboardEventData _lastData = KeyboardEventData(
    height: 0,
    duration: 0,
    timestamp: DateTime.now(),
    target: -1,
    type: TextInputType.text,
    appearance: KeyboardAppearance.light,
  );

  Future<void> _startFuture = Future<void>.value();

  void _start() {
    WidgetsFlutterBinding.ensureInitialized();
    _observer.start();
    _startFuture = _channel.start();
  }

  /// Completes once the native side has been queried. Only needed if you want
  /// to read [hasNativeSupport] or [keyboardBorderRadius] at startup.
  Future<void> get ready => _startFuture;

  // region Reactive state

  /// The current keyboard frame, updated on every frame of movement.
  ///
  /// This is the equivalent of RNKC's `useKeyboardAnimation()` —
  /// `metrics.value.height` and `.progress` are the `height` and `progress`
  /// shared values.
  ValueListenable<KeyboardEvent> get metrics => _metrics;

  /// The focused text field and its rect, or `null` when none is focused.
  ///
  /// Equivalent to RNKC's `useReanimatedFocusedInput().input`.
  ValueListenable<FocusedInput?> get focusedInput => _focusedInput;

  /// Position of the focused field among the text fields of its scope.
  ///
  /// Equivalent to RNKC's `focusDidSet` event; [KeyboardToolbar] uses it to
  /// enable and disable its arrows.
  ValueListenable<({int index, int count})> get focusPosition => _focusPosition;

  /// Caret geometry of the focused field, as last measured.
  FocusedInputSelection? get focusedInputSelection => _observer.selection;

  /// Discrete will/did show/hide notifications.
  Stream<KeyboardNotification> get notifications => _notifications.stream;

  Stream<KeyboardEventData> _notificationsOf(KeyboardNotificationKind kind) =>
      _notifications.stream
          .where((KeyboardNotification it) => it.kind == kind)
          .map((KeyboardNotification it) => it.data);

  Stream<KeyboardEventData> get onKeyboardWillShow =>
      _notificationsOf(KeyboardNotificationKind.willShow);
  Stream<KeyboardEventData> get onKeyboardDidShow =>
      _notificationsOf(KeyboardNotificationKind.didShow);
  Stream<KeyboardEventData> get onKeyboardWillHide =>
      _notificationsOf(KeyboardNotificationKind.willHide);
  Stream<KeyboardEventData> get onKeyboardDidHide =>
      _notificationsOf(KeyboardNotificationKind.didHide);

  /// Whether the keyboard is on its way in or already shown.
  bool get isVisible => !_isClosed;

  /// A snapshot of the keyboard, the equivalent of RNKC's
  /// `KeyboardController.state()`.
  KeyboardState get state =>
      KeyboardState(isVisible: isVisible, data: _lastData);

  /// Whether this package is tracking the keyboard at all.
  ///
  /// See [setEnabled].
  bool get enabled => _enabled;

  /// Whether the native half of the plugin is present.
  ///
  /// When it is not (web, desktop, widget tests) frames are synthesized from
  /// `viewInsets`: heights and progress are real, but `onStart` cannot report
  /// the destination before the animation and durations are reported as `0`.
  bool get hasNativeSupport => _channel.hasNativeSupport;

  /// Corner radius of the system keyboard; `0` when it has square corners.
  double get keyboardBorderRadius => _channel.keyboardBorderRadius;

  /// Whether the keyboard is a floating, rounded panel (iOS 26+).
  bool get keyboardHasRoundedCorners => keyboardBorderRadius > 0;

  // endregion

  // region Handlers

  /// Registers per-frame keyboard callbacks. Call the returned function to
  /// remove them.
  VoidCallback addHandler(KeyboardHandler handler) {
    _handlers.add(handler);
    return () => _handlers.remove(handler);
  }

  /// Registers focused-input callbacks. Call the returned function to remove
  /// them.
  VoidCallback addFocusedInputHandler(FocusedInputHandler handler) {
    _inputHandlers.add(handler);
    return () => _inputHandlers.remove(handler);
  }

  // endregion

  // region Imperative API

  /// Hides the keyboard, resolving once it is fully hidden.
  ///
  /// Pass `keepFocus: true` to leave the caret in the field, or
  /// `animated: false` to hide it without a transition. Both need the native
  /// side; without it this falls back to [FocusManager.primaryFocus] unfocus.
  Future<void> dismiss([DismissOptions options = const DismissOptions()]) {
    if (_isClosed) {
      if (!options.keepFocus) _unfocus(options);
      return Future<void>.value();
    }

    final Completer<void> completer = Completer<void>();
    late final StreamSubscription<KeyboardEventData> subscription;
    subscription = onKeyboardDidHide.listen((_) {
      subscription.cancel();
      if (!completer.isCompleted) completer.complete();
    });

    _unfocus(options);

    return completer.future;
  }

  void _unfocus(DismissOptions options) {
    if (options.keepFocus) {
      // `unfocus()` would detach the input client and take the caret with it.
      // Asking the engine to hide the keyboard leaves the focus — and the
      // caret — exactly where it is. RNKC reaches for a native input-view
      // swap here; Flutter already routes every field through one channel, so
      // this needs no platform code and works the same on both platforms.
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      return;
    }

    // Skipping the animation is the one thing Dart cannot do: `unfocus()`
    // always animates.
    if (!options.animated) {
      _channel.dismiss(keepFocus: false, animated: false);
    }
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// Moves focus to the next or previous text field, or restores it to the
  /// last focused one.
  ///
  /// Runs over the Flutter focus tree, so it works with ordinary
  /// [TextField]s — see [FocusedInputTraversal].
  bool setFocusTo(FocusDirection direction) => _observer.setFocusTo(direction);

  /// Turns keyboard tracking off, or back on.
  ///
  /// The equivalent of RNKC's `useKeyboardController().setEnabled`. Turning it
  /// off stops the native observers and the focus watcher, so keyboard
  /// handling falls back to the platform default — on Android, whatever
  /// `windowSoftInputMode` the manifest asks for.
  ///
  /// Values freeze rather than reset: [metrics] and [focusedInput] keep their
  /// last reading, so a layout already shifted for the keyboard does not jump
  /// the moment tracking stops. Dismiss the keyboard first if you want them at
  /// rest.
  Future<void> setEnabled(bool enabled) async {
    if (enabled == _enabled) return;
    _enabled = enabled;

    if (enabled) {
      _observer.start();
    } else {
      _observer.dispose();
    }

    await _channel.setEnabled(enabled);
  }

  /// Changes `windowSoftInputMode` on Android. No-op elsewhere.
  ///
  /// See [AndroidSoftInputMode] for the values.
  Future<void> setInputMode(int mode) => _channel.setInputMode(mode);

  /// Restores the `windowSoftInputMode` declared in `AndroidManifest.xml`.
  Future<void> setDefaultMode() => _channel.setDefaultMode();

  /// Warms the keyboard up so the first focus has no delay. iOS only.
  Future<void> preload() => _channel.preload();

  /// Makes the keyboard backdrop translucent so content behind it shows
  /// through. iOS only; see [KeyboardEffects].
  Future<void> setTranslucent(bool translucent) =>
      _channel.setTranslucent(translucent);

  /// Background colour of the keyboard currently installed, for
  /// [KeyboardBackgroundView]. `null` when the platform cannot report one.
  Future<Color?> keyboardBackgroundColor() async {
    final int? value = await _channel.keyboardBackgroundColor();
    return value == null ? null : Color(value);
  }

  /// Turns the native interactive-dismiss gesture on or off.
  ///
  /// Prefer the [KeyboardGestureArea] widget, which calls this for you and
  /// scopes the gesture to its own bounds.
  Future<bool> configureInteractiveKeyboard({
    required bool enabled,
    double offset = 0,
    KeyboardInterpolator interpolator = KeyboardInterpolator.ios,
    bool showOnSwipeUp = false,
    bool enableSwipeToDismiss = true,
  }) =>
      _channel.setInteractive(
        enabled: enabled,
        offset: offset,
        interpolator: interpolator,
        showOnSwipeUp: showOnSwipeUp,
        enableSwipeToDismiss: enableSwipeToDismiss,
      );

  /// Whether this platform can hand control of the keyboard position to a
  /// finger. `false` on Android below API 30, which has no inset-control API.
  Future<bool> isInteractiveKeyboardSupported() =>
      _channel.isInteractiveSupported();

  /// Restricts the interactive gesture to a rect in logical pixels, or clears
  /// the restriction when [rect] is `null`.
  Future<void> setInteractiveKeyboardArea(Rect? rect) =>
      _channel.setInteractiveArea(rect);

  /// Re-measures the focused field and pushes the result to [focusedInput].
  ///
  /// Equivalent to RNKC's `useReanimatedFocusedInput().update()`.
  void syncUpFocusedInputLayout() => _observer.syncUpLayout();

  // endregion

  // region Native message handling

  void _handleMessage(List<Object?> message) {
    // The native side has been told to stop, but a frame already in flight
    // must not slip through after that.
    if (!_enabled) return;

    final int kind = message[0]! as int;
    final KeyboardTransition? transition = KeyboardMessage.transitionOf(kind);

    if (transition != null) {
      _handleTransition(
        transition,
        height: (message[1]! as num).toDouble(),
        progress: (message[2]! as num).toDouble(),
        duration: (message[3]! as num).toInt(),
      );
      return;
    }

    _handleNotification(
      kind,
      height: (message[1]! as num).toDouble(),
      duration: (message[2]! as num).toInt(),
      timestampMs: (message[3]! as num).toInt(),
      isDark: message[4] == true,
    );
  }

  void _handleTransition(
    KeyboardTransition transition, {
    required double height,
    required double progress,
    required int duration,
  }) {
    if (transition == KeyboardTransition.start) {
      // RNKC re-measures the focused input at the start of every transition,
      // so handlers that scroll it into view see a fresh rect.
      _observer.syncUpLayout();
      if (height > 0) _persistentHeight = height;
    }

    final KeyboardEvent event = KeyboardEvent(
      height: height,
      progress: progress,
      duration: duration,
      target: _observer.target,
    );

    // `start` carries where the keyboard is *going*, not where it is. Writing
    // it here would draw everything built on [metrics] at the destination for
    // the frame or two before the first `move` arrives — a visible pop at the
    // start of every transition. Handlers still receive it as `onStart`.
    if (transition != KeyboardTransition.start) _metrics.value = event;
    _dispatch(transition, event);
  }

  void _dispatch(KeyboardTransition transition, KeyboardEvent event) {
    // Copy: a handler may remove itself while being called.
    for (final KeyboardHandler handler in List<KeyboardHandler>.of(_handlers)) {
      handler.dispatch(transition, event);
    }
  }

  void _handleNotification(
    int kind, {
    required double height,
    required int duration,
    required int timestampMs,
    required bool isDark,
  }) {
    final KeyboardNotificationKind? notification = switch (kind) {
      KeyboardMessage.willShow => KeyboardNotificationKind.willShow,
      KeyboardMessage.didShow => KeyboardNotificationKind.didShow,
      KeyboardMessage.willHide => KeyboardNotificationKind.willHide,
      KeyboardMessage.didHide => KeyboardNotificationKind.didHide,
      _ => null,
    };
    if (notification == null) return;

    final KeyboardEventData data = KeyboardEventData(
      height: height,
      duration: duration,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      target: _observer.target,
      type: _observer.keyboardType,
      appearance:
          isDark ? KeyboardAppearance.dark : KeyboardAppearance.light,
    );

    switch (notification) {
      case KeyboardNotificationKind.willShow:
        _isClosed = false;
        _lastData = data;
      case KeyboardNotificationKind.didHide:
        _isClosed = true;
        _lastData = data;
      case KeyboardNotificationKind.didShow:
      case KeyboardNotificationKind.willHide:
        break;
    }

    _notifications.add(KeyboardNotification(notification, data));
  }

  // endregion

  // region Focused input handling

  void _handleFocusedInputLayout(FocusedInput? input) {
    final int previous = _lastFocusTarget;
    _focusedInput.value = input;
    if (input != null) _lastFocusTarget = input.target;

    final bool focusMovedBetweenFields =
        input != null && previous != -1 && previous != input.target;

    // RNKC imitates iOS here: when focus hops between fields while the
    // keyboard stays up, no platform animation runs, so it emits an instant
    // start/end pair carrying the new target. Without it, consumers such as
    // KeyboardAwareScrollView would never learn that they must scroll.
    if (focusMovedBetweenFields && isVisible) {
      final KeyboardEvent event = KeyboardEvent(
        height: _persistentHeight,
        progress: 1,
        duration: 0,
        target: input.target,
      );
      _metrics.value = event;
      _dispatch(KeyboardTransition.start, event);
      _dispatch(KeyboardTransition.end, event);
    }
  }

  void _handleFocusedInputText(FocusedInputText text) {
    for (final FocusedInputHandler handler
        in List<FocusedInputHandler>.of(_inputHandlers)) {
      handler.onChangeText?.call(text);
    }
  }

  void _handleFocusedInputSelection(FocusedInputSelection selection) {
    for (final FocusedInputHandler handler
        in List<FocusedInputHandler>.of(_inputHandlers)) {
      handler.onSelectionChange?.call(selection);
    }
  }

  void _handleFocusPosition(int index, int count) {
    _focusPosition.value = (index: index, count: count);
  }

  // endregion

  /// Puts the controller back to how it starts, for tests.
  ///
  /// Needed because this is a singleton while `flutter_test` gives every test
  /// a fresh [FocusManager] and a fresh tree: without this, the focus listener
  /// stays attached to the previous test's manager and the keyboard height
  /// leaks from one test into the next. Call it from `setUp`.
  @visibleForTesting
  void resetForTesting() {
    _observer.dispose();
    _enabled = true;
    _metrics.value = KeyboardEvent.zero;
    _focusedInput.value = null;
    _focusPosition.value = (index: 0, count: 0);
    _isClosed = true;
    _persistentHeight = 0;
    _lastFocusTarget = -1;
    _lastData = KeyboardEventData(
      height: 0,
      duration: 0,
      timestamp: DateTime.now(),
      target: -1,
      type: TextInputType.text,
      appearance: KeyboardAppearance.light,
    );
    _observer.start();
  }

  /// Tears everything down. Only useful in tests — the singleton normally
  /// lives for the life of the process.
  @visibleForTesting
  Future<void> dispose() async {
    _observer.dispose();
    await _channel.dispose();
    await _notifications.close();
    _metrics.dispose();
    _focusedInput.dispose();
    _focusPosition.dispose();
  }
}
