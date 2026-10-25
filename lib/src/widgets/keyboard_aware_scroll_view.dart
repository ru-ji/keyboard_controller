import 'package:flutter/widgets.dart';

import '../keyboard_controller.dart';
import '../types.dart';

/// A scroll view that keeps the focused field — and the caret inside it —
/// above the keyboard, moving in step with the keyboard animation.
///
/// The port of RNKC's `KeyboardAwareScrollView`, including caret-aware
/// scrolling for multiline fields, [snapToOffsets], [bottomOffset] and
/// [extraKeyboardSpace]. It works with ordinary [TextField]s: the focused
/// field is found through the Flutter focus tree and measured in Dart.
///
/// Pass either [child] (like [SingleChildScrollView]) or [slivers] (like
/// [CustomScrollView]).
///
/// ```dart
/// KeyboardAwareScrollView(
///   bottomOffset: 20,
///   child: Column(children: [for (final f in fields) TextField(controller: f)]),
/// )
/// ```
///
/// RNKC also offers a `mode` of `"insets"`, which extends the scrollable area
/// without reflowing content. Flutter has no content-inset concept — extra
/// scrollable space is always a real box — so there is one mode here, matching
/// RNKC's `"layout"`.
class KeyboardAwareScrollView extends StatefulWidget {
  const KeyboardAwareScrollView({
    super.key,
    this.child,
    this.slivers,
    this.controller,
    this.bottomOffset = 0,
    this.disableScrollOnKeyboardHide = false,
    this.enabled = true,
    this.extraKeyboardSpace = 0,
    this.snapToOffsets,
    this.padding,
    this.physics,
    this.primary,
    this.keyboardDismissBehavior,
    this.reverse = false,
    this.restorationId,
    this.clipBehavior = Clip.hardEdge,
  }) : assert(
          (child == null) != (slivers == null),
          'Pass exactly one of child or slivers.',
        );

  /// A single scrollable child, as [SingleChildScrollView] takes.
  final Widget? child;

  /// Slivers, as [CustomScrollView] takes.
  final List<Widget>? slivers;

  final ScrollController? controller;

  /// Space to leave between the caret and the top of the keyboard.
  final double bottomOffset;

  /// Keep the current scroll position when the keyboard hides instead of
  /// scrolling back.
  final bool disableScrollOnKeyboardHide;

  /// When `false` this behaves like a plain scroll view.
  final bool enabled;

  /// Extra scrollable space added below the keyboard.
  final double extraKeyboardSpace;

  /// Scroll offsets to snap to instead of stopping at the computed position.
  final List<double>? snapToOffsets;

  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final bool? primary;
  final ScrollViewKeyboardDismissBehavior? keyboardDismissBehavior;
  final bool reverse;
  final String? restorationId;
  final Clip clipBehavior;

  @override
  KeyboardAwareScrollViewState createState() => KeyboardAwareScrollViewState();
}

/// State of a [KeyboardAwareScrollView].
///
/// Reach it with a `GlobalKey<KeyboardAwareScrollViewState>` to call
/// [assureFocusedInputVisible] — the equivalent of RNKC's ref method.
class KeyboardAwareScrollViewState extends State<KeyboardAwareScrollView> {
  /// Bottom spacer height, driven frame by frame.
  final ValueNotifier<double> _keyboardFrame = ValueNotifier<double>(0);

  /// Rapid typing would otherwise re-scroll on every keystroke; RNKC throttles
  /// the same way, and resets the window on each skipped call.
  static const Duration _typingThrottle = Duration(milliseconds: 200);

  ScrollController? _ownController;
  ScrollController get _controller =>
      widget.controller ?? (_ownController ??= ScrollController());

  VoidCallback? _removeKeyboardHandler;
  VoidCallback? _removeInputHandler;

