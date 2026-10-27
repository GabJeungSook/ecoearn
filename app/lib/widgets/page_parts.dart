import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Screen heading: a small uppercase label above a large title, actions on the right.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.overline, required this.title, this.actions = const []});

  final String overline;
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  overline.toUpperCase(),
                  style: const TextStyle(fontSize: 11, letterSpacing: 1.2, color: EcoColors.muted, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: EcoColors.ink)),
              ]),
            ),
            for (final action in actions) Padding(padding: const EdgeInsets.only(left: 8), child: action),
          ],
        ),
      );
}

/// Small square icon button. [primary] makes it the solid accent "main action".
class SquareIconButton extends StatelessWidget {
  const SquareIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: primary ? EcoColors.emerald : EcoColors.field,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: 40,
              child: Icon(icon, size: 20, color: primary ? Colors.white : EcoColors.ink),
            ),
          ),
        ),
      );
}

/// A list row drawn as its own rounded white card. The selected row is
/// filled with the accent color and its text and icons turn white.
class RowCard extends StatelessWidget {
  const RowCard({super.key, required this.child, this.selected = false, this.onTap});

  final Widget child;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : EcoColors.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? EcoColors.emerald : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: selected ? BorderSide.none : const BorderSide(color: EcoColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: foreground, fontSize: 14),
              child: IconTheme.merge(data: IconThemeData(color: foreground, size: 20), child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Column captions above a list of [RowCard]s. [flex] must match the rows.
class ColumnHeadings extends StatelessWidget {
  const ColumnHeadings({super.key, required this.labels, required this.flex, this.trailingWidth = 0});

  final List<String> labels;
  final List<int> flex;

  /// Space reserved at the end for row action buttons.
  final double trailingWidth;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              flex: flex[i],
              child: Text(labels[i], style: const TextStyle(fontSize: 12, color: EcoColors.muted)),
            ),
          SizedBox(width: trailingWidth),
        ]),
      );
}

/// Centered message for an empty list.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: EcoColors.muted),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: EcoColors.muted)),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      );
}
