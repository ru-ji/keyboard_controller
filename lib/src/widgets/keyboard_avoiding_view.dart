import 'dart:math' as math;

import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';

import '../keyboard_controller.dart';
import '../types.dart';

/// How a [KeyboardAvoidingView] reacts to the keyboard.
enum KeyboardAvoidingBehavior {
  /// Grows bottom padding so the content is pushed above the keyboard.
  padding,

  /// Shrinks the view itself, letting its own layout reflow.
  height,

  /// Moves the content up without changing its size.
  position,

  /// Moves the content up while the keyboard travels, then converts the shift
  /// into top padding once it settles.
  ///
  /// This is RNKC's `translate-with-padding`: the transform keeps the
  /// transition free of layout passes, and the padding at the end leaves the
  /// content in a position the rest of the layout can see.
  translateWithPadding,
}

/// Keeps its child clear of the keyboard.
///
/// The port of RNKC's `KeyboardAvoidingView`, including all four behaviours.
/// Unlike Flutter's own bottom-inset padding this follows the keyboard frame by
/// frame and accounts for where the view actually sits on screen, so a view
/// above a bottom bar or inside a sheet is not over-padded.
///
/// ```dart
/// KeyboardAvoidingView(
///   behavior: KeyboardAvoidingBehavior.padding,
///   child: Column(children: [TextField(), SubmitButton()]),
/// )
/// ```
class KeyboardAvoidingView extends StatefulWidget {
  const KeyboardAvoidingView({
    super.key,
    required this.child,
    this.behavior = KeyboardAvoidingBehavior.padding,
    this.keyboardVerticalOffset = 0,
    this.enabled = true,
  });

  final Widget child;

  final KeyboardAvoidingBehavior behavior;

  /// Extra space to leave between the content and the keyboard.
  ///
  /// Purely additive: the view measures its own position on screen, so this is
  /// never needed to compensate for app bars or sheets — it only adds slack.
  /// (RNKC needs `automaticOffset` for this; in Flutter the absolute position
  /// is always available, so it is always on.)
  final double keyboardVerticalOffset;

  /// When `false` the child is laid out as if there were no keyboard. Useful
  /// when more than one avoiding view is on screen.
  final bool enabled;

  @override
  State<KeyboardAvoidingView> createState() => _KeyboardAvoidingViewState();
}

class _KeyboardAvoidingViewState extends State<KeyboardAvoidingView> {
  /// `progress` driving the continuous transform.
  final ValueNotifier<double> _translate = ValueNotifier<double>(0);

  /// `progress` driving the padding, which only moves at the ends of a
  /// transition so that content never jumps mid-flight.
  final ValueNotifier<double> _padding = ValueNotifier<double>(0);

  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  Rect? _frame;
  double _heightWhenOpened = 0;
  bool _isClosed = true;
  VoidCallback? _removeHandler;

  @override
  void initState() {
    super.initState();
    _removeHandler = KeyboardController.instance.addHandler(
      KeyboardHandler(
        onStart: (KeyboardEvent e) {
          // Measured before the flags flip: at this point the view is still
          // laid out as if there were no keyboard, which is the frame the
          // calculation below needs.
          _measure();
          if (e.height > 0) {
            _isClosed = false;
            _heightWhenOpened = e.height;
          } else {
            _padding.value = 0;
          }
          // Nothing moves here: `e` is the destination. RNKC does set
          // `translate` at start on iOS, but only because React Native runs
          // that change inside the keyboard's own UIKit animation. Flutter has
          // no such implicit animation, so the same line would make the view
          // jump to the end of the transition and back.
        },
        onMove: (KeyboardEvent e) {
          _translate.value = e.progress;
          _progress.value = e.progress;
        },
        onInteractive: (KeyboardEvent e) {
          // A finger-driven move has no settled end, so the padding is cleared
          // and only the transform follows.
          _padding.value = 0;
          _translate.value = e.progress;
          _progress.value = e.progress;
        },
        onEnd: (KeyboardEvent e) {
          _isClosed = e.height == 0;
          _translate.value = e.progress;
          _padding.value = e.progress;
          _progress.value = e.progress;
          // Back to rest: the view is free to be re-measured again.
          if (_isClosed) _scheduleMeasure();
        },
      ),
    );
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(KeyboardAvoidingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleMeasure();
  }

  @override
  void dispose() {
    _removeHandler?.call();
    _translate.dispose();
    _padding.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    // Only measured at rest. Every behaviour changes this view's own box, so
    // re-measuring mid-transition would feed the adjusted box back into the
    // calculation and run away. RNKC can get away with measuring continuously
    // because its views are flex-constrained; a Flutter widget may well be in
    // an unconstrained slot, where `Padding` really does grow the box.
    if (!_isClosed && _frame != null) return;

    final RenderObject? object = context.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) return;

    final Rect frame = object.localToGlobal(Offset.zero) & object.size;
    if (frame == _frame) return;
    _frame = frame;
    // Nothing rebuilt here: the listenable builders below read `_frame` on
    // their next tick, and the next keyboard frame is at most 8ms away.
  }

