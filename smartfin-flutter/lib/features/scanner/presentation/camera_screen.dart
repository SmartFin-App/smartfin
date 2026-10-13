import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _scanAnimationController;
  late CurvedAnimation _curvedAnimation;

  CameraController? _controller;
  bool _initializing = false;
  bool _capturing = false;

  /// Why there is no live preview (no permission, no camera), or null.
  String? _cameraError;

  bool get _cameraReady => _controller?.value.isInitialized ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
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
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _scanAnimationController.dispose();
    super.dispose();
  }

  /// The camera is released while the app is in the background and reopened on
  /// return. A controller that has not finished initializing is left alone: the
  /// permission prompt itself makes the app inactive.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      // Coming back from Settings after granting access.
      if (state == AppLifecycleState.resumed && _cameraError != null) {
        _initCamera();
      }
      return;
    }
    if (state == AppLifecycleState.inactive) {
      setState(() => _controller = null);
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (_initializing) return;
    _initializing = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(
            () => _cameraError =
                'No camera found on this device. Pick a slip from your gallery instead.',
          );
        }
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      // No audio: slips are stills, and it avoids a microphone prompt.
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _cameraError = null);
    } on CameraException catch (e) {
      debugPrint('Camera init error: ${e.code} ${e.description}');
      _controller = null;
      if (!mounted) return;
      final denied = e.code.startsWith('CameraAccess');
      setState(
        () => _cameraError = denied
            ? 'SmartFin needs camera access to scan slips. Enable it in Settings, or pick a slip from your gallery.'
            : "We couldn't start the camera. Pick a slip from your gallery instead.",
      );
    } finally {
      _initializing = false;
    }
  }

  Future<void> _takePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final photo = await controller.takePicture();
      if (mounted) context.go('/processing', extra: File(photo.path));
    } on CameraException catch (e) {
      debugPrint('Capture error: ${e.code} ${e.description}');
      if (mounted) {
        showAppToast(
          context,
          "Couldn't take the photo. Try again.",
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// The live preview, scaled to cover the screen like a viewfinder.
  Widget _buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    // previewSize is reported in sensor (landscape) orientation.
    final size = controller.value.previewSize;
    if (size == null) return CameraPreview(controller);
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.height,
          height: size.width,
          child: CameraPreview(controller),
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
          // 1. Live camera preview
          Positioned.fill(child: _buildPreview()),

          // 2. Overlay Scanning Frame, or why the camera is unavailable
          if (_cameraError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  _cameraError!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.label.copyWith(color: Colors.white),
                ),
              ),
            )
          else if (!_cameraReady)
            const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          else
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

                        // Center Shutter Button
                        Semantics(
                          button: true,
                          enabled: _cameraReady && !_capturing,
                          label: 'Take photo',
                          child: GestureDetector(
                            onTap: _takePhoto,
                            child: Opacity(
                              opacity: _cameraReady && !_capturing ? 1 : 0.4,
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
