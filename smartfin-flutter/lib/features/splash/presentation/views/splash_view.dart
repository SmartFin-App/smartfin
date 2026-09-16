import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
// SharedPreferences no longer needed for onboarding check
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smart_fin/constants/color_style.dart';

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
      CurvedAnimation(
        parent: _bounceController,
        curve: Curves.easeInOutSine,
      ),
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
    final minimumDisplay = Future<void>.delayed(const Duration(milliseconds: 1800));

    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      try {
        // authStateChanges emits the restored user, or null once Firebase has
        // settled on "nobody is signed in".
        user = await FirebaseAuth.instance
            .authStateChanges()
            .first
            .timeout(const Duration(seconds: 5));
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
                // Cat and Glow
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Glow behind cat
                    Container(
                      width: 288,
                      height: 288,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color.fromRGBO(255, 159, 41, 0.05),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromRGBO(255, 159, 41, 0.05),
                            blurRadius: 50,
                          ),
                        ],
                      ),
                    ),
                    // Lucky cat image
                    AnimatedBuilder(
                      animation: _bounceAnimation,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, _bounceAnimation.value),
                          child: child,
                        );
                      },
                      child: Image.asset(
                        'assets/images/lucky_cat.png',
                        width: 160,
                        height: 161,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // App name
                Text(
                  'SmartFin',
                  style: GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w800,
                    fontSize: 60,
                    letterSpacing: -3,
                    color: const Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 8),
                // Tagline
                Text(
                  'YOUR AI FINANCIAL COACH',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 4.2,
                    color: const Color(0xFFFF9F29),
                  ),
                  textAlign: TextAlign.center,
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
                        color: const Color(0xFFFF9F29),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF9F29).withOpacity(_pulseController.value * 0.6),
                            blurRadius: 10 * _pulseController.value,
                            spreadRadius: 4 * _pulseController.value,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'BOOTING UP...',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                    letterSpacing: 2.5,
                    color: const Color(0xFF9E9E9E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
