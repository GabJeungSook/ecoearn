import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../auth/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';

Future<void> toggleFullScreen() async =>
    windowManager.setFullScreen(!await windowManager.isFullScreen());

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

/// Bottom of the sidebar: fullscreen toggle, who is signed in, and sign out.
class RailFooter extends StatelessWidget {
  const RailFooter({super.key, required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    final account = auth.current;
    const faded = Color(0xB3FFFFFF);
    return Expanded(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const IconButton(
                tooltip: 'Full screen (F11)',
                onPressed: toggleFullScreen,
                icon: Icon(Icons.fullscreen, color: faded),
              ),
              const SizedBox(height: 12),
              InitialsAvatar(name: account?.displayName ?? '?', size: 38, color: EcoColors.teal),
              const SizedBox(height: 6),
              SizedBox(
                width: 80,
                child: Text(
                  account?.displayName ?? '',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              Text(account?.role.label ?? '', style: const TextStyle(color: faded, fontSize: 11)),
              IconButton(
                tooltip: 'Sign out',
                onPressed: auth.logout,
                icon: const Icon(Icons.logout, color: faded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