  /// How much of the view the keyboard would cover, in logical pixels.
  double _relativeKeyboardHeight(double screenHeight) {
    final Rect? frame = _frame;
    if (frame == null) return 0;

    final double keyboardTop =
        screenHeight - _heightWhenOpened - widget.keyboardVerticalOffset;

    return (frame.bottom - keyboardTop).clamp(0, double.infinity);
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.sizeOf(context).height;

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_translate, _padding, _progress]),
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double relative =
            widget.enabled ? _relativeKeyboardHeight(screenHeight) : 0;
        final double bottom = relative * _progress.value;
        final KeyboardAvoidingBehavior behavior = widget.behavior;

        // Every behaviour renders the *same* widget chain and only feeds it
        // different values. Swapping parents instead — a bare child at rest, a
        // SizedBox once the keyboard is up — makes Flutter discard the subtree
        // and rebuild it, which destroys a focused text field mid-transition:
        // focus is lost and the keyboard that was opening closes again. Zero
        // offsets cost nothing here; a pure translation never pushes a layer.
        return Padding(
          padding: EdgeInsets.only(
            top: behavior == KeyboardAvoidingBehavior.translateWithPadding
                ? relative * _padding.value
                : 0,
            bottom: behavior == KeyboardAvoidingBehavior.padding ? bottom : 0,
          ),
          child: Transform.translate(
            offset: Offset(
              0,
              switch (behavior) {
                KeyboardAvoidingBehavior.position => -bottom,
                KeyboardAvoidingBehavior.translateWithPadding =>
                  -relative * _translate.value,
                _ => 0,
              },
            ),
            child: _Shrink(
              height: behavior == KeyboardAvoidingBehavior.height
                  ? _shrunkHeight(bottom)
                  : null,
              child: child!,
            ),
          ),
        );
      },
    );
  }

  /// The height `height` shrinks the view to, or `null` to leave it alone.
  double? _shrunkHeight(double covered) {
    final double? frame = _frame?.height;
    if (_isClosed || frame == null || covered <= 0) return null;
    return math.max(0, frame - covered);
  }
}

/// Lays [child] out [height] tall — or, with a `null` height, exactly as if
/// this widget were not there.
///
/// A plain `SizedBox` cannot do the shrinking: under tight constraints, such
/// as inside an `Expanded`, the parent's size wins. RNKC has the same problem
/// in React Native and resets `flex` to 0 for it; [OverflowBox] is the Flutter
/// equivalent, keeping its own size while giving the child less.
class _Shrink extends StatelessWidget {
  const _Shrink({required this.height, required this.child});

  final double? height;
  final Widget child;

  @override
  Widget build(BuildContext context) => OverflowBox(
        fit: OverflowBoxFit.deferToChild,
        alignment: Alignment.topCenter,
        minHeight: height,
        maxHeight: height,
        child: child,
      );
}
