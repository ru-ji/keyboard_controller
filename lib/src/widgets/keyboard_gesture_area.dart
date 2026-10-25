import 'package:flutter/widgets.dart';

import '../keyboard_controller.dart';
import '../types.dart';

/// Lets the keyboard be dragged away with a finger inside its bounds.
///
/// The port of RNKC's `KeyboardGestureArea`. The gesture is handled natively
/// and does **not** consume touches, so scrolling and tapping inside the area
/// behave exactly as before; the keyboard only starts following the finger
/// once the finger is over it (with [KeyboardInterpolator.ios]).
///
/// On Android (API 30+) the native side drives the real IME inset, so
/// Flutter's own `MediaQuery.viewInsets` follows the finger too and any layout
/// already reacting to the keyboard works unchanged.
///
/// On iOS only UIKit can move the keyboard, and only for a native
/// `UIScrollView`; the plugin places an invisible one under the Flutter view
/// and lets UIKit do it. [interpolator], [offset] and [showOnSwipeUp] are
/// Android-only there, since UIKit decides how the keyboard follows.
///
/// ```dart
/// KeyboardGestureArea(
///   offset: 20,
///   child: ListView(children: messages),
/// )
/// ```
class KeyboardGestureArea extends StatefulWidget {
  const KeyboardGestureArea({
    super.key,
    required this.child,
    this.enabled = true,
    this.offset = 0,
    this.interpolator = KeyboardInterpolator.ios,
    this.showOnSwipeUp = false,
    this.enableSwipeToDismiss = true,
  });

  final Widget child;

  /// Whether the gesture is active.
  final bool enabled;

  /// Extra slack above the keyboard that still counts as touching it.
  final double offset;

  /// How finger movement maps onto keyboard position.
  final KeyboardInterpolator interpolator;

  /// Allow swiping up to bring a hidden keyboard back. Off by default, as in
  /// RNKC.
  final bool showOnSwipeUp;

  /// Allow swiping down to dismiss a visible keyboard.
  final bool enableSwipeToDismiss;

  @override
  State<KeyboardGestureArea> createState() => _KeyboardGestureAreaState();
}

class _KeyboardGestureAreaState extends State<KeyboardGestureArea> {
  Rect? _reportedArea;

  @override
  void initState() {
    super.initState();
    _apply();
  }

  @override
  void didUpdateWidget(KeyboardGestureArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.offset != widget.offset ||
        oldWidget.interpolator != widget.interpolator ||
        oldWidget.showOnSwipeUp != widget.showOnSwipeUp ||
        oldWidget.enableSwipeToDismiss != widget.enableSwipeToDismiss) {
      _apply();
    }
  }

  @override
  void dispose() {
    final KeyboardController keyboard = KeyboardController.instance;
    keyboard.configureInteractiveKeyboard(enabled: false);
    keyboard.setInteractiveKeyboardArea(null);
    super.dispose();
  }

  void _apply() {
    KeyboardController.instance.configureInteractiveKeyboard(
      enabled: widget.enabled,
      offset: widget.offset,
      interpolator: widget.interpolator,
      showOnSwipeUp: widget.showOnSwipeUp,
      enableSwipeToDismiss: widget.enableSwipeToDismiss,
    );
    _reportArea();
  }

  /// Native code sees raw window touches, so it needs this widget's bounds to
  /// know which ones belong to the area.
  void _reportArea() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final RenderObject? object = context.findRenderObject();
      if (object is! RenderBox || !object.attached || !object.hasSize) return;

      final Rect area = object.localToGlobal(Offset.zero) & object.size;
      if (area == _reportedArea) return;
      _reportedArea = area;
      KeyboardController.instance
          .setInteractiveKeyboardArea(widget.enabled ? area : null);
    });
  }

  @override
  Widget build(BuildContext context) {
    _reportArea();
    return widget.child;
  }
}

/// Window-wide interactive keyboard dragging, without a widget.
///
/// Use [KeyboardGestureArea] when the gesture should be limited to part of the
/// screen; this turns it on for the whole window, which is what you want when
/// the whole screen is one chat or form.
abstract final class InteractiveKeyboard {
  /// Whether this platform can hand over control of the keyboard position.
  ///
  /// `false` on Android below API 30, which has no inset-control API.
  static Future<bool> isSupported() =>
      KeyboardController.instance.isInteractiveKeyboardSupported();

  /// Starts intercepting drags. Returns whether it took effect.
  static Future<bool> enable({
    double offset = 0,
    KeyboardInterpolator interpolator = KeyboardInterpolator.ios,
    bool showOnSwipeUp = false,
    bool enableSwipeToDismiss = true,
  }) async {
    await KeyboardController.instance.setInteractiveKeyboardArea(null);
    return KeyboardController.instance.configureInteractiveKeyboard(
      enabled: true,
      offset: offset,
      interpolator: interpolator,
      showOnSwipeUp: showOnSwipeUp,
      enableSwipeToDismiss: enableSwipeToDismiss,
    );
  }

  static Future<void> disable() =>
      KeyboardController.instance.configureInteractiveKeyboard(enabled: false);
}
