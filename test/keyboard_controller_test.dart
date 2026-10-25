import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_controller/keyboard_controller.dart';
import 'package:keyboard_controller/src/platform_channel.dart';

const MethodChannel _methods = MethodChannel('keyboard_controller');
const StandardMessageCodec _codec = StandardMessageCodec();

/// Feeds a native keyboard frame into the controller, exactly as the platform
/// side would.
Future<void> _frame(
  int kind,
  double height,
  double progress, {
  int duration = 250,
}) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'keyboard_controller/messages',
    _codec.encodeMessage(<Object?>[kind, height, progress, duration]),
    (_) {},
  );
}

/// Two frames: one to run the observer's post-frame measurement, one to let
/// whatever it reported reach the widgets.
///
/// Deliberately not `pumpAndSettle`: a focused text field blinks its caret
/// forever, so settling never arrives.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

/// Opens the keyboard to [height] over a start/move/end cycle.
Future<void> _showKeyboard(WidgetTester tester, double height) async {
  await _frame(KeyboardMessage.transitionStart, height, 1);
  await tester.pump();
  await _frame(KeyboardMessage.transitionMove, height / 2, 0.5);
  await tester.pump();
  await _frame(KeyboardMessage.transitionMove, height, 1);
  await tester.pump();
  await _frame(KeyboardMessage.transitionEnd, height, 1);
  await tester.pump();
}

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(resizeToAvoidBottomInset: false, body: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<MethodCall> calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    // The handler goes in before anything touches the singleton: creating it
    // queries `getConstants`, and a miss there would make it fall back to
    // synthesizing frames from `viewInsets` for the whole run.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_methods, (MethodCall call) async {
      calls.add(call);
      if (call.method == 'getConstants') {
        return <Object?, Object?>{'keyboardBorderRadius': 30.0};
      }
      if (call.method == 'isInteractiveSupported') return true;
      if (call.method == 'setInteractive') return true;
      return null;
    });
    // `flutter_test` hands every test a new FocusManager and a new tree, so
    // the singleton has to be pointed at them again.
    KeyboardController.instance.resetForTesting();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_methods, null);
  });

  group('focused input', () {
    testWidgets('measures a plain TextField', (WidgetTester tester) async {
      final FocusNode node = FocusNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(
        _app(
          Center(
            child: SizedBox(
              width: 200,
              child: TextField(focusNode: node),
            ),
          ),
        ),
      );

      node.requestFocus();
      await _settle(tester);

      final FocusedInput? input =
          KeyboardController.instance.focusedInput.value;

      expect(input, isNotNull, reason: 'a focused TextField must be reported');
      expect(input!.target, identityHashCode(node));
      // The reported rect is the field's own box on screen.
      expect(input.layout.width, greaterThan(0));
      expect(input.layout.height, greaterThan(0));
      expect(input.layout.absoluteY, closeTo(node.rect.top, 0.01));
      expect(input.layout.absoluteX, closeTo(node.rect.left, 0.01));
    });

    testWidgets('reports caret geometry', (WidgetTester tester) async {
      final TextEditingController controller = TextEditingController();
      final FocusNode node = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(node.dispose);

      await tester.pumpWidget(
        _app(
          TextField(
            controller: controller,
            focusNode: node,
            maxLines: 5,
          ),
        ),
      );

      node.requestFocus();
      await _settle(tester);

      controller.value = const TextEditingValue(
        text: 'one\ntwo\nthree',
        selection: TextSelection.collapsed(offset: 13),
      );
      await _settle(tester);

      final FocusedInputSelection? selection =
          KeyboardController.instance.focusedInputSelection;

      expect(selection, isNotNull);
      expect(selection!.end.position, 13);
      expect(selection.start.position, 13);
      // The caret is on the third line, so its bottom is well below the top of
      // the field — this is the value that keeps a growing field in view.
      expect(selection.end.y, greaterThan(selection.start.y));
      expect(selection.end.y, greaterThan(20));
    });

    testWidgets('a field leaving the tree mid-measurement does not throw',
        (WidgetTester tester) async {
      // A caller-owned node outlives its field and keeps pointing at the dead
      // element — the case that crashed on device.
      final FocusNode node = FocusNode();
      final TextEditingController controller = TextEditingController();
      addTearDown(node.dispose);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _app(TextField(focusNode: node, controller: controller)),
      );
      node.requestFocus();
      await _settle(tester);

      // Schedules a post-frame measurement…
      controller.text = 'x';
      // …and the field is gone before it runs.
      await tester.pumpWidget(_app(const SizedBox()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(KeyboardController.instance.focusedInput.value, isNull);
    });

    testWidgets('walks between fields in reading order',
        (WidgetTester tester) async {
      final List<FocusNode> nodes =
          List<FocusNode>.generate(3, (int i) => FocusNode(debugLabel: '$i'));
      addTearDown(() {
        for (final FocusNode node in nodes) {
          node.dispose();
        }
      });

      await tester.pumpWidget(
        _app(
          Column(
            children: <Widget>[
              for (final FocusNode node in nodes) TextField(focusNode: node),
              // Not a text field: must be skipped by prev/next.
              TextButton(onPressed: () {}, child: const Text('submit')),
            ],
          ),
        ),
      );

      nodes[0].requestFocus();
      await _settle(tester);

      expect(KeyboardController.instance.focusPosition.value,
          (index: 0, count: 3));

      expect(KeyboardController.instance.setFocusTo(FocusDirection.next), true);
      await _settle(tester);
      expect(nodes[1].hasFocus, true);

      expect(KeyboardController.instance.setFocusTo(FocusDirection.next), true);
      await _settle(tester);
      expect(nodes[2].hasFocus, true);

      // Past the last field there is nowhere to go — the button is not one.
      expect(
        KeyboardController.instance.setFocusTo(FocusDirection.next),
        false,
      );

      expect(KeyboardController.instance.setFocusTo(FocusDirection.prev), true);
      await _settle(tester);
      expect(nodes[1].hasFocus, true);
    });
  });

  group('keyboard frames', () {
    testWidgets('reach handlers and metrics', (WidgetTester tester) async {
      final List<String> seen = <String>[];
      final VoidCallback remove = KeyboardController.instance.addHandler(
        KeyboardHandler(
          onStart: (KeyboardEvent e) => seen.add('start:${e.height}'),
          onMove: (KeyboardEvent e) => seen.add('move:${e.height}'),
          onEnd: (KeyboardEvent e) => seen.add('end:${e.height}'),
          onInteractive: (KeyboardEvent e) => seen.add('interactive:${e.height}'),
        ),
      );
      addTearDown(remove);

      await tester.pumpWidget(_app(const SizedBox()));
      await _showKeyboard(tester, 300);

      expect(seen, <String>['start:300.0', 'move:150.0', 'move:300.0', 'end:300.0']);
      expect(KeyboardController.instance.metrics.value.height, 300);
      expect(KeyboardController.instance.metrics.value.progress, 1);

      await _frame(KeyboardMessage.transitionInteractive, 120, 0.4, duration: -1);
      await tester.pump();

      expect(seen.last, 'interactive:120.0');
      expect(KeyboardController.instance.metrics.value.isInteractive, true);
    });

    testWidgets('onStart is a destination, never a position',
        (WidgetTester tester) async {
      await tester.pumpWidget(_app(const SizedBox()));

      await _frame(KeyboardMessage.transitionStart, 300, 1);
      await tester.pump();
      // The keyboard has not moved yet; metrics must not claim it has, or
      // everything built on them pops to the end of the transition.
      expect(KeyboardController.instance.metrics.value.height, 0);

      await _frame(KeyboardMessage.transitionMove, 120, 0.4);
      await tester.pump();
      expect(KeyboardController.instance.metrics.value.height, 120);
    });

    for (final KeyboardAvoidingBehavior behavior
        in KeyboardAvoidingBehavior.values) {
      testWidgets('KeyboardAvoidingView ${behavior.name} waits for the '
          'keyboard to move', (WidgetTester tester) async {
        await tester.pumpWidget(
          _app(
            KeyboardAvoidingView(
              behavior: behavior,
              child: Column(
                children: <Widget>[
                  const Spacer(),
                  Container(key: const Key('box'), height: 100),
                ],
              ),
            ),
          ),
        );
        await _settle(tester);
        double bottom() => tester.getBottomLeft(find.byKey(const Key('box'))).dy;
        final double atRest = bottom();

        await _frame(KeyboardMessage.transitionStart, 200, 1);
        await tester.pump();
        expect(bottom(), atRest, reason: 'no jump to the destination');

        await _frame(KeyboardMessage.transitionMove, 100, 0.5);
        await tester.pump();
        expect(atRest - bottom(), closeTo(100, 1), reason: 'halfway, halfway');
      });
    }

    testWidgets('KeyboardStickyView rides the keyboard',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          Align(
            alignment: Alignment.bottomCenter,
            child: KeyboardStickyView(
              offset: const KeyboardStickyOffset(opened: 10),
              child: const SizedBox(key: Key('bar'), height: 40, width: 100),
            ),
          ),
        ),
      );

      final double atRest = tester.getTopLeft(find.byKey(const Key('bar'))).dy;

      await _showKeyboard(tester, 300);

      final double raised = tester.getTopLeft(find.byKey(const Key('bar'))).dy;
      // Up by the keyboard height, plus the configured open offset.
      expect(atRest - raised, closeTo(300 - 10, 0.01));
    });

    testWidgets('KeyboardAvoidingView pads only by what is covered',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          KeyboardAvoidingView(
            child: Column(
              children: <Widget>[
                const Spacer(),
                Container(key: const Key('box'), height: 100, color: Colors.red),
              ],
            ),
          ),
        ),
      );

      final double atRest = tester.getTopLeft(find.byKey(const Key('box'))).dy;

      await _showKeyboard(tester, 200);

      final double padded = tester.getTopLeft(find.byKey(const Key('box'))).dy;
      expect(atRest - padded, closeTo(200, 1));
    });
  });

  group('KeyboardAvoidingView height', () {
    testWidgets('shrinks the view without remounting what is inside',
        (WidgetTester tester) async {
      final FocusNode node = FocusNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(
        _app(
          KeyboardAvoidingView(
            behavior: KeyboardAvoidingBehavior.height,
            child: Column(
              children: <Widget>[
                TextField(focusNode: node),
                const Spacer(),
                const SizedBox(key: Key('bottom'), height: 10),
              ],
            ),
          ),
        ),
      );
      node.requestFocus();
      await _settle(tester);

      final State field = tester.state(find.byType(EditableText));
      final double atRest =
          tester.getBottomLeft(find.byKey(const Key('bottom'))).dy;

      await _showKeyboard(tester, 200);

      expect(
        identical(tester.state(find.byType(EditableText)), field),
        isTrue,
        reason: 'the field must survive the keyboard opening',
      );
      expect(node.hasFocus, isTrue);
      // Inside a tight slot — a full-screen body — it still shrinks.
      expect(
        atRest - tester.getBottomLeft(find.byKey(const Key('bottom'))).dy,
        closeTo(200, 1),
      );

      await _frame(KeyboardMessage.transitionStart, 0, 0);
      await _frame(KeyboardMessage.transitionEnd, 0, 0);
      await _settle(tester);

      expect(identical(tester.state(find.byType(EditableText)), field), isTrue);
      expect(
        tester.getBottomLeft(find.byKey(const Key('bottom'))).dy,
        closeTo(atRest, 1),
        reason: 'and grows back once the keyboard is gone',
      );
    });
  });

  group('KeyboardAwareScrollView', () {
    testWidgets('scrolls the focused field clear of the keyboard',
        (WidgetTester tester) async {
      final ScrollController scrollController = ScrollController();
      final FocusNode last = FocusNode();
      addTearDown(scrollController.dispose);
      addTearDown(last.dispose);

      await tester.pumpWidget(
        _app(
          KeyboardAwareScrollView(
            controller: scrollController,
            bottomOffset: 16,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < 8; i++)
                  const SizedBox(height: 60, child: TextField()),
                SizedBox(height: 60, child: TextField(focusNode: last)),
              ],
            ),
          ),
        ),
      );

      // The last field is on screen but will be behind the keyboard.
      last.requestFocus();
      await _settle(tester);

      expect(scrollController.offset, 0);

      await _showKeyboard(tester, 300);
      await _settle(tester);

      expect(
        scrollController.offset,
        greaterThan(0),
        reason: 'the covered field must be scrolled into view',
      );
    });
  });

  group('imperative API', () {
    testWidgets('dismiss unfocuses; keepFocus keeps the caret',
        (WidgetTester tester) async {
      final FocusNode node = FocusNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(_app(TextField(focusNode: node)));
      node.requestFocus();
      await _settle(tester);
      await _showKeyboard(tester, 300);

      calls.clear();
      KeyboardController.instance.dismiss();
      await _settle(tester);

      expect(node.hasFocus, false);
      expect(
        calls.map((MethodCall it) => it.method),
        isNot(contains('dismiss')),
        reason: 'an animated unfocus needs no platform call',
      );

      node.requestFocus();
      await _settle(tester);
      calls.clear();

      KeyboardController.instance
          .dismiss(const DismissOptions(keepFocus: true));
      await _settle(tester);

      expect(node.hasFocus, true, reason: 'keepFocus must keep the caret');
    });

    testWidgets('setEnabled stops and resumes tracking',
        (WidgetTester tester) async {
      final List<double> seen = <double>[];
      final VoidCallback remove = KeyboardController.instance.addHandler(
        KeyboardHandler(onMove: (KeyboardEvent e) => seen.add(e.height)),
      );
      addTearDown(remove);

      await tester.pumpWidget(_app(const SizedBox()));

      await KeyboardController.instance.setEnabled(false);
      expect(KeyboardController.instance.enabled, false);
      expect(
        calls.map((MethodCall it) => it.method),
        contains('setEnabled'),
        reason: 'the native observers must be told to stop too',
      );

      await _frame(KeyboardMessage.transitionMove, 300, 1);
      await tester.pump();
      expect(seen, isEmpty, reason: 'nothing is dispatched while disabled');

      await KeyboardController.instance.setEnabled(true);
      await _frame(KeyboardMessage.transitionMove, 300, 1);
      await tester.pump();
      expect(seen, <double>[300]);
    });

    testWidgets('exposes platform constants', (WidgetTester tester) async {
      await tester.pumpWidget(_app(const SizedBox()));
      // `ready` is not awaited here: the singleton's start-up Future belongs
      // to whichever test first touched it, and a Future from another test's
      // fake-async zone never completes in this one. By now it has resolved.
      await _settle(tester);

      expect(KeyboardController.instance.hasNativeSupport, true);
      expect(KeyboardController.instance.keyboardBorderRadius, 30);
      expect(KeyboardController.instance.keyboardHasRoundedCorners, true);
    });
  });
}
