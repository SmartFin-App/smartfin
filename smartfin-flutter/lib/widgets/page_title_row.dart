import 'package:flutter/material.dart';
import 'package:smart_fin/constants/text_style.dart';

/// The title line at the top of every tab screen (History, AI Coach, Profile),
/// so titles sit in the same place with the same type on each. Left-aligned to
/// match the SmartFin logo on the dashboard, with an optional 40px action on
/// the right. Callers supply the blurred header bar and its 24px side and 48px
/// top insets.
class PageTitleRow extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const PageTitleRow({super.key, required this.title, this.trailing});

  /// The height to give a pinned `SliverAppBar` whose header content ends
  /// [contentBottom] points from the top of the screen. The app bar adds the
  /// status-bar inset on top of its own height, while the header content sits
  /// at a fixed 48 from the top, so a fixed height left a band of empty space
  /// under the title on phones with a tall inset (about 60pt on an iPhone).
  static double barHeight(BuildContext context, double contentBottom) {
    final inset = MediaQuery.paddingOf(context).top;
    return (contentBottom - inset).clamp(0.0, contentBottom);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.title,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
