import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:smart_fin/features/scanner/services/gallery_watcher_service.dart';
import 'package:smart_fin/features/scanner/presentation/widgets/slip_detection_sheet.dart';
import 'package:smart_fin/features/scanner/presentation/widgets/slip_folders_sheet.dart';
import 'package:smart_fin/widgets/ui/ui.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _scanAnimationController;
  late CurvedAnimation _curvedAnimation;

  @override
  void initState() {
    super.initState();
    _scanAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _curvedAnimation = CurvedAnimation(
      parent: _scanAnimationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _scanAnimationController.dispose();
    super.dispose();
  }

  /// Copies the bundled sample receipt asset to a temp file and returns it.
  Future<File> _getReceiptFile() async {
    final byteData = await rootBundle.load('assets/images/sample_receipt.png');
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/sample_receipt.png');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file;
  }

  String _slipCheckMessage(SlipCheckStatus status) {
    switch (status) {
      case SlipCheckStatus.permissionDenied:
        return "SmartFin needs photo access to spot your payment slips. Enable it in Settings.";
      case SlipCheckStatus.disabled:
        return "Auto-Detect is turned off. You can switch it back on in your profile.";
      case SlipCheckStatus.noAlbum:
        // Same wording and picker offer as the action hub.
        return "We couldn't find your slip folder. Pick the one your bank saves slips to.";
      case SlipCheckStatus.none:
      case SlipCheckStatus.found:
        return "No new slips found. You're all caught up!";
    }
  }

  @override
  Widget build(BuildContext context) {
    // 80% screen width, 4:5 aspect ratio
    final double frameWidth = MediaQuery.of(context).size.width * 0.8;
    final double frameHeight = frameWidth * (5 / 4);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Static Receipt Image (demo mode — replaces live camera)
          Positioned.fill(
            child: Image.asset(
              'assets/images/sample_receipt.png',
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),

          // 2. Overlay Scanning Frame
          Center(
            child: SizedBox(
              width: frameWidth,
              height: frameHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: ScannerOverlayPainter()),
                  ),
                  AnimatedBuilder(
                    animation: _curvedAnimation,
                    builder: (context, child) {
                      return Positioned(
                        top: _curvedAnimation.value * frameHeight,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 2,
                          decoration: const BoxDecoration(
                            color: Color.fromRGBO(255, 159, 41, 0.6),
                            // Subtle glow
                            boxShadow: [
                              BoxShadow(
                                color: Color.fromRGBO(255, 159, 41, 0.6),
                                blurRadius: 10,
                                blurStyle: BlurStyle.outer,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // 3. Top Header navigation
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  AppSpacing.sm,
                  AppSpacing.screen,
                  0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _glassButton(
                      semanticLabel: 'Back',
                      onTap: () => context.go('/home'),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    // Auto-Detect
                    _glassButton(
                      semanticLabel: 'Auto-Detect slips',
                      onTap: () async {
                        final result = await GalleryWatcherService()
                            .checkForNewSlipsDetailed();
                        if (!context.mounted) return;
                        if (result.slip != null) {
                          SlipDetectionSheet.show(context, result.slip!);
                        } else {
                          final offerPicker =
                              result.status == SlipCheckStatus.noAlbum;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_slipCheckMessage(result.status)),
                              duration: Duration(seconds: offerPicker ? 8 : 3),
                              action: offerPicker
                                  ? SnackBarAction(
                                      label: 'Pick',
                                      onPressed: () =>
                                          SlipFoldersSheet.show(context),
                                    )
                                  : null,
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.auto_awesome_rounded,
                              color: AppColors.primary,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Auto-Detect',
                              style: AppTextStyles.label.copyWith(
                                color: Colors.white,
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
          ),

          // 4. Bottom Controls Interface
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x99000000), Colors.black],
                  stops: [0, 0.45, 1],
                ),
              ),
              padding: const EdgeInsets.only(top: 72, bottom: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      'Line the slip up inside the frame',
                      style: AppTextStyles.label.copyWith(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    width: 320,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sideAction(
                          icon: Icons.photo_library_outlined,
                          label: 'Gallery',
                          onTap: () async {
                            final xFile = await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 85,
                            );
                            if (xFile != null && context.mounted) {
                              context.go(
                                '/processing',
                                extra: File(xFile.path),
                              );
                            }
                          },
                        ),

                        // Center Shutter Button (uses sample receipt in demo mode)
                        Semantics(
                          button: true,
                          label: 'Take photo',
                          child: GestureDetector(
                            onTap: () async {
                              try {
                                final file = await _getReceiptFile();
                                if (context.mounted) {
                                  context.go('/processing', extra: file);
                                }
                              } catch (e) {
                                debugPrint('Demo capture error: $e');
                              }
                            },
                            child: Container(
                              width: 80,
                              height: 80,
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  width: 3,
                                ),
                              ),
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),

                        _sideAction(
                          icon: Icons.edit_outlined,
                          label: 'Manual',
                          onTap: () => context.go('/manual-add'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A dark translucent control for the camera view. Dark rather than frosted
  /// white: a white slip fills most of the frame, and white-on-white vanished.
  Widget _glassButton({
    required String semanticLabel,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(widthFactor: 1, child: child),
          ),
        ),
      ),
    );
  }

  Widget _sideAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _glassButton(
          semanticLabel: label,
          onTap: onTap,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          style: AppTextStyles.label.copyWith(
            fontSize: 12,
            color: Colors.white,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
          ),
        ),
      ],
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF9F29)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    const double lineLength = 24.0;
    const double radius = 12.0;

    // Top-Left corner
    Path topLeft = Path()
      ..moveTo(0, lineLength)
      ..lineTo(0, radius)
      ..arcToPoint(
        const Offset(radius, 0),
        radius: const Radius.circular(radius),
      )
      ..lineTo(lineLength, 0);
    canvas.drawPath(topLeft, paint);

    // Top-Right corner
    Path topRight = Path()
      ..moveTo(size.width - lineLength, 0)
      ..lineTo(size.width - radius, 0)
      ..arcToPoint(
        Offset(size.width, radius),
        radius: const Radius.circular(radius),
      )
      ..lineTo(size.width, lineLength);
    canvas.drawPath(topRight, paint);

    // Bottom-Left corner
    Path bottomLeft = Path()
      ..moveTo(0, size.height - lineLength)
      ..lineTo(0, size.height - radius)
      ..arcToPoint(
        Offset(radius, size.height),
        radius: const Radius.circular(radius),
        clockwise: false,
      )
      ..lineTo(lineLength, size.height);
    canvas.drawPath(bottomLeft, paint);

    // Bottom-Right corner
    Path bottomRight = Path()
      ..moveTo(size.width - lineLength, size.height)
      ..lineTo(size.width - radius, size.height)
      ..arcToPoint(
        Offset(size.width, size.height - radius),
        radius: const Radius.circular(radius),
        clockwise: false,
      )
      ..lineTo(size.width, size.height - lineLength);
    canvas.drawPath(bottomRight, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
