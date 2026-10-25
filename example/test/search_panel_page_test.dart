import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_controller/keyboard_controller.dart';
import 'package:keyboard_controller_example/pages/search_panel_page.dart';

const MethodChannel _methods = MethodChannel('keyboard_controller');

// Message codes of the native keyboard channel.
const int _start = 0;
const int _move = 1;
const int _end = 2;
const int _interactive = 3;

/// Feeds one keyboard frame in, exactly as the native side would.
Future<void> _frame(int kind, double height, {double duration = 250}) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'keyboard_controller/messages',
    const StandardMessageCodec().encodeMessage(
      <Object?>[kind, height, height / 300, duration.toInt()],
    ),
    (_) {},
  );
}

/// The panel's on-screen rect: the clip that shapes it.
Rect _panel(WidgetTester tester) => tester.getRect(
      find.descendant(
        of: find.byType(CustomSingleChildLayout),
        matching: find.byType(ClipRRect),
      ),
    );

/// The Search pill in the bottom bar.
final Finder _pill = find.byWidgetPredicate(
  (Widget w) => w is SizedBox && w.width == 140 && w.height == 56,
);

/// The panel's visible shape: its clip, in global coordinates.
RRect _shape(WidgetTester tester) {
  final RenderClipRRect clip = tester.renderObject(
    find.descendant(
      of: find.byType(CustomSingleChildLayout),
      matching: find.byType(ClipRRect),
    ),
  );
  return clip.clipper!
      .getClip(clip.size)
      .shift(clip.localToGlobal(Offset.zero));
}

Future<void> _openPanel(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SearchPanelPage()));
  await tester.tap(_pill);
  await tester.pump();
  // The morph takes 380ms. Not `pumpAndSettle`: the focused field's caret
  // blinks forever, so it never settles.
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_methods, (MethodCall call) async {
      if (call.method == 'getConstants') {
        return <Object?, Object?>{'keyboardBorderRadius': 0.0};
      }
      return null;
    });
    KeyboardController.instance.resetForTesting();
  });

  testWidgets('Search opens the panel and focuses the field',
      (WidgetTester tester) async {
    await _openPanel(tester);

    final EditableText field = tester.widget(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isTrue);
    expect(_panel(tester).top, 48, reason: 'just below the status bar');
  });

  testWidgets('the panel grows out of the Search pill',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SearchPanelPage()));
    final Rect pill = tester.getRect(_pill);

    await tester.tap(_pill);
    await tester.pump();

    // At `t = 0` the panel's shape *is* the pill: same rect, stadium radius.
    RRect shape = _shape(tester);
    expect(shape.outerRect, pill);
    expect(shape.tlRadiusX, 28);

    // First visible frame: the hand-over is continuous, a pixel or two at
    // most even on the steepest part of the curve.
    await tester.pump(const Duration(milliseconds: 1));
    shape = _shape(tester);
    expect(shape.left, closeTo(pill.left, 3));
    expect(shape.right, closeTo(pill.right, 3));
    expect(shape.bottom, closeTo(pill.bottom, 3));

    // And the header carries the hairline divider from the reference.
    expect(
      find.byWidgetPredicate(
        (Widget w) => w is ColoredBox && w.color == const Color(0xFF2B2B2B),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the panel bottom rides the keyboard, frame by frame',
      (WidgetTester tester) async {
    await _openPanel(tester);
    final double screen = tester.view.physicalSize.height /
        tester.view.devicePixelRatio;
    final double top = _panel(tester).top;

    // Every frame of a system animation, and a finger dragging it back down.
    // `start` carries the destination: the keyboard is still at 0 there, and
    // the panel must not jump ahead of it.
    final List<(int, double, double)> frames = <(int, double, double)>[
      // (kind, value sent, where the keyboard actually is)
      (_start, 300, 0),
      (_move, 60, 60),
      (_move, 180, 180),
      (_move, 300, 300),
      (_end, 300, 300),
      (_interactive, 220, 220),
      (_interactive, 90, 90),
    ];

    for (final (int kind, double sent, double keyboard) in frames) {
      await _frame(kind, sent, duration: kind == _interactive ? -1 : 250);
      await tester.pump();

      expect(
        _panel(tester).bottom,
        screen - keyboard - 64,
        reason: '64 above a keyboard $keyboard tall',
      );
      expect(_panel(tester).top, top, reason: 'only the bottom edge moves');
    }
  });

  testWidgets('keyboard frames rebuild nothing inside the page',
      (WidgetTester tester) async {
    await _openPanel(tester);
    final Element page = tester.element(find.byType(SearchPanelPage));

    bool isInsidePage(Element element) {
      if (identical(element, page)) return true;
      bool inside = false;
      element.visitAncestorElements((Element ancestor) {
        inside = identical(ancestor, page);
        return !inside;
      });
      return inside;
    }

    final List<Type> rebuiltInside = <Type>[];
    int rebuiltElsewhere = 0;
    debugOnRebuildDirtyWidget = (Element element, bool builtOnce) {
      if (isInsidePage(element)) {
        rebuiltInside.add(element.widget.runtimeType);
      } else {
        rebuiltElsewhere++;
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    addTearDown(tester.view.resetViewInsets);

    for (double keyboard = 0; keyboard <= 300; keyboard += 25) {
      // What a device does: Flutter's own insets move with this package's
      // frames, so anything that reads `MediaQuery.of` would rebuild here.
      tester.view.viewInsets = FakeViewPadding(
        bottom: keyboard * tester.view.devicePixelRatio,
      );
      await _frame(keyboard == 0 ? _start : _move, keyboard);
      await tester.pump();
    }

    expect(rebuiltInside, isEmpty);
    // Sanity check that the hook was live: the framework's own MediaQuery
    // plumbing does rebuild on every inset change.
    expect(rebuiltElsewhere, greaterThan(0));
  });

  testWidgets('the close button collapses back into the bar',
      (WidgetTester tester) async {
    await _openPanel(tester);

    await tester.tap(find.bySemanticsLabel('Close search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final EditableText field = tester.widget(find.byType(EditableText));
    expect(field.focusNode.hasFocus, isFalse);

    // The bar answers taps again: Search reopens.
    await tester.tap(_pill);
    await tester.pump();
    expect(field.focusNode.hasFocus, isTrue);
  });
}
