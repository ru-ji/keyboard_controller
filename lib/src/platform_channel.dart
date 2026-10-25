import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'types.dart';

/// Message kinds sent from the native side on [KeyboardControllerChannel.messages].
///
/// Frames are encoded as a flat `List` rather than a map: the per-frame channel
/// runs at display refresh rate, and a list skips the key hashing a map would
/// pay for on every single frame.
abstract final class KeyboardMessage {
  /// `[transitionStart, height, progress, duration]`
  static const int transitionStart = 0;
  static const int transitionMove = 1;
  static const int transitionEnd = 2;
  static const int transitionInteractive = 3;

  /// `[notification*, height, duration, timestampMs, isDarkAppearance]`
  static const int willShow = 10;
  static const int didShow = 11;
  static const int willHide = 12;
  static const int didHide = 13;

  static KeyboardTransition? transitionOf(int code) => switch (code) {
        transitionStart => KeyboardTransition.start,
        transitionMove => KeyboardTransition.move,
        transitionEnd => KeyboardTransition.end,
        transitionInteractive => KeyboardTransition.interactive,
        _ => null,
      };
}

/// Raw transport to the native keyboard observers.
///
/// Where the platform has no native half — web, desktop, widget tests — the
/// channel falls back to synthesizing frames from `FlutterView.viewInsets`,
/// which Flutter's own engine already animates. The fallback cannot know the
/// destination height before the animation starts, so it reports the current
/// height in `onStart`; everything else behaves the same.
class KeyboardControllerChannel {
  KeyboardControllerChannel();

  static const MethodChannel _methods = MethodChannel('keyboard_controller');
  static const BasicMessageChannel<Object?> _messages =
      BasicMessageChannel<Object?>(
    'keyboard_controller/messages',
    StandardMessageCodec(),
  );

  /// Receives every native message, decoded into its raw `List` form.
  void Function(List<Object?> message)? onMessage;

  bool _started = false;
  _ViewInsetsFallback? _fallback;

  /// Whether the native plugin answered, i.e. whether real keyboard
  /// lifecycle events (`onStart` with a destination, interactive frames,
  /// durations) are available.
  bool get hasNativeSupport => _hasNativeSupport;
  bool _hasNativeSupport = false;

  double _keyboardBorderRadius = 0;

  /// Corner radius of the system keyboard, `0` when it has square corners.
  double get keyboardBorderRadius => _keyboardBorderRadius;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _messages.setMessageHandler((Object? message) async {
      if (message is List<Object?>) onMessage?.call(message);
      return null;
    });

