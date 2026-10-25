import 'package:flutter/widgets.dart';

/// Walks the Flutter focus tree to find text fields, the counterpart of RNKC's
/// native `ViewHierarchyNavigator`.
///
/// RNKC searches the Android/iOS view hierarchy for `EditText`/`UITextField`
/// instances. Flutter paints its text fields itself, so there is no native view
/// to find; the equivalent structure is the focus tree, where every
/// [EditableText] registers a node. Searching that tree is what makes
/// prev/next navigation work with ordinary [TextField]s.
abstract final class FocusedInputTraversal {
  /// Returns [node]'s [EditableTextState] when the node belongs to a text
  /// field, `null` otherwise.
  ///
  /// [EditableText] attaches the field's [FocusNode] through a [Focus] widget
  /// inside its own subtree, so the state sits above the node's context.
  ///
  /// A node can outlive the field it was attached to — a caller-owned
  /// [FocusNode] keeps pointing at its old element after the field leaves the
  /// tree — so an unmounted context counts as "not a text field". Every lookup
  /// in this package goes through here first.
  static EditableTextState? editableOf(FocusNode? node) {
    final BuildContext? context = node?.context;
    if (context == null || !context.mounted) return null;
    return context.findAncestorStateOfType<EditableTextState>();
  }

  static bool isTextField(FocusNode node) => editableOf(node) != null;

  /// Every focusable text field in [node]'s scope, in reading order.
  ///
  /// Ordered geometrically — top to bottom, then along the reading direction —
  /// rather than by tree position, so the arrows follow what the user sees
  /// even when the widget order and the visual order disagree. (Flutter's own
  /// [ReadingOrderTraversalPolicy] sorts the same way but keeps its comparator
  /// `@protected`, so it cannot be reused from here.)
  static List<FocusNode> fieldsInScopeOf(FocusNode node) {
    final FocusScopeNode? scope = node.enclosingScope;
    if (scope == null) return <FocusNode>[node];

    final List<FocusNode> fields = scope.traversalDescendants
        .where(
          (FocusNode it) =>
              it.canRequestFocus && !it.skipTraversal && isTextField(it),
        )
        .toList();

    // The focused node is always part of the set, even if it has since been
    // marked unfocusable, so the caller can locate the current field.
    if (!fields.contains(node) && isTextField(node)) fields.add(node);

    final BuildContext? context = node.context;
    final bool rtl = context != null &&
        context.mounted &&
        Directionality.maybeOf(context) == TextDirection.rtl;

    fields.sort((FocusNode a, FocusNode b) {
      final Rect ra = a.rect;
      final Rect rb = b.rect;
      // Same row (overlapping vertically) compares horizontally.
      if (ra.bottom > rb.top && rb.bottom > ra.top) {
        return rtl ? rb.left.compareTo(ra.left) : ra.left.compareTo(rb.left);
      }
      return ra.top.compareTo(rb.top);
    });

    return fields;
  }

  /// Index of [node] among the text fields of its scope, and how many there
  /// are — what RNKC reports as `focusDidSet`.
  static (int index, int count) positionOf(FocusNode node) {
    final List<FocusNode> fields = fieldsInScopeOf(node);
    return (fields.indexOf(node), fields.length);
  }

  /// Moves focus to the text field [step] positions away from [node], if any.
  ///
  /// Returns whether focus moved. Unlike [FocusTraversalPolicy.next] this skips
  /// buttons and other focusables, matching RNKC's behaviour of hopping between
  /// inputs only.
  static bool move(FocusNode node, int step) {
    final List<FocusNode> fields = fieldsInScopeOf(node);
    final int index = fields.indexOf(node);
    if (index == -1) return false;

    final int target = index + step;
    if (target < 0 || target >= fields.length) return false;

    fields[target].requestFocus();
    return true;
  }
}
