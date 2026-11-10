import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'motion.dart';

/// Screen heading: a small uppercase label above a large title, actions on the right.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.overline, required this.title, this.actions = const []});

  final String overline;
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => FadeSlideIn(
        offset: const Offset(0, 10),
        child: Padding(
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
                  Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: EcoColors.ink)),
                ]),
              ),
              for (final action in actions) Padding(padding: const EdgeInsets.only(left: 8), child: action),
            ],
          ),
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
        child: HoverBuilder(
          cursor: onPressed == null ? MouseCursor.defer : SystemMouseCursors.click,
          builder: (context, hovered) {
            final active = hovered && onPressed != null;
            return AnimatedContainer(
              duration: Motion.fast,
              decoration: BoxDecoration(
                color: primary
                    ? (active ? EcoColors.forest : EcoColors.emerald)
                    : (active ? EcoColors.line : EcoColors.field),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Material(
                type: MaterialType.transparency,
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
          },
        ),
      );
}

/// A list row drawn as its own rounded white card. It fades in when it first
/// appears and lifts its border on hover. The selected row is filled with the
/// accent color and its text and icons turn white.
class RowCard extends StatelessWidget {
  const RowCard({super.key, required this.child, this.selected = false, this.onTap});

  final Widget child;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : EcoColors.ink;
    return FadeSlideIn(
      duration: Motion.medium,
      offset: const Offset(0, 8),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: HoverBuilder(
          cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
          builder: (context, hovered) => AnimatedContainer(
            duration: Motion.fast,
            decoration: BoxDecoration(
              color: selected ? EcoColors.emerald : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? EcoColors.emerald
                    : hovered
                        ? EcoColors.emerald.withValues(alpha: 0.45)
                        : EcoColors.line,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
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
          Container(
            width: 84,
            height: 84,
            decoration: const BoxDecoration(color: EcoColors.mint, shape: BoxShape.circle),
            child: Icon(icon, size: 38, color: EcoColors.emerald),
          ),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: EcoColors.muted, fontSize: 15)),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      );
}

/// A form field with its label above it (and an optional hint below), with
/// even spacing between fields.
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child, this.required = false, this.helper});

  final String label;
  final Widget child;
  final bool required;
  final String? helper;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text.rich(
            TextSpan(text: label, children: [
              if (required) const TextSpan(text: ' *', style: TextStyle(color: EcoColors.coral)),
            ]),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          child,
          if (helper != null) ...[
            const SizedBox(height: 6),
            Text(helper!, style: const TextStyle(fontSize: 12, color: EcoColors.muted)),
          ],
        ]),
      );
}
