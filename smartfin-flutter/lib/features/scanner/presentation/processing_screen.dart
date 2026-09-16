import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_fin/features/scanner/data/scanner_repository_impl.dart';

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
  String _statusMessage = 'Scanning your receipt...';

  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;
  late AnimationController _dotsController;

  @override
  void initState() {
    super.initState();

    // Bounce animation for lucky cat
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No image selected')),
    );
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) context.go('/scanner');
  }

  Future<void> _processReceipt() async {
    if (widget.imageFile == null) return;

    setState(() => _statusMessage = 'Reading receipt data...');

    // Any throw here (a missing temp file, an unexpected response) would otherwise
    // leave this screen spinning forever with no way back.
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final result = await ScannerRepositoryImpl()
          .processReceipt(widget.imageFile!, uid);

      if (!mounted) return;

      if (result.success) {
        setState(() {
          _statusMessage = 'Almost done...';
        });
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          context.go('/verify', extra: {
            ...?result.data,
            if (widget.slipAssetId != null) 'asset_id': widget.slipAssetId,
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? 'Failed to process receipt')),
        );
        await Future.delayed(const Duration(milliseconds: 1500));
        if (mounted) context.go('/scanner');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read that receipt: $e')),
      );
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) context.go('/scanner');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9F0),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Lucky cat with bounce
            AnimatedBuilder(
              animation: _bounceAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _bounceAnimation.value),
                  child: child,
                );
              },
              child: const Icon(
                Icons.receipt_long_outlined,
                size: 96,
                color: Color(0xFFFF9F29),
              ),
            ),
            const SizedBox(height: 32),

            // Spinner
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: Color(0xFFFF9F29),
                strokeWidth: 2.5,
              ),
            ),
            const SizedBox(height: 24),

            // Status message + animated dots
            AnimatedBuilder(
              animation: _dotsController,
              builder: (context, _) {
                final dotCount = (_dotsController.value * 3).floor() + 1;
                final dots = '.' * dotCount;
                return Text(
                  '${_statusMessage.toUpperCase()}$dots',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 2,
                    color: const Color(0xFF9E9E9E),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
