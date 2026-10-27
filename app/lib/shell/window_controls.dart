import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

Future<void> toggleFullScreen() async =>
    windowManager.setFullScreen(!await windowManager.isFullScreen());

/// The app runs fullscreen with no title bar, so this is how it gets closed.
Future<void> confirmQuit(BuildContext context) async {
  final quit = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Quit EcoEarn?'),
      content: const Text('Bottles deposited while EcoEarn is closed will not be recorded '
          'or earn points (the machine has no SD card to save them).'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Quit')),
      ],
    ),
  );
  if (quit == true) await windowManager.close();
}

/// Lets F11 toggle fullscreen anywhere inside [child].
class FullScreenShortcut extends StatelessWidget {
  const FullScreenShortcut({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.f11): toggleFullScreen},
        child: Focus(autofocus: true, child: child),
      );
}
