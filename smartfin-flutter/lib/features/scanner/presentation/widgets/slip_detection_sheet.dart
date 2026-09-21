import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:smart_fin/widgets/ui/ui.dart';
import 'package:smart_fin/features/scanner/services/gallery_watcher_service.dart';

/// Modal bottom sheet shown when a new payment slip is detected in "SmartFin Receipts"
class SlipDetectionSheet extends StatelessWidget {
  final DetectedSlip slip;
  final VoidCallback? onDismissed;

  const SlipDetectionSheet({super.key, required this.slip, this.onDismissed});

  /// Helper to show this sheet
  static Future<void> show(BuildContext context, DetectedSlip slip) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SlipDetectionSheet(slip: slip),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat(
      'd MMM yyyy · h:mm a',
    ).format(slip.createDateTime);

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
            // Header with auto-detect badge
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: AppColors.primaryText,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Auto-Detect',
                      style: AppTextStyles.label.copyWith(
                        fontSize: 12,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'New payment slip found',
              textAlign: TextAlign.center,
              style: AppTextStyles.title,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              "Found in '${slip.albumName}'. Scan it and add it as an expense?",
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Thumbnail preview
            Container(
              height: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.border),
                boxShadow: AppShadows.card,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      slip.file,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) => const Center(
                        child: Icon(
                          Icons.receipt_long_rounded,
                          size: 48,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.75),
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                slip.albumName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.label.copyWith(
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            Text(
                              formattedDate,
                              style: AppTextStyles.caption.copyWith(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            AppButton(
              label: 'Scan and add',
              icon: Icons.document_scanner_outlined,
              expand: true,
              onPressed: () {
                // The asset id travels with the image and is marked processed only
                // after the transaction saves. Marking here meant a failed scan
                // (server down, bad image) hid the slip from the watcher forever.
                Navigator.of(context).pop();
                context.go(
                  '/processing',
                  extra: {'file': slip.file, 'assetId': slip.asset.id},
                );
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              onPressed: () async {
                // Mark as processed/dismissed so user isn't prompted again
                await GalleryWatcherService().markSlipAsProcessed(
                  slip.asset.id,
                );
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
                onDismissed?.call();
              },
              child: const Text('Not this one'),
            ),
          ],
        ),
      ),
    );
  }
}
