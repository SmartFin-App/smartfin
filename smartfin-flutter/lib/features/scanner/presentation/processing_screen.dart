import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_fin/features/scanner/data/scanner_repository.dart';
import 'package:smart_fin/features/scanner/data/scanner_repository_impl.dart';
import 'package:smart_fin/features/scanner/services/slip_photo_check.dart';
import 'package:smart_fin/widgets/ui/ui.dart';

enum NotASlipChoice { retake, enterManually }

/// Shown when a photo has no slip or receipt in it, whether the phone's own
/// check or the server decided that. Dismissing it counts as a retake.
Future<NotASlipChoice> showNotASlipDialog(BuildContext context) async {
  final choice = await showDialog<NotASlipChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("This doesn't look like a slip"),
      content: Text(
        "We couldn't find a payment amount in this photo. Try a clear photo "
        'of a bank e-slip or receipt, or enter the expense yourself.',
        style: AppTextStyles.body,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, NotASlipChoice.enterManually),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
          ),
          child: const Text('Enter manually'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, NotASlipChoice.retake),
          child: const Text('Try another photo'),
        ),
      ],
    ),
  );
  return choice ?? NotASlipChoice.retake;
}

class ProcessingScreen extends StatefulWidget {
  final File? imageFile;

  /// Photo-library asset id when this scan came from the gallery watcher, so the
  /// slip can be marked processed after — not before — its transaction is saved.
  final String? slipAssetId;

  const ProcessingScreen({super.key, this.imageFile, this.slipAssetId});

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen>
    with TickerProviderStateMixin {
  String _statusMessage = 'Checking your photo';

  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;
  late AnimationController _dotsController;

  @override
  void initState() {
    super.initState();

    // Bounce animation for the receipt icon
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _bounceAnimation = Tween<double>(begin: 0, end: -12).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );

    // Dots animation
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.imageFile == null) {
        _handleNoImage();
      } else {
        _processReceipt();
      }
    });
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  Future<void> _handleNoImage() async {
    if (!mounted) return;
    showAppToast(context, 'No image selected', error: true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) context.go('/scanner');
  }

  Future<void> _processReceipt() async {
    if (widget.imageFile == null) return;

    // Any throw here (a missing temp file, an unexpected response) would otherwise
    // leave this screen spinning forever with no way back.
    try {
      // A photo with no amount in it is turned away here, before Gemini sees it.
      final verdict = await SlipPhotoCheck.check(widget.imageFile!);
      if (!mounted) return;
      if (verdict == SlipPhotoVerdict.notSlip) {
        await _rejectPhoto();
        return;
      }

      setState(() => _statusMessage = 'Reading your receipt');
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final result = await ScannerRepositoryImpl().processReceipt(
        widget.imageFile!,
        uid,
      );

      if (!mounted) return;

      if (result.success) {
        setState(() {
          _statusMessage = 'Almost done';
        });
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          context.go(
            '/verify',
            extra: {
              ...?result.data,
              if (widget.slipAssetId != null) 'asset_id': widget.slipAssetId,
            },
          );
        }
      } else if (result.error == ScannerRepository.notASlipError) {
        await _rejectPhoto();
      } else {
        showAppToast(
          context,
          result.error ?? 'Could not read that receipt',
          error: true,
        );
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) context.go('/scanner');
      }
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, 'Could not read that receipt: $e', error: true);
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) context.go('/scanner');
    }
  }

  Future<void> _rejectPhoto() async {
    final choice = await showNotASlipDialog(context);
    if (!mounted) return;
    context.go(
      choice == NotASlipChoice.enterManually ? '/manual-add' : '/scanner',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Receipt icon with bounce, on a soft ring that spins while
              // the slip is read.
              SizedBox(
                width: 132,
                height: 132,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const SizedBox.expand(
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        backgroundColor: AppColors.surfaceMuted,
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _bounceAnimation,
                      builder: (context, child) => Transform.translate(
                        offset: Offset(0, _bounceAnimation.value / 2),
                        child: child,
                      ),
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.receipt_long_rounded,
                          size: 44,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Status message + animated dots. The dots sit in a fixed-width
              // box so the text does not shift as they change.
              AnimatedBuilder(
                animation: _dotsController,
                builder: (context, _) {
                  final dotCount = (_dotsController.value * 3).floor() + 1;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_statusMessage, style: AppTextStyles.heading),
                      SizedBox(
                        width: 24,
                        child: Text(
                          '.' * dotCount,
                          style: AppTextStyles.heading,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'AI is reading the amount, merchant and date. This takes a few seconds.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
