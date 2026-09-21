import 'package:flutter/material.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/constants/text_style.dart';

/// One row of a list: leading mark, a title with an optional line under it,
/// and something on the right (usually an amount). Rows inside a card are
/// separated with [ListRow.divider].
class ListRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Tints the title, e.g. red for a destructive row such as Log out.
  final Color? titleColor;

  const ListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
  });

  /// A hairline between rows, indented to start under the title rather than
  /// under the leading mark.
  static Widget divider({double indent = 68}) =>
      Divider(height: 1, indent: indent, endIndent: AppSpacing.lg);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleColor == null
                        ? AppTextStyles.bodyStrong
                        : AppTextStyles.bodyStrong.copyWith(color: titleColor),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.md),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
