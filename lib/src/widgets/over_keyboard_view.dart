import 'package:flutter/widgets.dart';

/// Shows content above everything else **without closing the keyboard** —
/// the port of RNKC's `OverKeyboardView`.
///
/// It behaves like a modal that the keyboard survives: toggling [visible]
/// mounts and unmounts [child] in the nearest [Overlay], and because nothing
/// here takes focus, the focused field keeps it and the keyboard stays up.
///
/// ```dart
/// OverKeyboardView(
///   visible: showPicker,
///   child: Align(alignment: Alignment.bottomCenter, child: EmojiPicker()),
/// )
/// ```
///
/// **Z-order.** RNKC puts its content in a separate native window, so it can
/// paint on top of the keyboard's own pixels. Flutter draws the whole app into
/// one view and the keyboard is a system window above it, so there is nothing
/// to layer over: this content sits above all app content, but under the
/// keyboard itself. Position it in the space above the keyboard — which is
/// where such panels belong anyway — and it behaves the same.
class OverKeyboardView extends StatefulWidget {
  const OverKeyboardView({super.key, required this.visible, this.child});

  final bool visible;

  final Widget? child;

  @override
  State<OverKeyboardView> createState() => _OverKeyboardViewState();
}

class _OverKeyboardViewState extends State<OverKeyboardView> {
  OverlayEntry? _entry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(OverKeyboardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      _sync();
    } else if (widget.visible) {
      _entry?.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _remove();
    super.dispose();
  }

  void _sync() {
    if (widget.visible) {
      _insert();
    } else {
      _remove();
    }
  }

  void _insert() {
    if (_entry != null) return;
    final OverlayState? overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _entry = OverlayEntry(
      builder: (BuildContext context) =>
          Positioned.fill(child: widget.child ?? const SizedBox.shrink()),
    );
    overlay.insert(_entry!);
  }

  void _remove() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
