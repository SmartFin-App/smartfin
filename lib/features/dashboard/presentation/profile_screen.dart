import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/core/network/dio_client.dart';
import 'package:smart_fin/widgets/bottom_nav_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _notificationsEnabled = true;
  int _currentIncome = 0;
  int _budgetLimit = 0;
  int _monthlyIncome = 0;
  bool _isSavingIncome = false;
  final TextEditingController _incomeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadIncome();
  }

  @override
  void dispose() {
    _incomeController.dispose();
    super.dispose();
  }

  Future<void> _loadIncome() async {
    final prefs = await SharedPreferences.getInstance();
    final income = prefs.getInt('user_income_amount') ?? 0;
    final budget = prefs.getInt('user_budget_limit') ?? 0;
    if (mounted) {
      setState(() {
        _currentIncome = income;
        _budgetLimit = budget;
        _monthlyIncome = income;
      });
    }
  }

  Future<void> _showIncomeSheet() async {
    _incomeController.text =
        _currentIncome > 0 ? _currentIncome.toString() : '';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle pill
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAE2D6),
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  'Monthly Income',
                  style: GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    color: const Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Used to calculate your budget and savings rate.',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: const Color(0xFF9E9E9E),
                  ),
                ),
                const SizedBox(height: 24),

                // Amount input
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF9F0),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: const Color.fromRGBO(234, 226, 214, 0.8)),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        '฿',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                          color: const Color(0xFFFF9F29),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _incomeController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          autofocus: true,
                          style: GoogleFonts.bricolageGrotesque(
                            fontWeight: FontWeight.w700,
                            fontSize: 28,
                            color: const Color(0xFF333333),
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: '0',
                            hintStyle: GoogleFonts.bricolageGrotesque(
                              fontWeight: FontWeight.w700,
                              fontSize: 28,
                              color: const Color.fromRGBO(158, 158, 158, 0.4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _isSavingIncome
                        ? null
                        : () async {
                            final raw = _incomeController.text.trim();
                            final amount = int.tryParse(raw) ?? 0;
                            if (amount <= 0) return;

                            setSheetState(
                                () => _isSavingIncome = true);

                            try {
                              final uid = FirebaseAuth
                                      .instance.currentUser?.uid ??
                                  '';
                              await DioClient.dio.patch(
                                '/api/users/$uid',
                                data: {'monthly_income': amount},
                              );

                              // Sync local prefs
                              final prefs = await SharedPreferences
                                  .getInstance();
                              await prefs.setBool('income_set', true);
                              await prefs.setInt(
                                  'user_income_amount', amount);

                              if (mounted) {
                                setState(
                                    () => _currentIncome = amount);
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text(
                                    'Income updated to ฿${amount.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}',
                                    style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  backgroundColor:
                                      const Color(0xFF4CAF50),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ));
                              }
                            } on DioException catch (e) {
                              setSheetState(
                                  () => _isSavingIncome = false);
                              if (mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                  content: Text(
                                      'Failed to save: ${e.message}'),
                                  backgroundColor:
                                      const Color(0xFFEF4444),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ));
                              }
                            } finally {
                              if (mounted) {
                                setSheetState(
                                    () => _isSavingIncome = false);
                              }
                            }
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9F29),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: _isSavingIncome
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Save Income',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Future<void> _showBudgetEditor() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetEditorSheet(
        currentBudget: _budgetLimit,
        monthlyIncome: _monthlyIncome,
        scaffoldContext: context,
      ),
    );
    if (result != null && mounted) {
      setState(() => _budgetLimit = result);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Budget updated! 🐾',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF4CAF50),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "Log Out",
          style: GoogleFonts.bricolageGrotesque(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: const Color(0xFF333333),
          ),
        ),
        content: Text(
          "Are you sure you want to log out?",
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: const Color(0xFF9E9E9E),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              "Cancel",
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF9E9E9E),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/login');
            },
            child: Text(
              "Log Out",
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: const Color(0xFFEF4444),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesRow({
    required IconData icon,
    required String label,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(240, 235, 225, 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: const Color.fromRGBO(51, 51, 51, 0.6)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.inter( // fallback to Inter for strong legibility
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: const Color(0xFF333333),
                ),
              ),
            ),
            trailing,
          ],
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
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(top: 130, bottom: 120),
            child: Column(
              children: [
                // Section 1 - User Info
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.5), width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white, width: 4),
                                image: const DecorationImage(
                                  image: AssetImage('assets/images/lucky_cat.png'),
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.medium,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: -8,
                            right: -8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9F29),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))
                                ],
                              ),
                              child: Text(
                                "Lvl 12",
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        FirebaseAuth.instance.currentUser?.displayName ?? 'User',
                        style: GoogleFonts.bricolageGrotesque(
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                          color: const Color(0xFF333333),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "SmartFin Member since Jan 2024",
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          color: const Color(0xFF9E9E9E),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Section 2 - Wellness Score Card
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.4)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color.fromRGBO(255, 159, 41, 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color.fromRGBO(255, 159, 41, 0.1)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Image.asset('assets/images/lucky_cat.png', fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Wellness Score",
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: const Color(0xFF333333),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: const Color.fromRGBO(240, 235, 225, 0.6),
                                        borderRadius: BorderRadius.circular(9999),
                                      ),
                                      alignment: Alignment.centerLeft,
                                      child: FractionallySizedBox(
                                        widthFactor: 0.94,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFF9F29),
                                            borderRadius: BorderRadius.circular(9999),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "94%",
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10,
                                      color: const Color(0xFFFF9F29),
                                    ),
                                  )
                                ],
                              )
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Section 3 - Preferences
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          "PREFERENCES",
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                            letterSpacing: 2,
                            color: const Color(0xFF9E9E9E),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                       Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.4)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Column(
                            children: [
                              _buildPreferencesRow(
                                icon: Icons.account_balance_wallet_outlined,
                                label: 'Monthly Income',
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _currentIncome > 0
                                          ? '฿${_currentIncome.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}'
                                          : 'Not set',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: _currentIncome > 0
                                            ? const Color(0xFFFF9F29)
                                            : const Color(0xFF9E9E9E),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.chevron_right, size: 18, color: Color.fromRGBO(158, 158, 158, 0.5)),
                                  ],
                                ),
                                onTap: _showIncomeSheet,
                              ),
                              Divider(height: 1, thickness: 1, color: const Color.fromRGBO(234, 226, 214, 0.3)),
                              _buildPreferencesRow(
                                icon: Icons.person_outline,
                                label: 'Account Settings',
                                trailing: const Icon(Icons.chevron_right, size: 18, color: Color.fromRGBO(158, 158, 158, 0.5)),
                                onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account Settings coming soon'))),
                              ),
                              Divider(height: 1, thickness: 1, color: const Color.fromRGBO(234, 226, 214, 0.3)),
                              _buildPreferencesRow(
                                icon: Icons.account_balance_outlined,
                                label: 'Monthly Budget',
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color.fromRGBO(255, 159, 41, 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _budgetLimit > 0
                                        ? '฿${_budgetLimit.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}'
                                        : 'Not set',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                      color: const Color(0xFFFF9F29),
                                    ),
                                  ),
                                ),
                                onTap: _showBudgetEditor,
                              ),
                              Divider(height: 1, thickness: 1, color: const Color.fromRGBO(234, 226, 214, 0.3)),
                              _buildPreferencesRow(
                                icon: Icons.shield_outlined,
                                label: 'Security & Privacy',
                                trailing: const Icon(Icons.chevron_right, size: 18, color: Color.fromRGBO(158, 158, 158, 0.5)),
                                onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Security & Privacy coming soon'))),
                              ),
                              Divider(height: 1, thickness: 1, color: const Color.fromRGBO(234, 226, 214, 0.3)),
                              _buildPreferencesRow(
                                icon: Icons.notifications_outlined,
                                label: 'Notifications',
                                trailing: Switch(
                                  value: _notificationsEnabled,
                                  activeColor: const Color(0xFFFF9F29),
                                  onChanged: (val) {
                                    setState(() {
                                      _notificationsEnabled = val;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // Log Out Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: GestureDetector(
                    onTap: _showLogoutDialog,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color.fromRGBO(239, 68, 68, 0.1)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.logout, size: 18, color: Color(0xFFEF4444)),
                          const SizedBox(width: 8),
                          Text(
                            "Log Out",
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: const Color(0xFFEF4444),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),

          // Sticky Header Layers
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                child: Container(
                  color: const Color.fromRGBO(255, 249, 240, 0.8),
                  padding: const EdgeInsets.only(left: 24, right: 24, top: 48, bottom: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => context.go('/home'),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.6)),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
                            ],
                          ),
                          child: const Icon(Icons.chevron_left, size: 22, color: Color.fromRGBO(51, 51, 51, 0.7)),
                        ),
                      ),
                      Text(
                        "Profile",
                        style: GoogleFonts.bricolageGrotesque(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                          color: const Color(0xFF333333),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings coming soon')));
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.6)),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
                            ],
                          ),
                          child: const Icon(Icons.settings_outlined, size: 22, color: Color.fromRGBO(51, 51, 51, 0.7)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom Nav
          const SmartFinBottomNav(currentIndex: 3, showFab: false),
        ],
      ),
    );
  }
}

