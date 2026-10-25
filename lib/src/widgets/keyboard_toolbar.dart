import 'package:flutter/widgets.dart';

import '../keyboard_controller.dart';
import '../types.dart';
import 'keyboard_animation_builder.dart';
import 'keyboard_sticky_view.dart';

/// Colours for one keyboard appearance.
@immutable
class KeyboardToolbarColors {
  const KeyboardToolbarColors({
    required this.primary,
    required this.disabled,
    required this.background,
  });

  /// Arrow and text colour when enabled.
  final Color primary;

  /// Arrow colour when there is nowhere to go.
  final Color disabled;

  final Color background;
}

/// Light and dark colours for a [KeyboardToolbar].
@immutable
class KeyboardToolbarTheme {
  const KeyboardToolbarTheme({required this.light, required this.dark});

  final KeyboardToolbarColors light;
  final KeyboardToolbarColors dark;

  /// The defaults, matching RNKC's `DefaultKeyboardToolbarTheme`.
  static const KeyboardToolbarTheme defaults = KeyboardToolbarTheme(
    light: KeyboardToolbarColors(
      primary: Color(0xFF2C2C2C),
      disabled: Color(0xFFB0BEC5),
      background: Color(0xFFF3F3F4),
    ),
    dark: KeyboardToolbarColors(
      primary: Color(0xFFFAFAFA),
      disabled: Color(0xFF707070),
      background: Color(0xFF2C2C2E),
    ),
  );

  KeyboardToolbarColors of(KeyboardAppearance appearance) =>
      appearance == KeyboardAppearance.dark ? dark : light;
}

/// A bar that sits on top of the keyboard with prev/next arrows and a Done
/// button.
///
/// The port of RNKC's `KeyboardToolbar`. Navigation runs over the Flutter focus
/// tree, so the arrows move between ordinary [TextField]s with no extra wiring,
/// and the arrows disable themselves at the ends of the form.
///
/// Place it as the last child of a [Stack] that fills the screen:
///
/// ```dart
/// Stack(children: [form, const KeyboardToolbar()])
/// ```
class KeyboardToolbar extends StatelessWidget {
  const KeyboardToolbar({
    super.key,
    this.content,
    this.theme = KeyboardToolbarTheme.defaults,
    this.doneText = 'Done',
    this.showArrows = true,
    this.onNext,
    this.onPrev,
    this.onDone,
    this.background,
    this.opacity = 1,
    this.offset = KeyboardStickyOffset.zero,
    this.enabled = true,
    this.insets = EdgeInsets.zero,
  });

  /// Shown in the middle of the bar.
  final Widget? content;

  final KeyboardToolbarTheme theme;

  /// Text of the dismiss button; pass `null` to hide it.
  final String? doneText;

  final bool showArrows;

  /// Called in addition to moving focus.
  final VoidCallback? onNext;
  final VoidCallback? onPrev;

  /// Called in addition to dismissing the keyboard.
  final VoidCallback? onDone;

  /// Painted behind the bar — a blur, a gradient, anything.
  final Widget? background;

  /// Background opacity, `0`–`1`.
  final double opacity;

  final KeyboardStickyOffset offset;

  final bool enabled;

  /// Horizontal safe-area insets, for landscape.
  final EdgeInsets insets;

  /// Height of the bar, matching RNKC.
  static const double height = 42;

