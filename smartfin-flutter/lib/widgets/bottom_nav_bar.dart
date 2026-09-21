import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/widgets/action_hub_sheet.dart';

class SmartFinBottomNav extends StatelessWidget {
  final int currentIndex;

  const SmartFinBottomNav({super.key, required this.currentIndex});

  void _onTap(BuildContext context, int index) {
    if (index == currentIndex) return;

    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/history');
        break;
      case 2:
        context.go('/coach');
        break;
      case 3:
        context.go('/profile');
        break;
    }
  }

  Widget _buildNavItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isActive,
  }) {
    // Icons only on screen; the label is still read out by screen readers.
    // The active tab gets the filled icon on a soft orange pill.
    return Expanded(
      child: Semantics(
        label: label,
        button: true,
        selected: isActive,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onTap(context, index),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 52,
              height: 36,
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.primary.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Icon(
                isActive ? activeIcon : icon,
                size: 24,
                color: isActive ? AppColors.primaryText : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Add sits inside the bar on every tab. It used to float 24px above the
  /// bar, where it covered the coach's chat input, so Coach and Profile hid it
  /// and left an empty gap. It stays a filled square rather than a labelled
  /// tab because it opens the action hub; it is never the current page.
  Widget _buildAddButton(BuildContext context) {
    return Expanded(
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadius.md),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => ActionHubSheet.show(context),
              child: const SizedBox(
                width: 48,
                height: 44,
                child: Icon(
                  Icons.add_rounded,
                  color: AppColors.onPrimary,
                  size: 26,
                  semanticLabel: 'Add',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 32,
      left: 0,
      right: 0,
      child: Container(
        alignment: Alignment.center,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Main glass bar. The shadow sits outside the clip, which would
            // otherwise cut it off.
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                boxShadow: AppShadows.card,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.92,
                    constraints: const BoxConstraints(maxWidth: 448),
                    height: 64,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      border: Border.all(
                        color: AppColors.border.withValues(alpha: 0.7),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildNavItem(
                          context: context,
                          index: 0,
                          icon: Icons.home_outlined,
                          activeIcon: Icons.home_rounded,
                          label: 'Home',
                          isActive: currentIndex == 0,
                        ),
                        _buildNavItem(
                          context: context,
                          index: 1,
                          icon: Icons.receipt_long_outlined,
                          activeIcon: Icons.receipt_long_rounded,
                          label: 'History',
                          isActive: currentIndex == 1,
                        ),

                        _buildAddButton(context),

                        _buildNavItem(
                          context: context,
                          index: 2,
                          icon: Icons.chat_bubble_outline_rounded,
                          activeIcon: Icons.chat_bubble_rounded,
                          label: 'AI Coach',
                          isActive: currentIndex == 2,
                        ),
                        _buildNavItem(
                          context: context,
                          index: 3,
                          icon: Icons.person_outline_rounded,
                          activeIcon: Icons.person_rounded,
                          label: 'Profile',
                          isActive: currentIndex == 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
