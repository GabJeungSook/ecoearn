import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';
import 'rail_footer.dart';

/// Dark green navigation sidebar with the logo on top and the account at the bottom.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.auth,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.action,
  });

  final AuthService auth;
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;
  final List<NavigationRailDestination> destinations;

  /// Optional button under the logo (e.g. the officer's "Import data").
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(gradient: EcoColors.heroGradient),
        child: NavigationRail(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          labelType: NavigationRailLabelType.all,
          groupAlignment: -0.6,
          leading: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 20),
            child: Column(children: [
              const EcoLogo(size: 44),
              const SizedBox(height: 6),
              const Text('EcoEarn', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ]),
          ),
          destinations: destinations,
          trailing: RailFooter(auth: auth),
        ),
      );
}
