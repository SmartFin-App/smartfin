import 'package:flutter/material.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/constants/text_style.dart';

/// An icon, a short title and a line of help, centred — for empty lists and
/// failed loads. Plain copy: no paw or cat imagery outside the AI Coach.
class StatusMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;

  /// Optional button under the message, such as "Try again" or "Add expense".
  final Widget? action;

  const StatusMessage({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xl,
        horizontal: AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: AppColors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 24, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyStrong,
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(height: 1.4),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.lg),
            action!,
          ],
        ],
      ),
    );
  }
}
