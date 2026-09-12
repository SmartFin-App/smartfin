import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_fin/constants/color_style.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  // Animations
  late AnimationController _bounceController;
  late AnimationController _pulseController;
  late AnimationController _entryController;
  
  late Animation<double> _bounceAnimation;
  late Animation<double> _pulseAnimation;
  
  late Animation<double> _headingFade;
  late Animation<Offset> _headingSlide;
  late Animation<double> _bodyFade;
  late Animation<Offset> _bodySlide;
  late Animation<double> _footerFade;

  @override
  void initState() {
    super.initState();
    
    // Bounce
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat(reverse: true);
    
    _bounceAnimation = Tween<double>(begin: -10, end: 10).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );

    // Pulse
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Entry animations
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // Heading: delay 200ms, duration 700ms -> interval (0.2, 0.9)
    _headingFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entryController, curve: const Interval(0.2, 0.9, curve: Curves.easeOut)),
    );
    _headingSlide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _entryController, curve: const Interval(0.2, 0.9, curve: Curves.easeOutCubic)),
    );

    // Body: delay 300ms, duration 700ms -> interval (0.3, 1.0)
    _bodyFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entryController, curve: const Interval(0.3, 1.0, curve: Curves.easeOut)),
    );
    _bodySlide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _entryController, curve: const Interval(0.3, 1.0, curve: Curves.easeOutCubic)),
    );

    // Footer: delay 500ms -> interval (0.5, 1.0)
    _footerFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entryController, curve: const Interval(0.5, 1.0, curve: Curves.easeIn)),
    );

    _entryController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _bounceController.dispose();
    _pulseController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    _entryController.forward(from: 0.0);
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (mounted) {
      context.push('/signup'); // Maintaining push to signup per previous requests
    }
  }

  final List<Map<String, dynamic>> _slides = [
    {
      'image': 'assets/images/onboarding_1.png',
      'glow': const Color.fromRGBO(255, 159, 41, 0.05),
      'heading': 'Konnichiwa, Ant!',
      'body': 'I\'m your SmartFin Coach. I don\'t just track your Baht; I help you grow it with AI-powered wisdom. 🐾',
      'button': 'Let\'s Get Started',
    },
    {
      'image': 'assets/images/onboarding_2.png',
      'glow': const Color.fromRGBO(74, 144, 226, 0.05),
      'heading': 'Scan. Relax. Repeat.',
      'body': 'Stop typing every transaction. Just snap a photo of your receipt, and I\'ll categorize everything for you in seconds. 📸',
      'button': 'Continue',
    },
    {
      'image': 'assets/images/onboarding_3.png',
      'glow': const Color.fromRGBO(255, 159, 41, 0.05),
      'heading': 'Ask Your Money Anything.',
      'body': 'Wondering if you\'re on track for your goals? Just ask. I use your real-time data to give you honest, personalized advice. 💬',
      'button': 'Continue',
    },
    {
      'image': 'assets/images/onboarding_4.png',
      'glow': const Color.fromRGBO(255, 159, 41, 0.05),
      'heading': 'Reach Your North Star.',
      'body': 'Whether it\'s a weekend in Chiang Mai or your first luxury treat, let\'s build the habit that gets you there faster. 🌟',
      'button': 'Let\'s Go!',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Stack(
        children: [
          // Main Body
          Column(
            children: [
              // Spacer for Header
              const SizedBox(height: 64),
              
              // Expanded PageView
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  itemCount: _slides.length,
                  itemBuilder: (context, index) {
                    final slide = _slides[index];
                    return _buildSlideContent(slide);
                  },
                ),
              ),

              // Footer Area
              SizedBox(
                height: 192,
                child: FadeTransition(
                  opacity: _footerFade,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _slides.length,
                          (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            width: _currentIndex == index ? 32 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _currentIndex == index 
                                  ? const Color(0xFFFF9F29) 
                                  : const Color(0xFFEAE2D6),
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: _currentIndex == index
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFFFF9F29).withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : [],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Button
                      _AnimatedButton(
                        label: _slides[_currentIndex]['button'] as String,
                        onTap: () {
                          if (_currentIndex == _slides.length - 1) {
                            _completeOnboarding();
                          } else {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOut,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Header (Sticky at top)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
                child: Container(
                  height: 64,
                  color: const Color.fromRGBO(255, 249, 240, 0.5),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: GestureDetector(
                      onTap: _completeOnboarding,
                      child: Text(
                        'SKIP',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 2.0,
                          color: const Color(0xFF9E9E9E),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlideContent(Map<String, dynamic> slide) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
            // Image with Pulse Glow
            SizedBox(
              width: 180,
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Pulse Glow
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: slide['glow'] as Color,
                            boxShadow: [
                              BoxShadow(
                                color: slide['glow'] as Color,
                                blurRadius: 30,
                                spreadRadius: 15,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  // Bounce Image
                  AnimatedBuilder(
                    animation: _bounceAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _bounceAnimation.value),
                        child: Image.asset(
                          slide['image'] as String,
                          width: 180,
                          height: 180,
                          fit: BoxFit.contain,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Animated Heading
            FadeTransition(
              opacity: _headingFade,
              child: SlideTransition(
                position: _headingSlide,
                child: Text(
                  slide['heading'] as String,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w800,
                    fontSize: 30,
                    letterSpacing: -1.5,
                    color: const Color(0xFF333333),
                    height: 1.1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Animated Body
            FadeTransition(
              opacity: _bodyFade,
              child: SlideTransition(
                position: _bodySlide,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    slide['body'] as String,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                      height: 1.625, // 26px line height
                      color: const Color(0xFF9E9E9E),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _AnimatedButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _AnimatedButton({required this.label, required this.onTap});

  @override
  State<_AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<_AnimatedButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: 320,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFFF9F29),
            borderRadius: BorderRadius.circular(9999),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF9F29).withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label.toUpperCase(),
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 2.0,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
