import 'package:flutter/widgets.dart';

import '../keyboard_controller.dart';
import '../types.dart';
import 'keyboard_animation_builder.dart';
import 'keyboard_sticky_view.dart';

/// Paints the colour of the keyboard currently installed, so content placed
/// next to the keyboard blends into it.
///
/// The port of RNKC's `KeyboardBackgroundView`. The colour comes from the
/// platform: on Android it is looked up from the active IME package (Gboard,
/// SwiftKey, Samsung, Yandex, AOSP…) in light or dark mode, the same table
/// RNKC ships; on iOS it is the system keyboard backdrop colour. Where the
/// platform cannot say, [fallback] is used.
class KeyboardBackgroundView extends StatefulWidget {
  const KeyboardBackgroundView({
    super.key,
    this.child,
    this.fallback = const Color(0xFFD1D5DB),
  });

  final Widget? child;

  /// Used until — or when — the platform cannot report a colour.
  final Color fallback;

  @override
  State<KeyboardBackgroundView> createState() =>
      _KeyboardBackgroundViewState();
}

class _KeyboardBackgroundViewState extends State<KeyboardBackgroundView>
    with WidgetsBindingObserver {
  Color? _color;
  VoidCallback? _removeHandler;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    // The user can switch keyboards between focuses, and the IME re-themes
    // itself with the system theme, so the colour is re-read on both.
    _removeHandler = KeyboardController.instance.addHandler(
      KeyboardHandler(onStart: (_) => _refresh()),
    );
  }

  @override
  void dispose() {
    _removeHandler?.call();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _refresh();

  Future<void> _refresh() async {
    final Color? color =
        await KeyboardController.instance.keyboardBackgroundColor();
    if (!mounted || color == _color) return;
    setState(() => _color = color);
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: _color ?? widget.fallback,
        child: widget.child,
      );
}

/// Extends the keyboard with your own content, directly above its keys.
///
/// The port of RNKC's `KeyboardExtender`: the content sticks to the top of the
/// keyboard and shares its background colour, so it reads as part of the
/// keyboard rather than as part of the app.
///
/// ```dart
/// KeyboardExtender(
///   child: Row(children: [for (final a in amounts) AmountChip(a)]),
/// )
/// ```
///
/// RNKC can embed real views *inside* the iOS keyboard. That needs a native
/// view to hand to UIKit, which a Flutter widget is not, so this is the port of
/// RNKC's Android implementation — sticky view plus keyboard-coloured
/// background — on both platforms.
class KeyboardExtender extends StatelessWidget {
  const KeyboardExtender({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;

  final bool enabled;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: KeyboardStickyView(
          enabled: enabled,
          child: KeyboardAnimationBuilder(
            child: KeyboardBackgroundView(child: child),
            builder: (
              BuildContext context,
              KeyboardEvent keyboard,
              Widget? child,
            ) =>
                Opacity(opacity: keyboard.progress.clamp(0, 1), child: child),
          ),
        ),
      );
}

/// Renders content *behind* the keyboard, which shows through once the
/// keyboard backdrop is translucent.
///
/// The port of RNKC's `KeyboardEffects`: colours, gradients and animations
/// placed here blend through the keys. Mounting it asks the platform for a
/// translucent backdrop and gives that back on dispose; nesting several is
/// fine, the last one mounted wins.
///
/// Translucency is iOS-only, so on Android this simply draws behind the
/// keyboard's position with no visible effect.
class KeyboardEffects extends StatefulWidget {
  const KeyboardEffects({
    super.key,
    required this.child,
    this.translucent = true,
    this.rounded = true,
    this.offset = KeyboardStickyOffset.zero,
    this.enabled = true,
  });

  final Widget child;

  final bool translucent;

  /// Match the keyboard's rounded top corners where it has them.
  final bool rounded;

  final KeyboardStickyOffset offset;

  final bool enabled;

  @override
  State<KeyboardEffects> createState() => _KeyboardEffectsState();
}

class _KeyboardEffectsState extends State<KeyboardEffects> {
  /// A stack rather than a flag: with several effects mounted, unmounting an
  /// inner one must restore the outer one's choice, not reset to opaque.
  static final List<_KeyboardEffectsState> _stack = <_KeyboardEffectsState>[];
  static bool? _applied;

  @override
  void initState() {
    super.initState();
    _stack.add(this);
    _apply();
  }

  @override
  void didUpdateWidget(KeyboardEffects oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.translucent != widget.translucent) _apply();
  }

  @override
  void dispose() {
    _stack.remove(this);
    _apply();
    super.dispose();
  }

  static void _apply() {
    final bool next = _stack.isNotEmpty && _stack.last.widget.translucent;
    if (next == _applied) return;
    _applied = next;
    KeyboardController.instance.setTranslucent(next);
  }

  @override
  Widget build(BuildContext context) {
    final double radius = KeyboardController.instance.keyboardBorderRadius;
    final bool rounded = widget.rounded && radius > 0;

    // Taller than any keyboard, so the effect still covers it while the
    // keyboard is mid-flight and the sticky view has not caught up.
    Widget effect = SizedBox(height: 999, child: widget.child);

    if (rounded) {
      effect = ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
        child: effect,
      );
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: KeyboardStickyView(
        enabled: widget.enabled,
        offset: widget.offset,
        child: effect,
      ),
    );
  }
}
