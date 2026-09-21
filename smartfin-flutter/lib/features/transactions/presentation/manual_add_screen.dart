import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:smart_fin/features/transactions/data/transaction_repository_impl.dart';
import 'package:smart_fin/widgets/ui/ui.dart';

class ManualAddScreen extends StatefulWidget {
  const ManualAddScreen({super.key});

  @override
  State<ManualAddScreen> createState() => _ManualAddScreenState();
}

class _ManualAddScreenState extends State<ManualAddScreen>
    with TickerProviderStateMixin {
  String? _selectedCategory;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _merchantController = TextEditingController();
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now();

  // Animations
  late AnimationController _amountAnimController;
  late Animation<double> _amountScale;
  late Animation<double> _amountFade;

  late AnimationController _gridAnimController;
  late Animation<Offset> _gridSlide;
  late Animation<double> _gridFade;

  @override
  void initState() {
    super.initState();

    // Amount Load Animation
    _amountAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _amountScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _amountAnimController, curve: Curves.easeOutBack),
    );
    _amountFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _amountAnimController, curve: Curves.easeOut),
    );

    _amountAnimController.forward();

    // Grid Slide Animation
    _gridAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _gridSlide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _gridAnimController,
            curve: Curves.easeOutCubic,
          ),
        );
    _gridFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _gridAnimController, curve: Curves.easeOut),
    );

    Future.delayed(
      const Duration(milliseconds: 100),
      () => _gridAnimController.forward(),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _amountAnimController.dispose();
    _gridAnimController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final checkDate = DateTime(date.year, date.month, date.day);

    if (checkDate == today) return "Today";
    if (checkDate == yesterday) return "Yesterday";
    return DateFormat('MMM d, yyyy').format(date);
  }

  void _toast(String message, {bool error = false}) =>
      showAppToast(context, message, error: error);

  Future<void> _saveTransaction() async {
    // The button is disabled while saving, and the backend has no idempotency
    // key, so this guard is what stops a second tap booking a second charge.
    if (_isLoading) return;

    final amount = int.tryParse(
      _amountController.text.trim().replaceAll(',', ''),
    );

    if (amount == null || amount <= 0) {
      _toast('Please enter an amount', error: true);
      return;
    }

    if (_merchantController.text.trim().isEmpty) {
      _toast('Please enter where you spent it', error: true);
      return;
    }

    if (_selectedCategory == null) {
      _toast('Please pick a category', error: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final result = await TransactionRepositoryImpl().createTransaction(
        userID: uid,
        merchant: _merchantController.text.trim(),
        amount: amount,
        type: 'expense',
        category: _selectedCategory!,
        source: 'manual',
        date: _selectedDate,
      );

      if (!mounted) return;

      if (result.success) {
        _toast('Expense saved');
        context.go('/home');
      } else {
        _toast(result.error ?? 'Could not save the expense', error: true);
      }
    } catch (e) {
      if (mounted) _toast('Error: $e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static const List<({String label, IconData icon, Color color})>
  _expenseCats = [
    (label: 'Food', icon: Icons.restaurant_outlined, color: Color(0xFFFF9F29)),
    (
      label: 'Transport',
      icon: Icons.directions_car_outlined,
      color: Color(0xFF2563EB),
    ),
    (
      label: 'Entertainment',
      icon: Icons.movie_outlined,
      color: Color(0xFF7C3AED),
    ),
    (
      label: 'Shopping',
      icon: Icons.shopping_bag_outlined,
      color: Color(0xFFDB2777),
    ),
    (label: 'Health', icon: Icons.favorite_outline, color: Color(0xFFDC2626)),
    (
      label: 'Groceries',
      icon: Icons.local_grocery_store_outlined,
      color: Color(0xFF65A30D),
    ),
    (label: 'Bills', icon: Icons.receipt_outlined, color: Color(0xFF0D9488)),
    (label: 'Other', icon: Icons.add_circle_outline, color: Color(0xFF9E9E9E)),
  ];

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm),
    child: Text(
      text,
      style: AppTextStyles.label.copyWith(color: AppColors.textSecondary),
    ),
  );

  Widget _categoryTile(({String label, IconData icon, Color color}) cat) =>
      CategoryTile(
        label: cat.label,
        icon: cat.icon,
        color: cat.color,
        selected: _selectedCategory == cat.label,
        onTap: () => setState(() => _selectedCategory = cat.label),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      // Expand, so what is pinned to the bottom stays there when the content
      // is shorter than the screen.
      body: Stack(
        fit: StackFit.expand,
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screen,
              SubpageHeader.contentTop,
              AppSpacing.screen,
              140,
            ),
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Amount ─────────────────────────────────────────────
                FadeTransition(
                  opacity: _amountFade,
                  child: ScaleTransition(
                    scale: _amountScale,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: AppSpacing.lg,
                        bottom: AppSpacing.xxl,
                      ),
                      child: Column(
                        children: [
                          Text('Amount', style: AppTextStyles.caption),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '฿',
                                style: AppTextStyles.display.copyWith(
                                  fontSize: 40,
                                  color: AppColors.primaryText,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              IntrinsicWidth(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minWidth: 60,
                                  ),
                                  child: TextField(
                                    controller: _amountController,
                                    autofocus: true,
                                    // Whole baht only: money is integer ฿.
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.display.copyWith(
                                      fontSize: 56,
                                    ),
                                    decoration: InputDecoration(
                                      filled: false,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      isCollapsed: true,
                                      hintText: '0',
                                      hintStyle: AppTextStyles.display.copyWith(
                                        fontSize: 56,
                                        color: AppColors.border,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Merchant ───────────────────────────────────────────
                _fieldLabel('Merchant'),
                TextField(
                  controller: _merchantController,
                  textCapitalization: TextCapitalization.words,
                  style: AppTextStyles.body,
                  decoration: const InputDecoration(
                    hintText: 'Where did you spend it?',
                    prefixIcon: Icon(
                      Icons.storefront_outlined,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // ── Date ───────────────────────────────────────────────
                _fieldLabel('Date'),
                AppCard(
                  flat: true,
                  padding: EdgeInsets.zero,
                  child: ListRow(
                    leading: const Icon(
                      Icons.calendar_today_rounded,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    title: _formatDate(_selectedDate),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textMuted,
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                      }
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // ── Category ───────────────────────────────────────────
                FadeTransition(
                  opacity: _gridFade,
                  child: SlideTransition(
                    position: _gridSlide,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _fieldLabel('Category'),
                        GridView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: AppSpacing.md,
                                mainAxisSpacing: AppSpacing.md,
                                mainAxisExtent: 60,
                              ),
                          itemCount: _expenseCats.length,
                          itemBuilder: (context, index) =>
                              _categoryTile(_expenseCats[index]),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          SubpageHeader(
            title: 'Add expense',
            onBack: () => context.go('/home'),
          ),

          // ── Save ─────────────────────────────────────────────────────
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
                AppSpacing.screen,
                AppSpacing.xxl,
                AppSpacing.screen,
                32,
              ),
              child: AppButton(
                label: 'Save expense',
                expand: true,
                loading: _isLoading,
                onPressed: _saveTransaction,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
