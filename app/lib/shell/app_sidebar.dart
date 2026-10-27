import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';
import 'window_controls.dart';

class SidebarItem {
  const SidebarItem(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// Slim white sidebar: logo on top, icon navigation, account controls at the bottom.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.auth,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.action,
  });

  final AuthService auth;
  final List<SidebarItem> items;
  final int selectedIndex;

  /// Null disables navigation (e.g. an officer with no data imported yet).
  final ValueChanged<int>? onSelected;

  /// Optional button under the logo (e.g. the officer's "Import data").
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final account = auth.current;
    return Container(
      width: 88,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: EcoColors.line)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          const EcoLogo(size: 40),
          if (action != null) ...[const SizedBox(height: 20), action!],
          const SizedBox(height: 36),
          for (final (i, item) in items.indexed)
            _NavButton(
              item: item,
              selected: i == selectedIndex,
              onTap: onSelected == null ? null : () => onSelected!(i),
            ),
          const Spacer(),
          const _FooterButton(icon: Icons.fullscreen, tooltip: 'Full screen on/off (F11)', onPressed: toggleFullScreen),
          _FooterButton(icon: Icons.power_settings_new, tooltip: 'Quit EcoEarn', onPressed: () => confirmQuit(context)),
          _FooterButton(icon: Icons.logout, tooltip: 'Sign out', onPressed: auth.logout),
          const SizedBox(height: 12),
          Tooltip(
            message: '${account?.displayName ?? ''} · ${account?.role.label ?? ''}',
            child: InitialsAvatar(name: account?.displayName ?? '?', size: 40, color: EcoColors.teal),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});

  final SidebarItem item;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? EcoColors.emerald : (onTap == null ? EcoColors.line : EcoColors.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(children: [
              Icon(item.icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: EcoColors.muted, size: 22),
      );
}