    try {
      final Map<Object?, Object?>? constants =
          await _methods.invokeMapMethod<Object?, Object?>('getConstants');
      _hasNativeSupport = true;
      _keyboardBorderRadius =
          (constants?['keyboardBorderRadius'] as num?)?.toDouble() ?? 0;
    } on MissingPluginException {
      _hasNativeSupport = false;
    } catch (error, stack) {
      _hasNativeSupport = false;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'keyboard_controller',
          context: ErrorDescription('while querying native constants'),
        ),
      );
    }

    if (!_hasNativeSupport) {
      _fallback = _ViewInsetsFallback(
        (List<Object?> message) => onMessage?.call(message),
      )..start();
    }
  }

  Future<void> dispose() async {
    _messages.setMessageHandler(null);
    _fallback?.stop();
    _fallback = null;
    _started = false;
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _methods.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> setInputMode(int mode) =>
      _invoke<void>('setInputMode', <String, Object?>{'mode': mode});

  Future<void> setDefaultMode() => _invoke<void>('setDefaultMode');

  /// Starts or stops the native keyboard observers.
  ///
  /// Stopping them hands keyboard handling back to the platform default, which
  /// on Android means whatever `windowSoftInputMode` the manifest asks for.
  Future<void> setEnabled(bool enabled) =>
      _invoke<void>('setEnabled', <String, Object?>{'enabled': enabled});

  Future<void> preload() => _invoke<void>('preload');

  Future<void> setTranslucent(bool translucent) => _invoke<void>(
        'setTranslucent',
        <String, Object?>{'translucent': translucent},
      );

  /// Hides the keyboard without an animation, which Flutter's own `unfocus()`
  /// cannot do.
  Future<void> dismiss({required bool keepFocus, required bool animated}) =>
      _invoke<void>('dismiss', <String, Object?>{
        'keepFocus': keepFocus,
        'animated': animated,
      });

  /// Background colour of the current keyboard, for [KeyboardBackgroundView].
  Future<int?> keyboardBackgroundColor() =>
      _invoke<int>('keyboardBackgroundColor');

  /// Turns the native interactive-dismiss gesture on or off.
  Future<bool> setInteractive({
    required bool enabled,
    required double offset,
    required KeyboardInterpolator interpolator,
    required bool showOnSwipeUp,
    required bool enableSwipeToDismiss,
  }) async =>
      await _invoke<bool>('setInteractive', <String, Object?>{
            'enabled': enabled,
            'offset': offset,
            'interpolator': interpolator.name,
            'showOnSwipeUp': showOnSwipeUp,
            'enableSwipeToDismiss': enableSwipeToDismiss,
          }) ??
      false;

  Future<bool> isInteractiveSupported() async =>
      await _invoke<bool>('isInteractiveSupported') ?? false;

  /// Limits the gesture to a rect in logical pixels; `null` clears the limit.
  Future<void> setInteractiveArea(Rect? rect) => _invoke<void>(
        'setInteractiveArea',
        rect == null
            ? null
            : <String, Object?>{
                'left': rect.left,
                'top': rect.top,
                'right': rect.right,
                'bottom': rect.bottom,
              },
      );
}

/// Synthesizes keyboard frames from `FlutterView.viewInsets`.
///
/// Flutter's engine already interpolates `viewInsets` in step with the platform
/// keyboard animation, so watching it gives real per-frame movement; what it
/// cannot give is the destination before the first frame, a duration, or
/// interactive frames.
class _ViewInsetsFallback with WidgetsBindingObserver {
  _ViewInsetsFallback(this.emit);

  final void Function(List<Object?> message) emit;

  static const Duration _settleDelay = Duration(milliseconds: 80);

  double _last = 0;
  double _open = 0;
  bool _moving = false;
  Timer? _settle;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _last = _currentHeight();
    _open = _last;
  }

  void stop() {
    _settle?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  double _currentHeight() {
    final ui.FlutterView? view =
        WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return 0;
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  @override
  void didChangeMetrics() {
    final double height = _currentHeight();
    if (height == _last) return;

    final bool closing = height < _last;
    _last = height;
    if (height > _open) _open = height;

    if (!_moving) {
      _moving = true;
      // The destination is unknowable here, so the best available guess is
      // "fully open" or "fully closed" in the direction of travel.
      _emitFrame(
        KeyboardMessage.transitionStart,
        closing ? 0 : _open,
        closing ? 0 : 1,
      );
      _emitNotification(
        closing ? KeyboardMessage.willHide : KeyboardMessage.willShow,
        closing ? 0 : _open,
      );
    }

    _emitFrame(
      KeyboardMessage.transitionMove,
      height,
      _open == 0 ? 0 : height / _open,
    );

    _settle?.cancel();
    _settle = Timer(_settleDelay, () {
      _moving = false;
      final double end = _last;
      _emitFrame(
        KeyboardMessage.transitionEnd,
        end,
        _open == 0 ? 0 : end / _open,
      );
      _emitNotification(
        end == 0 ? KeyboardMessage.didHide : KeyboardMessage.didShow,
        end,
      );
    });
  }

  void _emitFrame(int kind, double height, double progress) =>
      emit(<Object?>[kind, height, progress, 0]);

  void _emitNotification(int kind, double height) => emit(<Object?>[
        kind,
        height,
        0,
        DateTime.now().millisecondsSinceEpoch,
        false,
      ]);
}
