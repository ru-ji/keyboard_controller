import 'package:flutter/material.dart';
import 'package:keyboard_controller/keyboard_controller.dart';

/// A chat where the keyboard can be dragged away with a finger.
///
/// The composer is moved with [KeyboardStickyView], so it follows the finger
/// frame by frame rather than snapping when the gesture ends.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _composer = TextEditingController();
  final List<String> _messages = <String>[
    for (int i = 1; i <= 30; i++) 'Message $i',
  ];

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  void _send() {
    final String text = _composer.text.trim();
    if (text.isEmpty) return;
    setState(() => _messages.add(text));
    _composer.clear();
  }

  @override
  Widget build(BuildContext context) {
    // The raw home-indicator inset. `viewPaddingOf` stays put while the
    // keyboard moves, so this page is not rebuilt per frame — unlike
    // `SafeArea`, whose padding collapses the moment the keyboard opens and
    // would make the composer jump.
    final double bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      resizeToAvoidBottomInset: false,
      body: KeyboardGestureArea(
        // Slack above the keyboard so the drag starts a little early.
        offset: 20,
        // One avoiding view around list *and* composer: the composer stays in
        // normal layout, so the list ends exactly where it begins. Avoiding
        // the keyboard separately in each — a padded list plus a composer
        // translated by the full keyboard height — slides the composer over
        // the last messages, since a transform takes no layout space.
        child: KeyboardAvoidingView(
          // The home-indicator strip ends up behind the keyboard, so the
          // composer can sit right on top of it instead of floating above.
          keyboardVerticalOffset: -bottomInset,
          child: Column(
            children: <Widget>[
              Expanded(
                child: ListView(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    for (final String message in _messages.reversed)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(message),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                key: const Key('composer'),
                padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + bottomInset),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _composer,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Drag the keyboard down to dismiss',
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
