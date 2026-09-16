import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smart_fin/features/scanner/services/gallery_watcher_service.dart';
import 'package:smart_fin/features/scanner/presentation/widgets/slip_detection_sheet.dart';
import 'package:smart_fin/features/scanner/presentation/widgets/slip_folders_sheet.dart';

class ActionHubSheet extends StatelessWidget {
  const ActionHubSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.2),
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: const ActionHubSheet(),
      ),
    );
  }

  Widget _buildActionRow({
    required BuildContext context,
    required Color bgColor,
    required Color borderColor,
    required Color iconBgColor,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    List<BoxShadow>? iconShadow,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: iconShadow,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter( // Fallback to Inter for Geist
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: const Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w500,
                      fontSize: 10,
                      color: const Color.fromRGBO(51, 51, 51, 0.6),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color.fromRGBO(51, 51, 51, 0.3), size: 20),
          ],
        ),
      ),
    );
  }

  String _slipCheckMessage(SlipCheckStatus status) {
    switch (status) {
      case SlipCheckStatus.permissionDenied:
        return "SmartFin needs photo access to spot your payment slips. Enable it in Settings.";
      case SlipCheckStatus.disabled:
        return "Auto-Detect is turned off. You can switch it back on in your profile.";
      case SlipCheckStatus.noAlbum:
        // Most people keep slips in their banking app's own folder rather than
        // making one for us, so point at the picker instead of asking them to
        // reorganise their gallery.
        return "We couldn't find your slip folder. Pick the one your bank saves slips to. 🐾";
      case SlipCheckStatus.none:
      case SlipCheckStatus.found:
        return "No new slips found. You're all caught up! 🐾";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(40),
          topRight: Radius.circular(40),
        ),
        border: Border(top: BorderSide(color: Color.fromRGBO(234, 226, 214, 0.4))),
      ),
      padding: const EdgeInsets.only(top: 32, left: 32, right: 32, bottom: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Container(
            width: 48,
            height: 6,
            margin: const EdgeInsets.only(bottom: 40),
            decoration: BoxDecoration(
              color: const Color(0xFFF0EBE1),
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
          
          // Title
          Text(
            "Add Transaction",
            style: GoogleFonts.bricolageGrotesque(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: const Color(0xFF333333),
            ),
          ),
          
          const SizedBox(height: 40),
          
          // Row 1 - Scan Receipt
          _buildActionRow(
            context: context,
            bgColor: const Color.fromRGBO(255, 159, 41, 0.05),
            borderColor: const Color.fromRGBO(255, 159, 41, 0.1),
            iconBgColor: const Color(0xFFFF9F29),
            icon: Icons.document_scanner,
            iconColor: Colors.white,
            iconShadow: [
              BoxShadow(
                color: const Color.fromRGBO(255, 159, 41, 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
            title: "Scan Receipt",
            subtitle: "AI-powered extraction",
            onTap: () {
              Navigator.pop(context);
              context.go('/scanner');
            },
          ),

          const SizedBox(height: 12),

          // Row 1.5 - Auto-Detect (backed by GalleryWatcherService)
          _buildActionRow(
            context: context,
            bgColor: const Color.fromRGBO(74, 144, 226, 0.05),
            borderColor: const Color.fromRGBO(74, 144, 226, 0.15),
            iconBgColor: const Color(0xFF4A90E2),
            icon: Icons.photo_album_outlined,
            iconColor: Colors.white,
            iconShadow: [
              BoxShadow(
                color: const Color.fromRGBO(74, 144, 226, 0.25),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
            title: "Auto-Detect",
            subtitle: "Find new PromptPay slips",
            onTap: () async {
              // Capture the ancestors before popping: this sheet's own context is
              // deactivated by the pop, so anything guarded on context.mounted
              // afterwards silently never runs.
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final rootContext = navigator.context;

              final result =
                  await GalleryWatcherService().checkForNewSlipsDetailed();
              navigator.pop();

              if (result.slip != null) {
                SlipDetectionSheet.show(rootContext, result.slip!);
              } else {
                // A tap on Auto-Detect is an explicit request, so the picker is
                // offered every time no folder matched — this is the only way
                // back for anyone who dismissed the dashboard's one-time offer.
                final offerPicker = result.status == SlipCheckStatus.noAlbum;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(_slipCheckMessage(result.status)),
                    duration: Duration(seconds: offerPicker ? 8 : 3),
                    action: offerPicker
                        ? SnackBarAction(
                            label: 'Pick',
                            onPressed: () => SlipFoldersSheet.show(rootContext),
                          )
                        : null,
                  ),
                );
              }
            },
          ),
          
          const SizedBox(height: 12),

          // Row 2 - Manual Expense
          _buildActionRow(
            context: context,
            bgColor: Colors.white,
            borderColor: const Color.fromRGBO(234, 226, 214, 0.6),
            iconBgColor: const Color.fromRGBO(240, 235, 225, 0.4),
            icon: Icons.edit_outlined,
            iconColor: const Color.fromRGBO(51, 51, 51, 0.6),
            title: "Manual Expense",
            subtitle: "Type it in yourself",
            onTap: () {
              Navigator.pop(context);
              context.go('/manual-add');
            },
          ),
          
          // Row 3 - Add Income
          _buildActionRow(
            context: context,
            bgColor: Colors.white,
            borderColor: const Color.fromRGBO(234, 226, 214, 0.6),
            iconBgColor: const Color.fromRGBO(76, 175, 80, 0.05),
            icon: Icons.account_balance_wallet_outlined,
            iconColor: const Color(0xFF4CAF50),
            title: "Add Extra Income",
            subtitle: "Bonuses, freelance pay or gifts",
            onTap: () {
              Navigator.pop(context);
              context.go('/manual-add?type=income');
            },
          ),
          
          const SizedBox(height: 16),
          
          // Cancel Button
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              color: Colors.transparent,
              alignment: Alignment.center,
              child: Text(
                "CANCEL",
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 2.0,
                  color: const Color(0xFF9E9E9E),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