  @override
  Widget build(BuildContext context) {
    final bool rounded = KeyboardController.instance.keyboardHasRoundedCorners;
    final double radius = KeyboardController.instance.keyboardBorderRadius;

    return Align(
      alignment: Alignment.bottomCenter,
      child: KeyboardStickyView(
        enabled: enabled,
        offset: KeyboardStickyOffset(
          closed: offset.closed + height,
          // A floating, rounded keyboard sits slightly inset from the bottom,
          // so the bar tucks under its top edge.
          opened: offset.opened + (rounded ? -11 : 0),
        ),
        child: Padding(
          padding: rounded
              ? EdgeInsets.only(left: insets.left + 16, right: insets.right + 16)
              : EdgeInsets.zero,
          child: KeyboardStateBuilder<KeyboardAppearance>(
            selector: (KeyboardState state) => state.appearance,
            builder: (
              BuildContext context,
              KeyboardAppearance appearance,
              _,
            ) {
              final KeyboardToolbarColors colors = theme.of(appearance);
              final Widget bar = SizedBox(
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    ColoredBox(
                      color: colors.background.withValues(alpha: opacity),
                    ),
                    ?background,
                    Padding(
                      padding: rounded
                          ? EdgeInsets.zero
                          : EdgeInsets.only(
                              left: insets.left,
                              right: insets.right,
                            ),
                      child: _ToolbarRow(
                        colors: colors,
                        content: content,
                        doneText: doneText,
                        showArrows: showArrows,
                        onNext: onNext,
                        onPrev: onPrev,
                        onDone: onDone,
                      ),
                    ),
                  ],
                ),
              );

              if (!rounded) return bar;

              return ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(radius),
                  bottom: Radius.circular(radius),
                ),
                child: bar,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ToolbarRow extends StatelessWidget {
  const _ToolbarRow({
    required this.colors,
    required this.content,
    required this.doneText,
    required this.showArrows,
    required this.onNext,
    required this.onPrev,
    required this.onDone,
  });

  final KeyboardToolbarColors colors;
  final Widget? content;
  final String? doneText;
  final bool showArrows;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<({int count, int index})>(
        valueListenable: KeyboardController.instance.focusPosition,
        builder: (BuildContext context, ({int count, int index}) position, _) {
          final bool prevDisabled = position.index <= 0;
          final bool nextDisabled = position.index >= position.count - 1;

          return Row(
            children: <Widget>[
              if (showArrows) ...<Widget>[
                const SizedBox(width: 8),
                _ArrowButton(
                  direction: FocusDirection.prev,
                  disabled: prevDisabled,
                  colors: colors,
                  semanticsLabel: 'Previous field',
                  onPressed: onPrev,
                ),
                _ArrowButton(
                  direction: FocusDirection.next,
                  disabled: nextDisabled,
                  colors: colors,
                  semanticsLabel: 'Next field',
                  onPressed: onNext,
                ),
              ],
              Expanded(
                child: Center(child: content ?? const SizedBox.shrink()),
              ),
              if (doneText != null)
                _DoneButton(
                  text: doneText!,
                  colors: colors,
                  onPressed: onDone,
                ),
            ],
          );
        },
      );
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.direction,
    required this.disabled,
    required this.colors,
    required this.semanticsLabel,
    required this.onPressed,
  });

  final FocusDirection direction;
  final bool disabled;
  final KeyboardToolbarColors colors;
  final String semanticsLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => _TapTarget(
        enabled: !disabled,
        semanticsLabel: semanticsLabel,
        onPressed: () {
          KeyboardController.instance.setFocusTo(direction);
          onPressed?.call();
        },
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: CustomPaint(
              size: const Size(20, 20),
              painter: _ChevronPainter(
                color: disabled ? colors.disabled : colors.primary,
                pointingUp: direction == FocusDirection.prev,
              ),
            ),
          ),
        ),
      );
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({
    required this.text,
    required this.colors,
    required this.onPressed,
  });

  final String text;
  final KeyboardToolbarColors colors;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => _TapTarget(
        enabled: true,
        semanticsLabel: text,
        onPressed: () {
          KeyboardController.instance.dismiss();
          onPressed?.call();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            text,
            style: TextStyle(
              color: colors.primary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}

/// A tap target that fades while pressed.
///
/// Deliberately not an `InkWell`: keeping this package free of a Material
/// dependency means a Cupertino-only or custom-design app pays nothing for it.
class _TapTarget extends StatefulWidget {
  const _TapTarget({
    required this.enabled,
    required this.semanticsLabel,
    required this.onPressed,
    required this.child,
  });

  final bool enabled;
  final String semanticsLabel;
  final VoidCallback onPressed;
  final Widget child;

  @override
  State<_TapTarget> createState() => _TapTargetState();
}

class _TapTargetState extends State<_TapTarget> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: widget.enabled,
        label: widget.semanticsLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown:
              widget.enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel:
              widget.enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.enabled
              ? () {
                  setState(() => _pressed = false);
                  widget.onPressed();
                }
              : null,
          child: Opacity(
            opacity: _pressed ? 0.4 : 1,
            child: ExcludeSemantics(child: widget.child),
          ),
        ),
      );
}

/// The two rounded strokes RNKC draws for its prev/next arrows.
class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color, required this.pointingUp});

  final Color color;
  final bool pointingUp;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final double midX = size.width / 2;
    final double midY = size.height / 2;
    const double arm = 5;

    final double tipY = pointingUp ? midY - arm / 2 : midY + arm / 2;
    final double baseY = pointingUp ? midY + arm / 2 : midY - arm / 2;

    canvas.drawPath(
      Path()
        ..moveTo(midX - arm, baseY)
        ..lineTo(midX, tipY)
        ..lineTo(midX + arm, baseY),
      paint,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter old) =>
      old.color != color || old.pointingUp != pointingUp;
}
