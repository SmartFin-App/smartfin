import 'package:flutter/material.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/constants/text_style.dart';

/// A heading above a block of content, with an optional link on the right
/// ("See all"). Sentence case, not letter-spaced capitals.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(child: Text(title, style: AppTextStyles.heading)),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: const Size(48, 40),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}
