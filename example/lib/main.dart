import 'package:flutter/material.dart';
import 'package:keyboard_controller/keyboard_controller.dart';

import 'pages/avoiding_view_page.dart';
import 'pages/aware_scroll_view_page.dart';
import 'pages/chat_page.dart';
import 'pages/decorations_page.dart';
import 'pages/metrics_page.dart';
import 'pages/search_panel_page.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'keyboard_controller',
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: const HomePage(),
      );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('keyboard_controller')),
        body: ListView(
          children: <Widget>[
            const _SupportBanner(),
            _Entry(
              title: 'Search panel',
              subtitle: 'bar grows into a panel that rides the keyboard',
              page: SearchPanelPage(),
            ),
            _Entry(
              title: 'Keyboard metrics',
              subtitle: 'height, progress and events, frame by frame',
              page: MetricsPage(),
            ),
            _Entry(
              title: 'KeyboardAvoidingView',
              subtitle: 'padding, height, position, translate-with-padding',
              page: AvoidingViewPage(),
            ),
            _Entry(
              title: 'KeyboardAwareScrollView',
              subtitle: 'a long form with a toolbar, caret kept in view',
              page: AwareScrollViewPage(),
            ),
            _Entry(
              title: 'Chat + interactive dismiss',
              subtitle: 'drag the keyboard away with a finger',
              page: ChatPage(),
            ),
            _Entry(
              title: 'Around the keyboard',
              subtitle: 'extender, effects and over-keyboard content',
              page: DecorationsPage(),
            ),
          ],
        ),
      );
}

class _SupportBanner extends StatefulWidget {
  const _SupportBanner();

  @override
  State<_SupportBanner> createState() => _SupportBannerState();
}

class _SupportBannerState extends State<_SupportBanner> {
  String _status = 'checking…';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final KeyboardController keyboard = KeyboardController.instance;
    await keyboard.ready;
    final bool interactive = await keyboard.isInteractiveKeyboardSupported();
    if (!mounted) return;
    setState(() {
      _status = keyboard.hasNativeSupport
          ? 'native tracking on · interactive drag '
              '${interactive ? 'supported' : 'unsupported'} · '
              'keyboard radius ${keyboard.keyboardBorderRadius.toInt()}'
          : 'no native plugin — frames synthesized from viewInsets';
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _status,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.title,
    required this.subtitle,
    required this.page,
  });

  final String title;
  final String subtitle;
  final Widget page;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => page),
        ),
      );
}