// ── Budget Editor Bottom Sheet ────────────────────────────────────────────────

class _BudgetEditorSheet extends StatefulWidget {
  final int currentBudget;
  final int monthlyIncome;
  final BuildContext scaffoldContext;

  const _BudgetEditorSheet({
    required this.currentBudget,
    required this.monthlyIncome,
    required this.scaffoldContext,
  });

  @override
  State<_BudgetEditorSheet> createState() => _BudgetEditorSheetState();
}

class _BudgetEditorSheetState extends State<_BudgetEditorSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _cursorController;
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    if (widget.currentBudget > 0) {
      _amountController.text = widget.currentBudget.toString();
    }
    _amountController.addListener(() => setState(() {}));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _cursorController.dispose();
    _amountController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _formattedAmount {
    final clean = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.isEmpty) return '0';
    return clean.replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(widget.scaffoldContext).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _saveBudget() async {
    final raw = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final amount = int.tryParse(raw) ?? 0;

    if (amount <= 0) {
      _showError('Please enter a budget amount');
      return;
    }
    if (widget.monthlyIncome > 0 && amount >= widget.monthlyIncome) {
      final formatted = widget.monthlyIncome
          .toString()
          .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
      _showError('Budget must be less than your monthly income (฿$formatted)');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      await DioClient.dio.put('/api/users/$uid', data: {'budget_limit': amount});

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('user_budget_limit', amount);

      if (mounted) Navigator.pop(context, amount);
    } on DioException catch (e) {
      _showError('Failed to save: ${e.message}');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final incomeFormatted = widget.monthlyIncome > 0
        ? '฿${widget.monthlyIncome.toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}'
        : null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          // Sheet card
          Container(
            margin: const EdgeInsets.only(top: 40),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
            ),
            padding: const EdgeInsets.fromLTRB(32, 56, 32, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Set Monthly Budget',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    color: const Color(0xFF333333),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  incomeFormatted != null
                      ? 'Your monthly income is $incomeFormatted. Set how much you want to allow yourself to spend.'
                      : 'Set how much you want to allow yourself to spend each month.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    height: 1.5,
                    color: const Color(0xFF9E9E9E),
                  ),
                ),
                const SizedBox(height: 40),

                // Amount display with blinking cursor
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '฿ ',
                          style: GoogleFonts.bricolageGrotesque(
                            fontWeight: FontWeight.w800,
                            fontSize: 36,
                            color: const Color(0xFFFF9F29),
                          ),
                        ),
                        Text(
                          _formattedAmount,
                          style: GoogleFonts.bricolageGrotesque(
                            fontWeight: FontWeight.w800,
                            fontSize: 36,
                            color: const Color(0xFF333333),
                          ),
                        ),
                        const SizedBox(width: 4),
                        FadeTransition(
                          opacity: _cursorController,
                          child: Container(
                            width: 2,
                            height: 36,
                            color: const Color(0xFFFF9F29),
                          ),
                        ),
                      ],
                    ),
                    // Hidden auto-focused TextField
                    Positioned.fill(
                      child: TextField(
                        controller: _amountController,
                        focusNode: _focusNode,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        showCursor: false,
                        style: const TextStyle(color: Colors.transparent, fontSize: 1),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _isSaving ? null : _saveBudget,
                    child: Container(
                      height: 58,
                      alignment: Alignment.center,
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
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'SAVE BUDGET',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                letterSpacing: 2,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Maybe Later
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'MAYBE LATER',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 2,
                        color: const Color(0xFF9E9E9E),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Floating lucky cat
          Positioned(
            top: 0,
            child: Image.asset(
              'assets/images/lucky_cat.png',
              width: 80,
              height: 80,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ],
      ),
    );
  }
}
