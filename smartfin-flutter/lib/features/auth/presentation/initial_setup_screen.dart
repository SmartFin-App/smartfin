import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_fin/widgets/ui/ui.dart';
import 'package:smart_fin/core/network/dio_client.dart';
import 'package:smart_fin/features/auth/data/auth_repository_impl.dart';
import 'package:smart_fin/widgets/smartfin_logo.dart';

class InitialSetupScreen extends StatefulWidget {
  const InitialSetupScreen({super.key});

  @override
  State<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends State<InitialSetupScreen>
    with TickerProviderStateMixin {
  String? selectedStatus;
  String? selectedHealth;
  final _nameController = TextEditingController();
  // Optional. SmartFin tracks spending, so the budget is the one figure worth
  // asking for up front; it used to be set silently to 70% of an income figure.
  final _budgetController = TextEditingController();
  bool _isLoading = false;

  late AnimationController _catController;
  late Animation<double> _catFade;
  late Animation<double> _catScale;

  late AnimationController _contentController;
  late Animation<double> _contentFade;
  late Animation<Offset> _contentSlide;

  @override
  void initState() {
    super.initState();

    // Cat Image Animation: fade-in zoom-in duration 700ms
    _catController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _catFade = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _catController, curve: Curves.easeOut));
    _catScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _catController, curve: Curves.easeOutBack),
    );

    // Content: slide-in from bottom fade-in duration 700ms delay 200ms
    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 900,
      ), // 200ms delay + 700ms duration
    );
    _contentFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _contentController,
        curve: const Interval(0.22, 1.0, curve: Curves.easeOut),
      ),
    );
    _contentSlide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _contentController,
            curve: const Interval(0.22, 1.0, curve: Curves.easeOutCubic),
          ),
        );

    _catController.forward();
    _contentController.forward();
  }

  @override
  void dispose() {
    _catController.dispose();
    _contentController.dispose();
    _nameController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  void _showError(String message) =>
      showAppToast(context, message, error: true);

  Future<void> _submitSetup() async {
    if (_isLoading) return;
    final name = _nameController.text.trim();
    if (name.isEmpty || selectedStatus == null || selectedHealth == null) {
      _showError('Please fill in your name and pick one of each');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No authenticated user found.');

      // Update Firebase display name
      await user.updateDisplayName(name);

      // Zero means "not set": the dashboard and the coach say so rather than
      // measuring spending against a limit the user never chose.
      final budgetLimit = int.tryParse(_budgetController.text.trim()) ?? 0;

      // Save to Go backend
      final repo = AuthRepositoryImpl();
      final result = await repo.createUser(
        firebaseUID: user.uid,
        name: name,
        email: user.email ?? '',
        photoURL: user.photoURL ?? '',
        currentStatus: selectedStatus!,
        financialHealth: selectedHealth!,
        budgetLimit: budgetLimit.toDouble(),
      );

      if (!result.success) {
        if (mounted) {
          _showError(result.error ?? 'Could not save your details.');
        }
        return;
      }

      // Persist locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('setup_complete', true);
      await prefs.setString('user_name', name);
      await prefs.setString('user_status', selectedStatus!);
      await prefs.setString('user_health', selectedHealth!);
      // setInt, not setDouble: these are read back with getInt, which throws a
      // TypeError on a stored double and left Profile showing ฿0.
      if (budgetLimit > 0) {
        await prefs.setInt('user_budget_limit', budgetLimit);
      }
      await prefs.setBool('onboarding_complete', true);

      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        _showError(
          DioClient.handleError(
            e is Exception ? e as dynamic : Exception(e.toString()),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm),
    child: Text(
      label,
      style: AppTextStyles.label.copyWith(color: AppColors.textSecondary),
    ),
  );

  Widget _statusCard({required String label, required IconData icon}) {
    final selected = label == selectedStatus;
    final radius = BorderRadius.circular(AppRadius.lg);
    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          decoration: BoxDecoration(
            color: selected
                ? Color.alphaBlend(
                    AppColors.primary.withValues(alpha: 0.12),
                    AppColors.white,
                  )
                : AppColors.white,
            borderRadius: radius,
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: () => setState(() => selectedStatus = label),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Column(
                  children: [
                    IconTile(
                      icon: icon,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      size: 44,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      label,
                      style: AppTextStyles.bodyStrong.copyWith(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                72,
                AppSpacing.xl,
                140,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FadeTransition(
                    opacity: _catFade,
                    child: ScaleTransition(
                      scale: _catScale,
                      child: Column(
                        children: [
                          const SmartFinLogo(fontSize: 32),
                          const SizedBox(height: AppSpacing.xl),
                          Text(
                            "Let's set you up",
                            textAlign: TextAlign.center,
                            style: AppTextStyles.title,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  FadeTransition(
                    opacity: _contentFade,
                    child: SlideTransition(
                      position: _contentSlide,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionLabel('Your name'),
                          TextField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            autofillHints: const [AutofillHints.givenName],
                            style: AppTextStyles.body,
                            decoration: const InputDecoration(
                              hintText: 'What should we call you?',
                              prefixIcon: Icon(
                                Icons.person_outline_rounded,
                                size: 20,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),

                          _sectionLabel('Monthly budget (optional)'),
                          TextField(
                            controller: _budgetController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(8),
                            ],
                            style: AppTextStyles.body,
                            decoration: InputDecoration(
                              hintText: 'e.g. 15000',
                              // An icon rather than prefixText, which only
                              // shows once the field is focused.
                              prefixIcon: SizedBox(
                                width: 48,
                                child: Center(
                                  child: Text(
                                    '฿',
                                    style: AppTextStyles.bodyStrong.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs,
                            ),
                            child: Text(
                              'How much you aim to spend each month. You can skip this and set it later in Profile.',
                              style: AppTextStyles.caption.copyWith(
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),

                          _sectionLabel('What do you do?'),
                          Row(
                            children: [
                              _statusCard(
                                label: 'Student',
                                icon: Icons.school_outlined,
                              ),
                              _statusCard(
                                label: 'Pro',
                                icon: Icons.work_outline,
                              ),
                              _statusCard(
                                label: 'Founder',
                                icon: Icons.rocket_launch_outlined,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),

                          _sectionLabel('How are your finances?'),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              for (final h in const [
                                'Debt-Free',
                                'Saving Up',
                                'Managing Debt',
                                'Paycheck to Paycheck',
                              ])
                                AppChip(
                                  label: h,
                                  selected: selectedHealth == h,
                                  onTap: () =>
                                      setState(() => selectedHealth = h),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              left: AppSpacing.screen,
              top: AppSpacing.sm,
              child: AppIconButton(
                icon: Icons.arrow_back_rounded,
                semanticLabel: 'Back',
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/login');
                  }
                },
              ),
            ),

            // ── Continue ───────────────────────────────────────────────
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.cream.withValues(alpha: 0),
                      AppColors.cream,
                    ],
                    stops: const [0, 0.35],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xxl,
                  AppSpacing.xl,
                  AppSpacing.lg,
                ),
                child: AppButton(
                  label: 'Get started',
                  expand: true,
                  loading: _isLoading,
                  onPressed: _submitSetup,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
