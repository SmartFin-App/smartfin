import 'package:flutter/material.dart';
import 'package:smart_fin/constants/color_style.dart';

/// A 40px icon button for screen headers, on a white rounded square. [active]
/// tints it orange; a [badge] above zero shows a count in the corner, e.g. how
/// many filters are on.
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final bool active;
  final int badge;

  /// A solid orange button, for the screen's main action (e.g. add).
  final bool filled;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.active = false,
    this.badge = 0,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color fill;
    final Color edge;
    final Color fg;
    if (filled) {
      fill = AppColors.primary;
      edge = AppColors.primary;
      fg = AppColors.onPrimary;
    } else if (active) {
      fill = AppColors.primary.withValues(alpha: 0.14);
      edge = AppColors.primary.withValues(alpha: 0.5);
      fg = AppColors.primaryText;
    } else {
      fill = AppColors.white;
      edge = AppColors.border;
      fg = AppColors.textDark;
    }

    final button = Material(
      color: fill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: edge),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: 22,
            color: fg,
            semanticLabel: badge > 0
                ? '$semanticLabel, $badge on'
                : semanticLabel,
          ),
        ),
      ),
    );
    if (badge <= 0) return button;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          top: -5,
          right: -5,
          child: ExcludeSemantics(
            child: Container(
              constraints: const BoxConstraints(minWidth: 20),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: AppColors.cream, width: 2),
              ),
              child: Text(
                '$badge',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  height: 1,
                  color: AppColors.onPrimary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
