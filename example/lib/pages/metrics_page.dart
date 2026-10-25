import 'package:flutter/material.dart';
import 'package:keyboard_controller/keyboard_controller.dart';

/// Shows every value the keyboard reports, live.
class MetricsPage extends StatefulWidget {
  const MetricsPage({super.key});

  @override
  State<MetricsPage> createState() => _MetricsPageState();
}

class _MetricsPageState extends State<MetricsPage> {
  final List<String> _log = <String>[];
  VoidCallback? _remove;

  @override
  void initState() {
    super.initState();
    _remove = KeyboardController.instance.addHandler(
      KeyboardHandler(
        onStart: (KeyboardEvent e) => _add('onStart  → ${e.height.toInt()}px '
            '(${e.duration}ms)'),
        onEnd: (KeyboardEvent e) => _add('onEnd    → ${e.height.toInt()}px'),
      ),
    );
  }

  @override
  void dispose() {
    _remove?.call();
    super.dispose();
  }

  void _add(String line) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, line);
      if (_log.length > 12) _log.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Keyboard metrics')),
        body: Column(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Focus me, then dismiss',
                ),
              ),
            ),
            // Rebuilds every frame of the transition, so the bar tracks the
            // keyboard exactly rather than approximating it.
            KeyboardAnimationBuilder(
              builder: (BuildContext context, KeyboardEvent keyboard, _) =>
                  Column(
                children: <Widget>[
                  LinearProgressIndicator(value: keyboard.progress.clamp(0, 1)),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'height ${keyboard.height.toStringAsFixed(1)}  ·  '
                      'progress ${keyboard.progress.toStringAsFixed(3)}  ·  '
                      '${keyboard.isInteractive ? 'interactive' : '${keyboard.duration}ms'}',
                    ),
                  ),
                ],
              ),
            ),
            KeyboardStateBuilder<KeyboardState>(
              selector: (KeyboardState state) => state,
              builder: (BuildContext context, KeyboardState state, _) => Text(
                'visible ${state.isVisible} · ${state.appearance.name} · '
                'type ${state.type.toJson()['name']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: <Widget>[
                  for (final String line in _log)
                    Text(line, style: const TextStyle(fontFamily: 'monospace')),
                ],
              ),
            ),
            // Sticks to the keyboard: it rides up with it and sits just above.
            KeyboardStickyView(
              offset: const KeyboardStickyOffset(opened: -8),
              child: Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.primaryContainer,
                padding: const EdgeInsets.all(16),
                child: const Text('KeyboardStickyView'),
              ),
            ),
          ],
        ),
      );
}
