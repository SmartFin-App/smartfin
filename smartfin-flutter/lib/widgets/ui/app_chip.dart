import 'package:flutter/material.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/constants/text_style.dart';

/// A pill that can be selected: filter options, suggestions. Selected chips
/// take a soft orange fill with dark-orange text rather than a heavy border.
class AppChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  const AppChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.primaryText : AppColors.textDark;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.14)
            : AppColors.white,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(label, style: AppTextStyles.label.copyWith(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
