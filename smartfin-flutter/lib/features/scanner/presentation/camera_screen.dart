import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:smart_fin/features/scanner/services/gallery_watcher_service.dart';
import 'package:smart_fin/features/scanner/presentation/widgets/slip_detection_sheet.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with SingleTickerProviderStateMixin {
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
        return "No 'SmartFin Receipts' album yet. Save PromptPay slips to that album to auto-detect!";
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
                    child: CustomPaint(
                      painter: ScannerOverlayPainter(),
                    ),
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
                            color: Color.fromRGBO(255, 159, 41, 0.4),
                            // Subtle glow
                            boxShadow: [
                              BoxShadow(
                                color: Color.fromRGBO(255, 159, 41, 0.6),
                                blurRadius: 10,
                                blurStyle: BlurStyle.outer,
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  )
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
                padding: const EdgeInsets.only(top: 16, left: 24, right: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back
                    GestureDetector(
                      onTap: () => context.go('/home'),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(255, 255, 255, 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.1)),
                        ),
                        child: const Icon(Icons.chevron_left, color: Colors.white, size: 22),
                      ),
                    ),
                    // Auto-Detect button
                    GestureDetector(
                      onTap: () async {
                        final result = await GalleryWatcherService()
                            .checkForNewSlipsDetailed();
                        if (!context.mounted) return;
                        if (result.slip != null) {
                          SlipDetectionSheet.show(context, result.slip!);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_slipCheckMessage(result.status)),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(255, 159, 41, 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color.fromRGBO(255, 159, 41, 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.photo_album_outlined, color: Color(0xFFFF9F29), size: 16),
                            const SizedBox(width: 6),
                            Text(
                              "SLIPS ALBUM",
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                                letterSpacing: 1,
                                color: const Color(0xFFFF9F29),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Flash (decorative in demo mode)
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(255, 255, 255, 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.1)),
                      ),
                      child: const Icon(
                        Icons.flashlight_off,
                        color: Colors.white,
                        size: 22,
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
              height: 200,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 320,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // Gallery Button
                          GestureDetector(
                            onTap: () async {
                              final xFile = await ImagePicker().pickImage(
                                source: ImageSource.gallery,
                                imageQuality: 85,
                              );
                              if (xFile != null && context.mounted) {
                                context.go('/processing', extra: File(xFile.path));
                              }
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: const Color.fromRGBO(255, 255, 255, 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.1)),
                                  ),
                                  child: const Icon(
                                    Icons.photo_library_outlined, 
                                    color: Color.fromRGBO(255, 255, 255, 0.4), 
                                    size: 22
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "GALLERY",
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 9,
                                    letterSpacing: 2,
                                    color: const Color.fromRGBO(255, 255, 255, 0.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          // Center Shutter Button (uses sample receipt in demo mode)
                          GestureDetector(
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
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color.fromRGBO(255, 255, 255, 0.3),
                                  width: 2,
                                ),
                              ),
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                          
                          // Manual Button
                          GestureDetector(
                            onTap: () {
                              context.go('/manual-add');
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: const Color.fromRGBO(255, 255, 255, 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.1)),
                                  ),
                                  child: const Icon(
                                    Icons.keyboard_outlined, 
                                    color: Color.fromRGBO(255, 255, 255, 0.4), 
                                    size: 22
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "MANUAL",
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 9,
                                    letterSpacing: 2,
                                    color: const Color.fromRGBO(255, 255, 255, 0.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "SCAN RECEIPT",
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        letterSpacing: 2,
                        color: const Color.fromRGBO(255, 255, 255, 0.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
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
      ..arcToPoint(const Offset(radius, 0), radius: const Radius.circular(radius))
      ..lineTo(lineLength, 0);
    canvas.drawPath(topLeft, paint);

    // Top-Right corner
    Path topRight = Path()
      ..moveTo(size.width - lineLength, 0)
      ..lineTo(size.width - radius, 0)
      ..arcToPoint(Offset(size.width, radius), radius: const Radius.circular(radius))
      ..lineTo(size.width, lineLength);
    canvas.drawPath(topRight, paint);

    // Bottom-Left corner
    Path bottomLeft = Path()
      ..moveTo(0, size.height - lineLength)
      ..lineTo(0, size.height - radius)
      ..arcToPoint(Offset(radius, size.height), radius: const Radius.circular(radius), clockwise: false)
      ..lineTo(lineLength, size.height);
    canvas.drawPath(bottomLeft, paint);

    // Bottom-Right corner
    Path bottomRight = Path()
      ..moveTo(size.width - lineLength, size.height)
      ..lineTo(size.width - radius, size.height)
      ..arcToPoint(Offset(size.width, size.height - radius), radius: const Radius.circular(radius), clockwise: false)
      ..lineTo(size.width, size.height - lineLength);
    canvas.drawPath(bottomRight, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
