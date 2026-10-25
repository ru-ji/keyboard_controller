import 'package:flutter/widgets.dart';

import '../keyboard_controller.dart';
import '../types.dart';

/// Rebuilds on every frame of keyboard movement.
///
/// The equivalent of RNKC's `useKeyboardAnimation()` /
/// `useReanimatedKeyboardAnimation()`: [builder] receives the live
/// [KeyboardEvent], so `height` and `progress` are available per frame.
///
/// Pass the expensive part of the subtree as [child]: it is built once and
/// handed back untouched, so per-frame work stays inside the closure. Prefer
/// moving [child] with [Transform.translate] over changing padding — a
/// transform resolves at paint time and costs no layout pass.
///
/// ```dart
/// KeyboardAnimationBuilder(
///   child: const ExpensiveComposer(),
///   builder: (context, keyboard, child) => Transform.translate(
///     offset: Offset(0, -keyboard.height),
///     child: child,
///   ),
/// )
/// ```
class KeyboardAnimationBuilder extends StatelessWidget {
  const KeyboardAnimationBuilder({
    super.key,
    required this.builder,
    this.child,
  });

  final Widget Function(
    BuildContext context,
    KeyboardEvent keyboard,
    Widget? child,
  ) builder;

  /// Built once, never rebuilt by keyboard movement.
  final Widget? child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<KeyboardEvent>(
        valueListenable: KeyboardController.instance.metrics,
        builder: builder,
        child: child,
      );
}

/// Rebuilds when the keyboard's discrete state changes — shown/hidden,
/// height, appearance, type.
///
/// The equivalent of RNKC's `useKeyboardState()`. Unlike
/// [KeyboardAnimationBuilder] this does **not** rebuild per frame: it follows
/// `keyboardWillShow`/`keyboardDidHide` only, which is what you want for
/// anything that merely reacts to the keyboard being there.
///
/// [selector] narrows what counts as a change, so a widget that only cares
/// about visibility is not rebuilt when the height changes:
///
/// ```dart
/// KeyboardStateBuilder<bool>(
///   selector: (state) => state.isVisible,
///   builder: (context, visible, _) => Text('$visible'),
/// )
/// ```
class KeyboardStateBuilder<T> extends StatefulWidget {
  const KeyboardStateBuilder({
    super.key,
    required this.selector,
    required this.builder,
    this.child,
  });

  final T Function(KeyboardState state) selector;

  final Widget Function(BuildContext context, T value, Widget? child) builder;

  final Widget? child;

  @override
  State<KeyboardStateBuilder<T>> createState() =>
      _KeyboardStateBuilderState<T>();
}

class _KeyboardStateBuilderState<T> extends State<KeyboardStateBuilder<T>> {
  late T _value = widget.selector(KeyboardController.instance.state);
  VoidCallback? _remove;

  @override
  void initState() {
    super.initState();
    // Both edges of the state: `willShow` carries the new height before the
    // transition, `didHide` is the only point at which the keyboard is gone.
    _remove = KeyboardController.instance.addHandler(
      KeyboardHandler(onStart: (_) => _update(), onEnd: (_) => _update()),
    );
  }

  @override
  void didUpdateWidget(KeyboardStateBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selector != widget.selector) _update();
  }

  @override
  void dispose() {
    _remove?.call();
    super.dispose();
  }

  void _update() {
    if (!mounted) return;
    final T next = widget.selector(KeyboardController.instance.state);
    if (next == _value) return;
    setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _value, widget.child);
}
