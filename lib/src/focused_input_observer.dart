import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'focus_traversal.dart';
import 'types.dart';

/// Tracks the focused text field: where it is, what it contains, and where the
/// caret sits.
///
/// react-native-keyboard-controller does this natively, by observing the
/// focused `EditText`/`UITextField`. A Flutter [TextField] is not a native
/// view — the engine only owns a hidden input connection — so the native side
/// has nothing to measure. The equivalent information lives in Dart: the
/// focused [FocusNode] gives the rect, its [EditableTextState] gives the text
/// and the caret geometry. Observing it here is what makes every widget in
/// this package work with plain Flutter text fields.
///
/// Geometry is recomputed on focus changes, on text/selection changes and
/// whenever [syncUpLayout] is called — which [KeyboardController] does at the
/// start of each keyboard transition, mirroring RNKC's `syncUpLayout()`. It is
/// deliberately not recomputed every frame.
class FocusedInputObserver {
  FocusedInputObserver({
    required this.onLayout,
    required this.onText,
    required this.onSelection,
    required this.onFocusPosition,
  });

  /// Fires with `null` when no text field is focused.
  final ValueChanged<FocusedInput?> onLayout;
  final ValueChanged<FocusedInputText> onText;
  final ValueChanged<FocusedInputSelection> onSelection;

  /// `(index, count)` of the focused field among its siblings.
  final void Function(int index, int count) onFocusPosition;

  FocusNode? _node;

  /// Survives blur so [setFocusTo] can restore focus, the way RNKC's
  /// `FocusedInputHolder` keeps a weak reference to the last input.
  FocusNode? _lastFocused;
  EditableTextState? _editable;
  TextEditingController? _controller;
  String _lastText = '';
  FocusedInputSelection? _lastSelection;
  FocusedInputLayout? _lastLayout;
  bool _syncScheduled = false;

  /// Keyboard type of the focused field, for [KeyboardEventData.type].
  TextInputType get keyboardType =>
      _editable?.widget.keyboardType ?? TextInputType.text;

  /// Identity of the focused field, or `-1`.
  int get target => _node == null ? -1 : identityHashCode(_node);

  FocusedInputSelection? get selection => _lastSelection;

  void start() {
    FocusManager.instance.addListener(_handleFocusChange);
    _handleFocusChange();
  }

  void dispose() {
    FocusManager.instance.removeListener(_handleFocusChange);
    _detach();
  }

  void _handleFocusChange() {
    final FocusNode? node = FocusManager.instance.primaryFocus;
    if (node == _node) return;

    final EditableTextState? editable = FocusedInputTraversal.editableOf(node);
    if (editable == null) {
      // Focus left text input entirely (a button, or nothing at all).
      if (_node != null) {
        _detach();
        onLayout(null);
      }
      return;
    }

    _detach();

    _node = node;
    _lastFocused = node;
    _editable = editable;
    _controller = editable.widget.controller;
    _lastText = _controller?.text ?? '';
    _controller?.addListener(_handleValueChange);

    final (int index, int count) = FocusedInputTraversal.positionOf(node!);
    onFocusPosition(index, count);

    // Measured straight away when the field is already laid out — which it is
    // whenever focus moves within a live tree — so consumers do not see a
    // frame of `null`. The post-frame pass then corrects it for the case where
    // focus and layout arrive together.
    syncUpLayout();
    _scheduleSync(includeSelection: true);
  }

  void _detach() {
    _controller?.removeListener(_handleValueChange);
    _controller = null;
    _editable = null;
    _node = null;
    _lastSelection = null;
    _lastLayout = null;
  }

  void _handleValueChange() {
    final String text = _controller?.text ?? '';
    if (text != _lastText) {
      _lastText = text;
      onText(FocusedInputText(target: target, text: text));
    }
    // Caret geometry is only valid once the editable has laid out the new
    // value, which is why RNKC reads it from an `onPreDraw` listener; the
    // post-frame callback is the Flutter equivalent.
    _scheduleSync(includeSelection: true);
  }

