import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_fin/features/scanner/services/gallery_watcher_service.dart';
import 'package:smart_fin/widgets/ui/ui.dart';
import 'package:smart_fin/features/scanner/presentation/widgets/slip_detection_sheet.dart';
import 'package:smart_fin/features/scanner/presentation/widgets/slip_folders_sheet.dart';

class ActionHubSheet extends StatelessWidget {
  const ActionHubSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      barrierColor: Colors.black.withValues(alpha: 0.2),
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: const ActionHubSheet(),
      ),
    );
  }

  /// One way to add an expense: an icon tile, what it does, and a chevron.
  /// [highlight] tints the card for the main path (scanning).
  Widget _buildAction({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool highlight = false,
  }) {
    return AppCard(
      flat: !highlight,
      color: highlight
          ? Color.alphaBlend(
              AppColors.primary.withValues(alpha: 0.08),
              AppColors.white,
            )
          : AppColors.white,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ListRow(
        leading: IconTile(icon: icon, color: color, size: 48),
        title: title,
        subtitle: subtitle,
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.textMuted,
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
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
        return "We couldn't find your slip folder. Pick the one your bank saves slips to.";
      case SlipCheckStatus.none:
      case SlipCheckStatus.found:
        return "No new slips found. You're all caught up!";
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add an expense',
              textAlign: TextAlign.center,
              style: AppTextStyles.title,
            ),
            const SizedBox(height: AppSpacing.xl),

            _buildAction(
              icon: Icons.document_scanner_outlined,
              color: AppColors.primary,
              title: 'Scan a slip',
              subtitle: 'Read a slip or receipt with AI',
              highlight: true,
              onTap: () {
                Navigator.pop(context);
                context.go('/scanner');
              },
            ),
            const SizedBox(height: AppSpacing.md),

            // Backed by GalleryWatcherService.
            _buildAction(
              icon: Icons.photo_library_outlined,
              color: const Color(0xFF2563EB),
              title: 'Auto-Detect',
              subtitle: 'Find new slips in your photos',
              onTap: () async {
                // Capture the ancestors before popping: this sheet's own context is
                // deactivated by the pop, so anything guarded on context.mounted
                // afterwards silently never runs.
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                final rootContext = navigator.context;

                final result = await GalleryWatcherService()
                    .checkForNewSlipsDetailed();
                navigator.pop();
                if (!rootContext.mounted) return;

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
                              onPressed: () =>
                                  SlipFoldersSheet.show(rootContext),
                            )
                          : null,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: AppSpacing.md),

            _buildAction(
              icon: Icons.edit_outlined,
              color: AppColors.textSecondary,
              title: 'Enter manually',
              subtitle: 'Type it in yourself',
              onTap: () {
                Navigator.pop(context);
                context.go('/manual-add');
              },
            ),
            const SizedBox(height: AppSpacing.sm),

            AppButton.text(
              label: 'Cancel',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
