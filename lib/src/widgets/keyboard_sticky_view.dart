import 'package:flutter/widgets.dart';

import '../types.dart';
import 'keyboard_animation_builder.dart';

/// Extra translation to apply at each end of the keyboard transition.
@immutable
class KeyboardStickyOffset {
  const KeyboardStickyOffset({this.closed = 0, this.opened = 0});

  /// Added to `translateY` when the keyboard is closed.
  final double closed;

  /// Added to `translateY` when the keyboard is open.
  final double opened;

  static const KeyboardStickyOffset zero = KeyboardStickyOffset();
}

/// Sticks its child to the top of the keyboard, following it frame by frame.
///
/// The port of RNKC's `KeyboardStickyView`. The child is moved with a
/// [Transform], so following the keyboard costs no layout pass; place it at the
/// bottom of a [Stack] or [Column] as you would any bottom bar.
///
/// ```dart
/// KeyboardStickyView(
///   offset: const KeyboardStickyOffset(opened: 20),
///   child: ElevatedButton(onPressed: submit, child: const Text('Send')),
/// )
/// ```
class KeyboardStickyView extends StatelessWidget {
  const KeyboardStickyView({
    super.key,
    required this.child,
    this.offset = KeyboardStickyOffset.zero,
    this.enabled = true,
  });

  final Widget child;

  final KeyboardStickyOffset offset;

  /// When `false` the child stays at [KeyboardStickyOffset.closed].
  final bool enabled;

  @override
  Widget build(BuildContext context) => KeyboardAnimationBuilder(
        child: child,
        builder: (BuildContext context, KeyboardEvent keyboard, Widget? child) {
          final double extra = offset.closed +
              (offset.opened - offset.closed) * keyboard.progress;
          final double dy = enabled ? -keyboard.height + extra : offset.closed;

          return Transform.translate(offset: Offset(0, dy), child: child);
        },
      );
}