  void _scheduleSync({required bool includeSelection}) {
    if (_syncScheduled) return;
    _syncScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      syncUpLayout();
      if (includeSelection) _emitSelection();
    });
  }

  /// Re-measures the focused field and reports it if anything moved.
  void syncUpLayout() {
    final FocusedInput? input = measure();
    if (input == null) return;
    if (input.layout == _lastLayout) return;
    _lastLayout = input.layout;
    onLayout(input);
  }

  /// Current geometry of the focused field, or `null` when there is none.
  FocusedInput? measure() {
    final FocusNode? node = _node;
    final BuildContext? context = node?.context;
    // Measurement runs from a post-frame callback, by which time the field may
    // have left the tree. FocusManager reports the blur on its own; all this
    // has to do is not touch the dead element.
    if (node == null || context == null || !context.mounted) return null;

    final RenderObject? object = context.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) return null;

    final Offset origin = object.localToGlobal(Offset.zero);
    final Size size = object.size;

    // RNKC reports `x`/`y` relative to the parent scroll view and
    // `absoluteX`/`absoluteY` relative to the window. The Flutter counterpart
    // of "parent scroll view" is the enclosing Scrollable, so offsets are
    // resolved against its content.
    double x = origin.dx;
    double y = origin.dy;
    final ScrollableState? scrollable = Scrollable.maybeOf(context);
    if (scrollable != null) {
      final RenderObject? viewport = scrollable.context.findRenderObject();
      if (viewport is RenderBox && viewport.attached) {
        final Offset local = viewport.globalToLocal(origin);
        final double scrolled = scrollable.position.pixels;
        final bool vertical = scrollable.position.axis == Axis.vertical;
        x = local.dx + (vertical ? 0 : scrolled);
        y = local.dy + (vertical ? scrolled : 0);
      }
    }

    return FocusedInput(
      target: identityHashCode(node),
      node: node,
      parentScrollable: scrollable,
      layout: FocusedInputLayout(
        x: x,
        y: y,
        width: size.width,
        height: size.height,
        absoluteX: origin.dx,
        absoluteY: origin.dy,
      ),
    );
  }

  void _emitSelection() {
    final FocusedInputSelection? next = measureSelection();
    if (next == null || next == _lastSelection) return;
    _lastSelection = next;
    onSelection(next);
  }

  /// Caret geometry of the focused field, in coordinates local to its rect.
  FocusedInputSelection? measureSelection() {
    final EditableTextState? editable = _editable;
    final BuildContext? context = _node?.context;
    if (editable == null || !editable.mounted) return null;
    if (context == null || !context.mounted) return null;

    final TextSelection selection = editable.textEditingValue.selection;
    if (!selection.isValid) return null;

    final RenderEditable editableBox;
    try {
      editableBox = editable.renderEditable;
    } on Object {
      return null;
    }
    if (!editableBox.attached || !editableBox.hasSize) return null;

    final RenderObject? object = context.findRenderObject();
    if (object is! RenderBox || !object.attached) return null;

    // Caret rects are local to the RenderEditable, which sits inside whatever
    // decoration the field has; shift them so they share the reported rect's
    // coordinate space.
    final Offset delta =
        editableBox.localToGlobal(Offset.zero) - object.localToGlobal(Offset.zero);

    final Rect start = editableBox.getLocalRectForCaret(
      TextPosition(offset: selection.start, affinity: selection.affinity),
    );
    final Rect end = editableBox.getLocalRectForCaret(
      TextPosition(offset: selection.end, affinity: selection.affinity),
    );

    return FocusedInputSelection(
      target: target,
      start: CaretPoint(
        x: start.left + delta.dx,
        y: start.top + delta.dy,
        position: selection.start,
      ),
      // The bottom edge, so the value doubles as "height up to the caret" the
      // way RNKC's Android selection watcher reports it.
      end: CaretPoint(
        x: end.right + delta.dx,
        y: end.bottom + delta.dy,
        position: selection.end,
      ),
    );
  }

  /// Moves focus between text fields. See [FocusedInputTraversal.move].
  bool setFocusTo(FocusDirection direction) {
    final FocusNode? node = _node;
    switch (direction) {
      case FocusDirection.current:
        final FocusNode? restore = node ?? _lastFocused;
        if (restore == null) return false;
        restore.requestFocus();
        return true;
      case FocusDirection.next:
        return node != null && FocusedInputTraversal.move(node, 1);
      case FocusDirection.prev:
        return node != null && FocusedInputTraversal.move(node, -1);
    }
  }
}
