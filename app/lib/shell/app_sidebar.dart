import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';
import '../widgets/motion.dart';
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
    this.onOpenDisplay,
  });

  final AuthService auth;
  final List<SidebarItem> items;
  final int selectedIndex;

  /// Null disables navigation (e.g. an officer with no data imported yet).
  final ValueChanged<int>? onSelected;

  /// Optional button under the logo (e.g. the officer's "Import data").
  final Widget? action;

  /// Shows an "Open display screen" button (admin only).
  final VoidCallback? onOpenDisplay;

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
          const SizedBox(height: 24),
          for (final (i, item) in items.indexed)
            _NavButton(
              item: item,
              selected: i == selectedIndex,
              onTap: onSelected == null ? null : () => onSelected!(i),
            ),
          const Spacer(),
          if (onOpenDisplay != null)
            _FooterButton(
              icon: Icons.tv_rounded,
              tooltip: 'Open the display screen (what students see). Unlock it with an admin password.',
              onPressed: onOpenDisplay!,
            ),
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
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: HoverBuilder(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        builder: (context, hovered) {
          final color = selected
              ? EcoColors.forest
              : !enabled
                  ? EcoColors.line
                  : hovered
                      ? EcoColors.ink
                      : EcoColors.muted;
          return GestureDetector(
            onTap: onTap,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              // Accent bar on the left edge of the selected item.
              AnimatedContainer(
                duration: Motion.medium,
                curve: Motion.curve,
                width: 4,
                height: selected ? 28 : 0,
                decoration: BoxDecoration(
                  color: EcoColors.emerald,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedContainer(
                duration: Motion.fast,
                width: 68,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? EcoColors.mint
                      : hovered && enabled
                          ? EcoColors.field
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  AnimatedScale(
                    scale: hovered && enabled && !selected ? 1.1 : 1,
                    duration: Motion.fast,
                    child: Icon(item.icon, color: color, size: 23),
                  ),
                  const SizedBox(height: 4),
                  AnimatedDefaultTextStyle(
                    duration: Motion.fast,
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 11,
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    child: Text(item.label),
                  ),
                ]),
              ),
              const SizedBox(width: 9), // 4 + 6 + 68 + 9 = the sidebar's 87 px inside its border
            ]),
          );
        },
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
