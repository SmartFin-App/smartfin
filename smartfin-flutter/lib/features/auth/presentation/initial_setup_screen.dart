import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/core/network/dio_client.dart';
import 'package:smart_fin/features/auth/data/auth_repository_impl.dart';

class InitialSetupScreen extends StatefulWidget {
  const InitialSetupScreen({super.key});

  @override
  State<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends State<InitialSetupScreen> with TickerProviderStateMixin {
  String? selectedIncome;
  String? selectedStatus;
  String? selectedHealth;
  final _nameController = TextEditingController();
  bool _isLoading = false;

  late AnimationController _catController;
  late Animation<double> _catFade;
  late Animation<double> _catScale;

  late AnimationController _contentController;
  late Animation<double> _contentFade;
  late Animation<Offset> _contentSlide;

  bool _isButtonPressed = false;

  @override
  void initState() {
    super.initState();

    // Cat Image Animation: fade-in zoom-in duration 700ms
    _catController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _catFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _catController, curve: Curves.easeOut),
    );
    _catScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _catController, curve: Curves.easeOutBack),
    );

    // Content: slide-in from bottom fade-in duration 700ms delay 200ms
    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900), // 200ms delay + 700ms duration
    );
    _contentFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.22, 1.0, curve: Curves.easeOut)),
    );
    _contentSlide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.22, 1.0, curve: Curves.easeOutCubic)),
    );

    _catController.forward();
    _contentController.forward();
  }

  @override
  void dispose() {
    _catController.dispose();
    _contentController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  double _parseIncome(String bracket) {
    switch (bracket) {
      case 'Under 20k': return 15000;
      case '20k-50k':   return 35000;
      case '50k-100k':  return 75000;
      case '100k+':     return 150000;
      default:          return 0;
    }
  }

  Future<void> _submitSetup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || selectedIncome == null || selectedStatus == null || selectedHealth == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all fields to continue')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No authenticated user found.');

      // Update Firebase display name
      await user.updateDisplayName(name);

      final monthlyIncome = _parseIncome(selectedIncome!);
      final budgetLimit = monthlyIncome * 0.7;

      // Save to Go backend
      final repo = AuthRepositoryImpl();
      final result = await repo.createUser(
        firebaseUID: user.uid,
        name: name,
        email: user.email ?? '',
        photoURL: user.photoURL ?? '',
        monthlyIncome: monthlyIncome,
        incomeBracket: selectedIncome!,
        currentStatus: selectedStatus!,
        financialHealth: selectedHealth!,
        budgetLimit: budgetLimit,
      );

      if (!result.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.error ?? 'Failed to save setup.')),
          );
        }
        return;
      }

      // Persist locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('setup_complete', true);
      await prefs.setString('user_name', name);
      await prefs.setString('user_income', selectedIncome!);
      await prefs.setString('user_status', selectedStatus!);
      await prefs.setString('user_health', selectedHealth!);
      // setInt, not setDouble: these are read back with getInt, which throws a
      // TypeError on a stored double and left Profile showing ฿0.
      await prefs.setInt('user_income_amount', monthlyIncome.round());
      await prefs.setInt('user_budget_limit', budgetLimit.round());
      await prefs.setBool('onboarding_complete', true);

      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DioClient.handleError(e is Exception ? e as dynamic : Exception(e.toString())))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        label,
        style: GoogleFonts.inter( // Using Inter instead of Geist
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 2.0,
          color: const Color(0xFF9E9E9E),
        ),
      ),
    );
  }

  Widget _buildPill(String text, String? groupValue, ValueChanged<String> onSelect) {
    final bool isSelected = text == groupValue;
    return GestureDetector(
      onTap: () => onSelect(text),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color.fromRGBO(255, 159, 41, 0.05) : Colors.white,
          border: Border.all(
            color: isSelected ? const Color(0xFFFF9F29) : const Color(0xFFEAE2D6),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
            fontSize: 14,
            color: isSelected ? const Color(0xFFFF9F29) : const Color(0xFF333333),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard({
    required String label,
    required IconData icon,
    required String? groupValue,
    required ValueChanged<String> onSelect,
  }) {
    final bool isSelected = label == groupValue;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelect(label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: isSelected ? const Color(0xFFFF9F29) : const Color(0xFFEAE2D6),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color.fromRGBO(255, 159, 41, 0.05),
                      spreadRadius: 4,
                      blurRadius: 10,
                    )
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isSelected 
                      ? const Color.fromRGBO(255, 159, 41, 0.1) 
                      : const Color.fromRGBO(240, 235, 225, 0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? const Color(0xFFFF9F29) : const Color(0xFF9E9E9E),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                label.toUpperCase(),
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: isSelected ? const Color(0xFFFF9F29) : const Color(0xFF333333),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Stack(
        children: [
          // Scrollable Area
          SingleChildScrollView(
            padding: const EdgeInsets.only(top: 132, bottom: 120, left: 24, right: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top section: Cat + Title
                FadeTransition(
                  opacity: _catFade,
                  child: ScaleTransition(
                    scale: _catScale,
                    child: Column(
                      children: [
                        Image.asset('assets/images/lucky_cat.png', width: 128, height: 128),
                        const SizedBox(height: 16),
                        Text(
                          "Let's Build Your Profile.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.bricolageGrotesque(
                            fontWeight: FontWeight.w800,
                            fontSize: 30,
                            letterSpacing: -0.75,
                            color: const Color(0xFF333333),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 48),

                // Content sections
                FadeTransition(
                  opacity: _contentFade,
                  child: SlideTransition(
                    position: _contentSlide,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section 0: Name Field
                        _buildSectionLabel('PREFERRED NAME'),
                        Container(
                          margin: const EdgeInsets.only(bottom: 32),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFEAE2D6)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.02),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _nameController,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: const Color(0xFF333333),
                            ),
                            decoration: InputDecoration(
                              hintText: "What should we call you?",
                              hintStyle: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: const Color.fromRGBO(158, 158, 158, 0.3),
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                            ),
                          ),
                        ),

                        // Section 1: Monthly Income
                        _buildSectionLabel('MONTHLY INCOME'),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              _buildPill('Under 20k', selectedIncome, (val) => setState(() => selectedIncome = val)),
                              const SizedBox(width: 8),
                              _buildPill('20k-50k', selectedIncome, (val) => setState(() => selectedIncome = val)),
                              const SizedBox(width: 8),
                              _buildPill('50k-100k', selectedIncome, (val) => setState(() => selectedIncome = val)),
                              const SizedBox(width: 8),
                              _buildPill('100k+', selectedIncome, (val) => setState(() => selectedIncome = val)),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 32),

                        // Section 2: Current Status
                        _buildSectionLabel('CURRENT STATUS'),
                        Row(
                          children: [
                            _buildStatusCard(
                              label: 'Student', 
                              icon: Icons.school, 
                              groupValue: selectedStatus, 
                              onSelect: (val) => setState(() => selectedStatus = val),
                            ),
                            _buildStatusCard(
                              label: 'Pro', 
                              icon: Icons.work, 
                              groupValue: selectedStatus, 
                              onSelect: (val) => setState(() => selectedStatus = val),
                            ),
                            _buildStatusCard(
                              label: 'Founder', 
                              icon: Icons.rocket_launch, 
                              groupValue: selectedStatus, 
                              onSelect: (val) => setState(() => selectedStatus = val),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        // Section 3: Financial Health
                        _buildSectionLabel('FINANCIAL HEALTH'),
                        Wrap(
                          spacing: 8,
                          runSpacing: 12,
                          children: [
                            _buildPill('Debt-Free', selectedHealth, (val) => setState(() => selectedHealth = val)),
                            _buildPill('Saving Up', selectedHealth, (val) => setState(() => selectedHealth = val)),
                            _buildPill('Managing Debt', selectedHealth, (val) => setState(() => selectedHealth = val)),
                            _buildPill('Paycheck to Paycheck', selectedHealth, (val) => setState(() => selectedHealth = val)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Header (Back button)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                child: Container(
                  height: 112, // Status bar + 48 padding
                  color: const Color.fromRGBO(255, 249, 240, 0.8),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 24,
                        top: 48,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go('/login');
                            }
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.6)),
                              borderRadius: BorderRadius.circular(9999), // full circle
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.chevron_left, color: Color(0xFF333333)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Footer Fixed Button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer( // Let pointer ignore the gradient part, only catch button
              ignoring: false,
              child: Container(
                height: 154,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.fromRGBO(255, 249, 240, 0.0),
                      Color(0xFFFFF9F0),
                    ],
                    stops: [0.0, 0.4],
                  ),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.only(top: 24),
                child: GestureDetector(
                  onTapDown: (_) => setState(() => _isButtonPressed = true),
                  onTapUp: (_) {
                    setState(() => _isButtonPressed = false);
                    _submitSetup();
                  },
                  onTapCancel: () => setState(() => _isButtonPressed = false),
                  child: AnimatedScale(
                    scale: _isButtonPressed ? 0.98 : 1.0,
                    duration: const Duration(milliseconds: 100),
                    child: Container(
                      height: 58,
                      margin: const EdgeInsets.symmetric(horizontal: 32), // full width minus 64 (32+32)
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
                      child: _isLoading 
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            'ANALYZE MY FINANCES',
                            style: GoogleFonts.inter( // Inter instead of Geist as discussed earlier
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              letterSpacing: 2.4,
                              color: Colors.white,
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
}
