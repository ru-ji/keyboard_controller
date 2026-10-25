import 'package:flutter/material.dart';
import 'package:keyboard_controller/keyboard_controller.dart';

/// Compares the four [KeyboardAvoidingBehavior] values side by side.
class AvoidingViewPage extends StatefulWidget {
  const AvoidingViewPage({super.key});

  @override
  State<AvoidingViewPage> createState() => _AvoidingViewPageState();
}

class _AvoidingViewPageState extends State<AvoidingViewPage> {
  KeyboardAvoidingBehavior _behavior = KeyboardAvoidingBehavior.padding;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('KeyboardAvoidingView')),
        // Left to this package rather than to the Scaffold: the behaviours
        // below need the raw, un-inset layout to measure against.
        resizeToAvoidBottomInset: false,
        body: Column(
          children: <Widget>[
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final KeyboardAvoidingBehavior behavior
                    in KeyboardAvoidingBehavior.values)
                  ChoiceChip(
                    label: Text(behavior.name),
                    selected: _behavior == behavior,
                    onSelected: (_) => setState(() => _behavior = behavior),
                  ),
              ],
            ),
            Expanded(
              child: KeyboardAvoidingView(
                behavior: _behavior,
                keyboardVerticalOffset: 12,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    const Spacer(),
                    Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: <Widget>[
                          Text('behavior: ${_behavior.name}'),
                          const SizedBox(height: 12),
                          const TextField(
                            decoration: InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Stays above the keyboard',
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: KeyboardController.instance.dismiss,
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}
