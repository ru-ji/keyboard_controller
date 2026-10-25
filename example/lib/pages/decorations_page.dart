import 'package:flutter/material.dart';
import 'package:keyboard_controller/keyboard_controller.dart';

/// [KeyboardExtender], [KeyboardEffects] and [OverKeyboardView] together.
class DecorationsPage extends StatefulWidget {
  const DecorationsPage({super.key});

  @override
  State<DecorationsPage> createState() => _DecorationsPageState();
}

class _DecorationsPageState extends State<DecorationsPage> {
  final TextEditingController _amount = TextEditingController();
  bool _panelVisible = false;
  bool _effects = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Around the keyboard')),
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: <Widget>[
            ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                TextField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Amount',
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Translucent keyboard (iOS)'),
                  value: _effects,
                  onChanged: (bool value) => setState(() => _effects = value),
                ),
                FilledButton(
                  onPressed: () =>
                      setState(() => _panelVisible = !_panelVisible),
                  child: Text(
                    _panelVisible ? 'Hide panel' : 'Show panel over keyboard',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The panel appears without the keyboard closing.',
                ),
              ],
            ),

            if (_effects)
              KeyboardEffects(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.purple.shade400,
                        Colors.indigo.shade900,
                      ],
                    ),
                  ),
                ),
              ),

            // Quick-amount buttons that read as part of the keyboard.
            KeyboardExtender(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    for (final String amount in <String>['10', '20', '50'])
                      OutlinedButton(
                        onPressed: () => _amount.text = amount,
                        child: Text('$amount €'),
                      ),
                  ],
                ),
              ),
            ),

            OverKeyboardView(
              visible: _panelVisible,
              child: Align(
                alignment: Alignment.center,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text('Still focused, still typing.'),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () =>
                              setState(() => _panelVisible = false),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
