import 'package:flutter/material.dart';
import 'package:keyboard_controller/keyboard_controller.dart';

/// A long form: every field — and the caret inside the multiline one — stays
/// above the keyboard, and the toolbar walks between them.
class AwareScrollViewPage extends StatefulWidget {
  const AwareScrollViewPage({super.key});

  @override
  State<AwareScrollViewPage> createState() => _AwareScrollViewPageState();
}

class _AwareScrollViewPageState extends State<AwareScrollViewPage> {
  static const List<String> _labels = <String>[
    'Full name',
    'Email',
    'Phone',
    'Street',
    'City',
    'Post code',
    'Country',
    'Notes',
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('KeyboardAwareScrollView')),
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: <Widget>[
            KeyboardAwareScrollView(
              // Room between the caret and the toolbar sitting on the keyboard.
              bottomOffset: KeyboardToolbar.height + 12,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  for (final String label in _labels)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextField(
                        maxLines: label == 'Notes' ? 6 : 1,
                        keyboardType: switch (label) {
                          'Email' => TextInputType.emailAddress,
                          'Phone' => TextInputType.phone,
                          'Notes' => TextInputType.multiline,
                          _ => TextInputType.text,
                        },
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: label,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: () {},
                    child: const Text('Submit'),
                  ),
                ],
              ),
            ),
            const KeyboardToolbar(),
          ],
        ),
      );
}
