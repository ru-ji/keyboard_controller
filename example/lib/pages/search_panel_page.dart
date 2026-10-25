import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:keyboard_controller/keyboard_controller.dart';

/// A bottom bar that grows into a search panel whose bottom edge rides the
/// keyboard — including while the keyboard is dragged away with a finger.
///
/// **Why it stays at display rate.** The panel's frame changes on every frame
/// of keyboard movement, and none of that goes through `build`:
///
///  * Geometry is read at *layout* time by a [SingleChildLayoutDelegate] and a
///    [CustomClipper] that listen to the keyboard and the open animation
///    directly (`relayout:` / `reclip:`). A keyboard frame therefore costs one
///    relayout of the panel and a repaint of its clip — zero rebuilds.
///  * The content is always laid out at the panel's final width. Only its
///    height changes, so the text field keeps its constraints and skips
///    layout entirely; the list just reveals more or fewer rows.
///  * Rows have a fixed extent, so the list never measures them, and the
///    viewport's default cache already holds ~250px of built rows below the
///    fold — about one keyboard's worth. A growing panel uncovers rows that
///    exist rather than building them.
///  * The background dims with a fading scrim rather than a shadow around the
///    panel: a shadow would have to be re-blurred at a new size every frame.
class SearchPanelPage extends StatefulWidget {
  const SearchPanelPage({super.key});

  @override
  State<SearchPanelPage> createState() => _SearchPanelPageState();
}

abstract final class _Palette {
  static const Color background = Color(0xFF141414);
  static const Color button = Color(0xFF2A2A2A);
  static const Color panel = Color(0xFF1E1E1E);
  static const Color skeleton = Color(0xFF2D2D2D);
  static const Color placeholder = Color(0xFF8E8E8E);
  static const Color clear = Color(0xFF5C5C5C);
  static const Color onSurface = Color(0xFFEDEDED);
  static const Color divider = Color(0xFF2B2B2B);
}

/// Measured from the reference recording, in logical pixels.
abstract final class _Size {
  static const double button = 56;
  static const double searchPill = 140;
  static const double barGap = 12;

  /// Above the bottom safe area.
  static const double barBottom = 24;

  static const double panelSide = 20;

  /// Below the top safe area.
  static const double panelTop = 48;

  /// Between the panel and the keyboard — or the screen bottom when the
  /// keyboard is down. Also how close the finger has to come to the keyboard
  /// before it starts following, so the panel edge and the keyboard move off
  /// together.
  static const double panelBottom = 64;

  static const double panelRadius = 20;
  static const double header = 52;
  static const double row = 52;
  static const double rowGap = 8;
}

