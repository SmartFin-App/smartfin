import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/widgets/action_hub_sheet.dart';

class SmartFinBottomNav extends StatelessWidget {
  final int currentIndex;
  final bool showFab;

  const SmartFinBottomNav({
    super.key,
    required this.currentIndex,
    this.showFab = true,
  });

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
    required String label,
    required bool isActive,
  }) {
    final color = isActive ? const Color(0xFFFF9F29) : const Color.fromRGBO(158, 158, 158, 0.6);
    
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onTap(context, index),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 8,
                letterSpacing: 0.5,
                color: color,
              ),
            ),
          ],
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
            // Main Glass Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.92,
                  constraints: const BoxConstraints(maxWidth: 448),
                  height: 64, // Approximate height to fit icons+text comfortably
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(255, 255, 255, 0.95),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.6)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildNavItem(
                        context: context,
                        index: 0,
                        icon: Icons.home,
                        label: 'HOME',
                        isActive: currentIndex == 0,
                      ),
                      _buildNavItem(
                        context: context,
                        index: 1,
                        icon: Icons.history,
                        label: 'HISTORY',
                        isActive: currentIndex == 1,
                      ),
                      
                      // Center space for FAB
                      const SizedBox(width: 80), 
                      
                      _buildNavItem(
                        context: context,
                        index: 2,
                        icon: Icons.chat_bubble_outline,
                        label: 'COACH',
                        isActive: currentIndex == 2,
                      ),
                      _buildNavItem(
                        context: context,
                        index: 3,
                        icon: Icons.person_outline,
                        label: 'PROFILE',
                        isActive: currentIndex == 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Floating Action Button
            if (showFab)
              Positioned(
              top: -24, // Elevating it above the bar
              child: GestureDetector(
                onTap: () => ActionHubSheet.show(context),
                child: Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9F29),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF9F29).withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.add, color: Color(0xFFFF9F29), size: 18),
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
