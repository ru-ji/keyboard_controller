import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyboard_controller/keyboard_controller.dart';
import 'package:keyboard_controller_example/pages/chat_page.dart';

const MethodChannel _methods = MethodChannel('keyboard_controller');

// Message codes of the native keyboard channel.
const int _start = 0;
const int _move = 1;
const int _end = 2;

Future<void> _frame(int kind, double height) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'keyboard_controller/messages',
    const StandardMessageCodec()
        .encodeMessage(<Object?>[kind, height, height / 300, 250]),
    (_) {},
  );
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

  testWidgets('messages never go behind the composer, and the composer '
      'never goes behind the keyboard', (WidgetTester tester) async {
    // An iPhone with a home indicator, like the device in the bug report.
    const double homeIndicator = 34;
    final double dpr = tester.view.devicePixelRatio;
    tester.view.viewPadding = FakeViewPadding(bottom: homeIndicator * dpr);
    tester.view.padding = FakeViewPadding(bottom: homeIndicator * dpr);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);

    await tester.pumpWidget(const MaterialApp(home: ChatPage()));
    final double screen = tester.view.physicalSize.height / dpr;

    Rect composer() => tester.getRect(find.byKey(const Key('composer')));
    Rect field() => tester.getRect(find.byType(TextField));
    Rect list() => tester.getRect(find.byType(ListView));

    expect(composer().bottom, screen, reason: 'at rest, on the screen edge');

    await tester.tap(find.byType(TextField));
    await tester.pump();

    for (final (int kind, double keyboard) in <(int, double)>[
      (_start, 300),
      (_move, 75),
      (_move, 150),
      (_move, 225),
      (_move, 300),
      (_end, 300),
    ]) {
      await _frame(kind, keyboard);
      await tester.pump();

      // `start` is the destination; the keyboard is still down there.
      final double keyboardTop = screen - (kind == _start ? 0 : keyboard);

      expect(
        list().bottom,
        lessThanOrEqualTo(composer().top),
        reason: 'the list must end where the composer begins',
      );
      expect(
        field().bottom,
        lessThanOrEqualTo(keyboardTop),
        reason: 'the field must clear a keyboard $keyboard tall',
      );
    }

    // Fully open: the home-indicator strip is behind the keyboard, so the
    // field sits on it with just the composer's own 8 of padding.
    expect(field().bottom, closeTo(screen - 300 - 8, 1));
    expect(
      tester.getRect(find.text('Message 30')).bottom,
      lessThanOrEqualTo(composer().top),
      reason: 'the newest message stays in view',
    );
  });
}