  // Mirrors of RNKC's shared values. See the flow chart in its source: every
  // transition starts in `onStart`, which memoizes what `onMove` then
  // interpolates, and `onEnd` covers the cases where `onMove` never runs
  // (an instant transition when focus hops between fields).
  double _scrollPosition = 0;
  double _keyboardHeight = 0;
  bool _keyboardWillAppear = false;
  int _tag = -1;
  double _initialKeyboardSize = 0;
  double _scrollBeforeKeyboardMovement = 0;
  FocusedInput? _layout;
  FocusedInputSelection? _lastSelection;
  bool _pendingSelectionForFocus = false;
  bool _selectionUpdatedSinceHide = false;
  double _scrollViewPageY = 0;
  DateTime _lastTypingScroll = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    final KeyboardController keyboard = KeyboardController.instance;

    _removeKeyboardHandler = keyboard.addHandler(
      KeyboardHandler(
        onStart: _onKeyboardStart,
        onMove: _onKeyboardMove,
        onInteractive: _onKeyboardMove,
        onEnd: _onKeyboardEnd,
      ),
    );
    _removeInputHandler = keyboard.addFocusedInputHandler(
      FocusedInputHandler(onSelectionChange: _onSelectionChange),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _syncViewportOrigin());
  }

  @override
  void didUpdateWidget(KeyboardAwareScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bottomOffset != widget.bottomOffset) {
      assureFocusedInputVisible();
    }
  }

  @override
  void dispose() {
    _removeKeyboardHandler?.call();
    _removeInputHandler?.call();
    _keyboardFrame.dispose();
    _ownController?.dispose();
    super.dispose();
  }

  // region Geometry helpers

  void _syncViewportOrigin() {
    final RenderObject? object = context.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) return;
    _scrollViewPageY = object.localToGlobal(Offset.zero).dy;
  }

  double get _offset =>
      _controller.hasClients ? _controller.position.pixels : 0;

  void _jumpTo(double value) {
    if (!_controller.hasClients) return;
    final ScrollPosition position = _controller.position;
    _controller.jumpTo(
      value.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  /// Linear map, matching Reanimated's `interpolate` with its default
  /// (extending, non-clamping) extrapolation.
  static double _interpolate(
    double value,
    double inMin,
    double inMax,
    double outMin,
    double outMax,
  ) {
    if (inMax == inMin) return outMax;
    return outMin + (outMax - outMin) * ((value - inMin) / (inMax - inMin));
  }

  double _withSnapPoints(double value) {
    final List<double>? points = widget.snapToOffsets;
    if (points == null) return value;
    for (final double point in points) {
      if (point >= value) return point;
    }
    return value;
  }

  /// Whether the focused field lives in *this* scroll view.
  ///
  /// RNKC compares native view tags; here the scroll position the field
  /// reported is matched against the ones this controller drives, which also
  /// stays correct when scroll views are nested.
  bool get _ownsFocusedInput {
    final ScrollableState? theirs = _layout?.parentScrollable;
    if (theirs == null || !_controller.hasClients) return false;
    return _controller.positions.contains(theirs.position);
  }

  // endregion

  // region Scrolling

  /// Scrolls so the focused field clears a keyboard of height [frameHeight].
  ///
  /// Returns the distance it decided to scroll, which the caller folds into
  /// its own bookkeeping — exactly as RNKC's `maybeScroll` does.
  double _maybeScroll(double frameHeight, {bool animated = false}) {
    if (!widget.enabled) return 0;
    final FocusedInput? layout = _layout;
    if (layout == null || !_ownsFocusedInput) return 0;

    final double screenHeight = MediaQuery.sizeOf(context).height;
    final double visibleRect = screenHeight - _keyboardHeight;
    final double point = layout.layout.absoluteY + layout.layout.height;

    if (visibleRect - point <= widget.bottomOffset) {
      final double relativeScrollTo =
          _keyboardHeight - (screenHeight - point) + widget.bottomOffset;
      final double interpolated = _interpolate(
        frameHeight,
        _initialKeyboardSize,
        _keyboardHeight,
        0,
        _withSnapPoints(relativeScrollTo + _scrollPosition) - _scrollPosition,
      );

      _jumpTo(interpolated.clamp(0, double.infinity) + _scrollPosition);

      return interpolated;
    }

    // The field sits above the viewport: bring it down into view.
    if (point < _scrollViewPageY) {
      final double positionOnScreen = visibleRect - widget.bottomOffset;
      final double topOfScreen = _scrollPosition + point;
      _jumpTo(topOfScreen - positionOnScreen);
    }

    return 0;
  }

  void _performScrollWithPositionRestoration(double newPosition) {
    final double previous = _scrollPosition;
    _scrollPosition = newPosition;
    _maybeScroll(_keyboardHeight, animated: true);
    _scrollPosition = previous;
  }

  void _syncKeyboardFrame(KeyboardEvent e) {
    _keyboardFrame.value = _keyboardHeight == 0
        ? e.height
        : _interpolate(
            e.height,
            0,
            _keyboardHeight,
            0,
            _keyboardHeight + widget.extraKeyboardSpace,
          );
  }

  /// Replaces the focused field's height with "height up to the caret", so a
  /// multiline field that has grown keeps the *caret* visible rather than its
  /// whole box.
  bool _updateLayoutFromSelection() {
    final FocusedInput? input = KeyboardController.instance.focusedInput.value;
    final double? caretBottom = _lastSelection?.end.y;
    if (input == null || caretBottom == null) return false;

    _layout = input.copyWith(
      layout: input.layout.copyWith(
        height: caretBottom.clamp(0, input.layout.height),
      ),
    );

    return true;
  }

  void _scrollFromCurrentPosition() {
    final FocusedInput? previous = _layout;
    if (!_updateLayoutFromSelection()) return;
    _performScrollWithPositionRestoration(_offset);
    _layout = previous;
  }

  // endregion

  // region Handlers

  void _onSelectionChange(FocusedInputSelection selection) {
    final int? lastTarget = _lastSelection?.target;
    final FocusedInputSelection? latest = _lastSelection;

    _lastSelection = selection;
    _selectionUpdatedSinceHide = true;

    if (selection.target != lastTarget || _pendingSelectionForFocus) {
      if (_pendingSelectionForFocus) {
        // The selection arrived after `onStart`; finish the deferred setup.
        _pendingSelectionForFocus = false;
        _updateLayoutFromSelection();

        // The keyboard was already up, so no `onMove` is coming: scroll now.
        if (!_keyboardWillAppear && _keyboardHeight > 0) {
          _maybeScroll(_keyboardHeight, animated: true);
        }
      }
      return;
    }

    // Caret at the end and its y moved: a new line, so the field may have grown.
    if (selection.end.position == selection.start.position &&
        latest?.end.y != selection.end.y) {
      _scrollFromCurrentPosition();
      return;
    }

    // A real selection, not just a caret.
    if (selection.start.position != selection.end.position) {
      _scrollFromCurrentPosition();
      return;
    }

    // Plain typing: throttled, since every keystroke lands here.
    final DateTime now = DateTime.now();
    if (now.difference(_lastTypingScroll) < _typingThrottle) {
      _lastTypingScroll = now;
      return;
    }
    _lastTypingScroll = now;
    _scrollFromCurrentPosition();
  }

  void _onKeyboardStart(KeyboardEvent e) {
    _syncViewportOrigin();

    final bool keyboardWillChangeSize =
        _keyboardHeight != e.height && e.height > 0;

    _keyboardWillAppear = e.height > 0 && _keyboardHeight == 0;
    final bool keyboardWillHide = e.height == 0;

    final bool focusWasChanged =
        (_tag != e.target && e.target != -1) || keyboardWillChangeSize;

    if (keyboardWillChangeSize) _initialKeyboardSize = _keyboardHeight;

    if (keyboardWillHide) {
      // Hiding interpolates back over [0, keyboardHeight].
      _initialKeyboardSize = 0;
      _scrollPosition = _scrollBeforeKeyboardMovement;
      _pendingSelectionForFocus = false;
    }

    if (_keyboardWillAppear || keyboardWillChangeSize || focusWasChanged) {
      _scrollPosition = _offset;
      _keyboardHeight = e.height;
    }

    if (focusWasChanged) {
      _tag = e.target;

      final FocusedInput? input =
          KeyboardController.instance.focusedInput.value;

      if (_lastSelection?.target == e.target && _selectionUpdatedSinceHide) {
        // A fresh selection beat `onStart` here; use it.
        _updateLayoutFromSelection();
        _pendingSelectionForFocus = false;
      } else {
        // No selection for the new field yet, or a stale one from the previous
        // session. Use the stale value for the same target as a best effort,
        // otherwise the whole field rect, and correct it when a fresh
        // selection arrives.
        if (_lastSelection?.target == e.target) {
          _updateLayoutFromSelection();
        } else if (input != null) {
          _layout = input;
        }
        _pendingSelectionForFocus = true;
      }

      // Remembered so hiding the keyboard can scroll smoothly back.
      _scrollBeforeKeyboardMovement = _offset;
    }

    if (focusWasChanged &&
        !_keyboardWillAppear &&
        !_pendingSelectionForFocus) {
      _maybeScroll(e.height, animated: true);
    }

    // The spacer is *not* sized here. In RNKC's layout mode — the only one
    // Flutter has — it must grow frame by frame in `onMove`, or the content
    // reflows to the full keyboard height before the keyboard has moved.
  }

  void _onKeyboardMove(KeyboardEvent e) {
    if (_pendingSelectionForFocus && _lastSelection?.target != _tag) return;

    _syncKeyboardFrame(e);

    if (!widget.disableScrollOnKeyboardHide || _keyboardWillAppear) {
      _maybeScroll(e.height);
    }
  }

  void _onKeyboardEnd(KeyboardEvent e) {
    _keyboardHeight = e.height;
    _scrollPosition = _offset;

    if (e.height == 0) {
      _selectionUpdatedSinceHide = false;
    } else if (_keyboardWillAppear) {
      // Fully shown after appearing: clear the flag so it cannot leak into the
      // next focus change.
      _pendingSelectionForFocus = false;
    }

    _syncKeyboardFrame(e);
  }

  // endregion

  /// Re-measures the focused field and scrolls it into view if needed.
  ///
  /// Call this after changing layout around the field in a way the keyboard
  /// never heard about. Equivalent to RNKC's `assureFocusedInputVisible()`.
  void assureFocusedInputVisible() {
    KeyboardController.instance.syncUpFocusedInputLayout();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncViewportOrigin();
      _scrollFromCurrentPosition();
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> slivers = <Widget>[
      if (widget.slivers != null)
        ...widget.slivers!
      else
        SliverToBoxAdapter(child: widget.child),
      if (widget.enabled)
        SliverToBoxAdapter(
          child: ValueListenableBuilder<double>(
            valueListenable: _keyboardFrame,
            builder: (BuildContext context, double height, _) => SizedBox(
              // The extra pixel keeps the scroll view from reaching its exact
              // end mid-animation, where it would otherwise re-run layout on
              // every frame (RNKC hits the same problem; see its PR #342).
              height: height + 1,
            ),
          ),
        ),
    ];

    return CustomScrollView(
      controller: _controller,
      physics: widget.physics,
      primary: widget.primary,
      reverse: widget.reverse,
      restorationId: widget.restorationId,
      clipBehavior: widget.clipBehavior,
      keyboardDismissBehavior: widget.keyboardDismissBehavior ??
          ScrollViewKeyboardDismissBehavior.manual,
      slivers: widget.padding == null
          ? slivers
          : <Widget>[
              SliverPadding(
                padding: widget.padding!,
                sliver: SliverMainAxisGroup(slivers: slivers),
              ),
            ],
    );
  }
}
