import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_fin/widgets/ui/ui.dart';
import 'package:smart_fin/widgets/smartfin_logo.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _bounceAnimation = Tween<double>(begin: 0, end: -15).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOutSine),
    );

    _routeWhenAuthResolved();
  }

  /// Decides where to go once Firebase has actually restored the persisted
  /// session, rather than after a fixed delay.
  ///
  /// `currentUser` is null until that restore completes, so a timer that expires
  /// first sent a signed-in user to the login screen as though they had never
  /// logged in — rare on a warm start, likely on a cold one.
  Future<void> _routeWhenAuthResolved() async {
    // Keep the splash on screen long enough to read, but run the auth wait
    // alongside it rather than after it.
    final minimumDisplay = Future<void>.delayed(
      const Duration(milliseconds: 1800),
    );

    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      try {
        // authStateChanges emits the restored user, or null once Firebase has
        // settled on "nobody is signed in".
        user = await FirebaseAuth.instance.authStateChanges().first.timeout(
          const Duration(seconds: 5),
        );
      } catch (_) {
        // Timed out or errored: fall through to the signed-out route rather
        // than leaving the user stuck on the splash screen.
        user = null;
      }
    }

    await minimumDisplay;
    if (!mounted) return;
    context.go(user != null ? '/home' : '/login');
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Stack(
        children: [
          // Main content centered horizontally but positioned ~35% from top
          Positioned(
            top: screenHeight * 0.35 - (161 / 2),
            left: 0,
            right: 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Wordmark, carrying the bounce the cat illustration used to.
                AnimatedBuilder(
                  animation: _bounceAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _bounceAnimation.value),
                      child: child,
                    );
                  },
                  child: const SmartFinLogo(fontSize: 60, letterSpacing: -3),
                ),
                const SizedBox(height: 8),
                // Tagline. Sentence case rather than tracked capitals, and
                // scaled down rather than wrapped on a narrow screen.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Automatic expense tracking',
                      style: AppTextStyles.body.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Bottom content
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // Pulsing dot
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(
                              alpha: _pulseController.value * 0.6,
                            ),
                            blurRadius: 10 * _pulseController.value,
                            spreadRadius: 4 * _pulseController.value,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text('Loading', style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
