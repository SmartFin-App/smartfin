import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/constants/text_style.dart';
import 'package:smart_fin/widgets/ui/app_icon_button.dart';

/// The blurred header of a pushed screen: a back button, a centred title and
/// an optional action on the right. Place it at the top of a `Stack` over the
/// scrolling content, which should start [contentTop] from the top.
class SubpageHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final Widget? trailing;

  const SubpageHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.trailing,
  });

  /// Where content below the header should begin: the header row sits 48 from
  /// the top, is 40 tall, and has 8 below it, plus room to breathe.
  static const double contentTop = 112;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: AppColors.cream.withValues(alpha: 0.85),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              48,
              AppSpacing.screen,
              AppSpacing.sm,
            ),
            child: SizedBox(
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Centred on the screen whatever the actions' widths; the
                  // inset keeps it clear of up to two 40px buttons a side.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 96),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.heading,
                    ),
                  ),
                  Row(
                    children: [
                      AppIconButton(
                        icon: Icons.arrow_back_rounded,
                        semanticLabel: 'Back',
                        onPressed: onBack,
                      ),
                      const Spacer(),
                      ?trailing,
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