class _SearchPanelPageState extends State<SearchPanelPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    reverseDuration: const Duration(milliseconds: 300),
  );
  late final Animation<double> _progress = CurvedAnimation(
    parent: _open,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  final FocusNode _focus = FocusNode();
  final TextEditingController _query = TextEditingController();

  bool _isOpen = false;

  /// Built once: opening and closing flip two flags, and nothing in here has
  /// to be rebuilt for that.
  late final Widget _content = _PanelContent(
    focus: _focus,
    query: _query,
    onClose: _close,
  );

  @override
  void dispose() {
    _open.dispose();
    _focus.dispose();
    _query.dispose();
    super.dispose();
  }

  void _openPanel() {
    setState(() => _isOpen = true);
    _open.forward();
    _focus.requestFocus();
  }

  void _close() {
    setState(() => _isOpen = false);
    _open.reverse();
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    // Aspect lookups only. `MediaQuery.of` would subscribe to `viewInsets`
    // too and rebuild this page on every frame of keyboard movement.
    final EdgeInsets padding = MediaQuery.paddingOf(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: PopScope(
        canPop: !_isOpen,
        onPopInvokedWithResult: (bool didPop, _) {
          if (!didPop) _close();
        },
        child: Material(
          color: _Palette.background,
          child: KeyboardGestureArea(
            offset: _Size.panelBottom,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: IgnorePointer(
                    child: FadeTransition(
                      opacity: _progress.drive(Tween<double>(begin: 0, end: 0.45)),
                      child: const ColoredBox(color: Colors.black),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: padding.bottom + _Size.barBottom,
                  child: IgnorePointer(
                    ignoring: _isOpen,
                    child: _BottomBar(
                      onSearch: _openPanel,
                      sides: _progress.drive(
                        Tween<double>(begin: 1, end: 0)
                            .chain(CurveTween(curve: const Interval(0, 0.25))),
                      ),
                      // The panel starts as an exact copy of the pill, so the
                      // pill simply steps aside on the first frame.
                      pill: _progress.drive(
                        Tween<double>(begin: 1, end: 0)
                            .chain(CurveTween(curve: const Threshold(0.001))),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_isOpen,
                    // Hidden only at rest, where the real pill is showing.
                    child: FadeTransition(
                      opacity: _progress.drive(
                        CurveTween(curve: const Threshold(0.001)),
                      ),
                      child: CustomSingleChildLayout(
                        delegate: _PanelLayout(padding: padding, open: _progress),
                        child: ClipRRect(
                          clipper: _PanelClip(open: _progress),
                          // Rebuilds one ColoredBox per frame of the morph
                          // only; the keyboard never drives this.
                          child: AnimatedBuilder(
                            animation: _progress,
                            builder: (BuildContext context, Widget? child) =>
                                ColoredBox(
                              color: Color.lerp(
                                _Palette.button,
                                _Palette.panel,
                                _progress.value,
                              )!,
                              child: child,
                            ),
                            child: Stack(
                              children: <Widget>[
                                FadeTransition(
                                  opacity: _progress.drive(
                                    CurveTween(curve: const Interval(0.35, 1)),
                                  ),
                                  child: _content,
                                ),
                                // The pill's own label, so that at `t = 0`
                                // the panel is pixel-for-pixel the pill.
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  height: _Size.button,
                                  child: ExcludeSemantics(
                                    child: FadeTransition(
                                      opacity: _progress.drive(
                                        Tween<double>(begin: 1, end: 0).chain(
                                          CurveTween(
                                            curve: const Interval(0, 0.3),
                                          ),
                                        ),
                                      ),
                                      child: const Center(child: _SearchLabel()),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the panel is for open-progress [t] and a keyboard [keyboard] tall.
///
/// At `t = 0` the panel *is* the Search pill; at `t = 1` it spans from below
/// the status bar to [_Size.panelBottom] above the keyboard. The bottom edge is
/// always measured from the keyboard's top, so it rides the keyboard at every
/// `t` — including mid-morph, and while a finger drags the keyboard.
@immutable
class _PanelFrame {
  factory _PanelFrame(Size screen, EdgeInsets padding, double t, double keyboard) {
    final double barBottom = screen.height - padding.bottom - _Size.barBottom;
    final double barTop = barBottom - _Size.button;
    final double pillLeft = (screen.width - _Size.searchPill) / 2;

    final double gap =
        lerpDouble(screen.height - barBottom, _Size.panelBottom, t)!;
    final double bottom = screen.height - keyboard - gap;

    // Never shorter than one row. Closing while the keyboard is still up
    // would otherwise invert the panel; instead it collapses to a strip that
    // rides down on the keyboard, which is what the reference does.
    final double minHeight = lerpDouble(_Size.button, _Size.header, t)!;
    final double top = math
        .min(lerpDouble(barTop, padding.top + _Size.panelTop, t)!,
            bottom - minHeight)
        .clamp(0.0, math.max(0.0, bottom));

    return _PanelFrame._(
      top: top,
      height: math.max(0, bottom - top),
      left: lerpDouble(pillLeft, _Size.panelSide, t)!,
      right: lerpDouble(
        pillLeft + _Size.searchPill,
        screen.width - _Size.panelSide,
        t,
      )!,
      radius: lerpDouble(_Size.button / 2, _Size.panelRadius, t)!,
    );
  }

  const _PanelFrame._({
    required this.top,
    required this.height,
    required this.left,
    required this.right,
    required this.radius,
  });

  final double top;
  final double height;
  final double left;
  final double right;
  final double radius;
}

/// Sizes and places the panel content from the live keyboard height.
///
/// `relayout:` is what keeps this off the build path: a keyboard frame marks
/// this delegate's render object for layout directly.
class _PanelLayout extends SingleChildLayoutDelegate {
  _PanelLayout({required this.padding, required this.open})
      : super(
          relayout: Listenable.merge(<Listenable>[
            open,
            KeyboardController.instance.metrics,
          ]),
        );

  final EdgeInsets padding;
  final Animation<double> open;

  _PanelFrame _frame(Size screen) => _PanelFrame(
        screen,
        padding,
        open.value,
        KeyboardController.instance.metrics.value.height,
      );

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final Size screen = constraints.biggest;
    // Always the *final* width: only the height follows the keyboard, so the
    // text field's constraints never change and its layout is skipped.
    return BoxConstraints.tightFor(
      width: screen.width - _Size.panelSide * 2,
      height: _frame(screen).height,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      Offset(_Size.panelSide, _frame(size).top);

  @override
  bool shouldRelayout(_PanelLayout oldDelegate) =>
      oldDelegate.padding != padding || oldDelegate.open != open;
}

/// Clips the full-width content down to the morphing panel shape.
///
/// Vertical extent is the content's own height, which the layout delegate
/// already follows the keyboard with; a size change invalidates the clip on
/// its own. Only the open animation needs `reclip:`.
class _PanelClip extends CustomClipper<RRect> {
  _PanelClip({required this.open}) : super(reclip: open);

  final Animation<double> open;

  @override
  RRect getClip(Size size) {
    final Size screen = Size(size.width + _Size.panelSide * 2, 0);
    final _PanelFrame frame = _PanelFrame(screen, EdgeInsets.zero, open.value, 0);

    return RRect.fromLTRBR(
      frame.left - _Size.panelSide,
      0,
      frame.right - _Size.panelSide,
      size.height,
      Radius.circular(frame.radius),
    );
  }

  @override
  bool shouldReclip(_PanelClip oldClipper) => oldClipper.open != open;
}

class _PanelContent extends StatelessWidget {
  const _PanelContent({
    required this.focus,
    required this.query,
    required this.onClose,
  });

  final FocusNode focus;
  final TextEditingController query;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          // Its own layer: the blinking caret repaints only the header, and
          // the panel resizing never repaints the text.
          RepaintBoundary(
            child: SizedBox(
              height: _Size.header,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      focusNode: focus,
                      controller: query,
                      cursorColor: _Palette.onSurface,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                        color: _Palette.onSurface,
                        fontSize: 16,
                      ),
                      decoration: const InputDecoration.collapsed(
                        hintText: 'Search for people and places',
                        hintStyle: TextStyle(
                          color: _Palette.placeholder,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  _ClearButton(onPressed: onClose),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
          const SizedBox(
            height: 1,
            width: double.infinity,
            child: ColoredBox(color: _Palette.divider),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemExtent: _Size.row + _Size.rowGap,
              itemCount: 24,
              itemBuilder: (BuildContext context, int index) =>
                  const _SkeletonRow(),
            ),
          ),
        ],
      );
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(bottom: _Size.rowGap),
        child: Row(
          children: <Widget>[
            SizedBox.square(
              dimension: _Size.row,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _Palette.skeleton,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _Palette.skeleton,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      );
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Close search',
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _Palette.clear,
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(
                dimension: 24,
                child: Icon(Icons.close, size: 16, color: _Palette.onSurface),
              ),
            ),
          ),
        ),
      );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.onSearch,
    required this.sides,
    required this.pill,
  });

  final VoidCallback onSearch;

  /// History and favourites fade away as the panel opens.
  final Animation<double> sides;

  /// The Search pill hands over to the panel on the first frame.
  final Animation<double> pill;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          FadeTransition(
            opacity: sides,
            child: _BarButton(
              width: _Size.button,
              semanticsLabel: 'History',
              onPressed: () {},
              child: const Icon(
                Icons.history_toggle_off,
                color: _Palette.onSurface,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: _Size.barGap),
          FadeTransition(
            opacity: pill,
            child: _BarButton(
              width: _Size.searchPill,
              semanticsLabel: 'Search',
              onPressed: onSearch,
              child: const _SearchLabel(),
            ),
          ),
          const SizedBox(width: _Size.barGap),
          FadeTransition(
            opacity: sides,
            child: _BarButton(
              width: _Size.button,
              semanticsLabel: 'Favourites',
              onPressed: () {},
              child: const Icon(
                Icons.star_border_rounded,
                color: _Palette.onSurface,
                size: 24,
              ),
            ),
          ),
        ],
      );
}

/// "🔍 Search" — drawn by the pill at rest and by the panel as it takes over,
/// so the two are identical at the handover.
class _SearchLabel extends StatelessWidget {
  const _SearchLabel();

  @override
  Widget build(BuildContext context) => const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.search, color: _Palette.onSurface, size: 20),
          SizedBox(width: 8),
          Text(
            'Search',
            style: TextStyle(
              color: _Palette.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.width,
    required this.semanticsLabel,
    required this.onPressed,
    required this.child,
  });

  final double width;
  final String semanticsLabel;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semanticsLabel,
        excludeSemantics: true,
        child: Material(
          color: _Palette.button,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: width,
              height: _Size.button,
              child: Center(child: child),
            ),
          ),
        ),
      );
}
