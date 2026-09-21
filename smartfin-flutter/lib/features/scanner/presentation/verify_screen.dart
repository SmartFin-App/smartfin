import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:smart_fin/widgets/ui/ui.dart';
import 'package:smart_fin/features/transactions/data/transaction_repository_impl.dart';
import 'package:smart_fin/features/scanner/services/gallery_watcher_service.dart';

class VerifyScreen extends StatefulWidget {
  final Map<String, dynamic>? extractedData;

  const VerifyScreen({super.key, this.extractedData});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final TextEditingController _merchantController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String _selectedCategory = 'Food';
  bool _isLoading = false;

  final List<Map<String, dynamic>> _categories = [
    {
      'label': 'Food',
      'icon': Icons.restaurant_outlined,
      'color': const Color(0xFFFF9F29),
    },
    {
      'label': 'Transport',
      'icon': Icons.directions_car_outlined,
      'color': const Color(0xFF2563EB),
    },
    {
      'label': 'Entertainment',
      'icon': Icons.movie_outlined,
      'color': const Color(0xFF7C3AED),
    },
    {
      'label': 'Shopping',
      'icon': Icons.shopping_bag_outlined,
      'color': const Color(0xFFDB2777),
    },
    {
      'label': 'Health',
      'icon': Icons.favorite_outline,
      'color': const Color(0xFFDC2626),
    },
    {
      'label': 'Groceries',
      'icon': Icons.local_grocery_store_outlined,
      'color': const Color(0xFF65A30D),
    },
    {
      'label': 'Bills',
      'icon': Icons.receipt_outlined,
      'color': const Color(0xFF0D9488),
    },
    {
      'label': 'Other',
      'icon': Icons.add_circle_outline,
      'color': const Color(0xFF9E9E9E),
    },
  ];

  /// Brings a model-extracted date back into a plausible range. Thai slips are often
  /// printed in the Buddhist era (543 years ahead), which is recoverable; anything
  /// else out of range falls back to today rather than being saved as-is.
  DateTime _clampExtractedDate(DateTime parsed) {
    var date = parsed;
    if (date.year > 2400) {
      date = DateTime(date.year - 543, date.month, date.day);
    }
    final now = DateTime.now();
    if (date.isAfter(now) || date.year < 2000) {
      return now;
    }
    return date;
  }

  @override
  void initState() {
    super.initState();
    final data = widget.extractedData;
    if (data != null) {
      _merchantController.text = data['merchant'] as String? ?? '';
      _amountController.text = (data['amount'] ?? 0).toString();

      // Parse date string. The value is model-extracted, so it can be a Buddhist-era
      // year (2569) or otherwise out of range — which would both crash the date picker
      // (initialDate after lastDate) and put the expense outside every month window.
      final dateStr = data['date'] as String?;
      if (dateStr != null) {
        try {
          _selectedDate = _clampExtractedDate(DateTime.parse(dateStr));
        } catch (_) {
          _selectedDate = DateTime.now();
        }
      }

      // Pre-select category if backend returns one
      final cat = data['category'] as String?;
      if (cat != null && _categories.any((c) => c['label'] as String == cat)) {
        _selectedCategory = cat;
      }
    }
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  void _toast(String message, {bool error = false}) =>
      showAppToast(context, message, error: error);

  Future<void> _saveTransaction() async {
    if (_isLoading) return;
    final merchant = _merchantController.text.trim();
    final amount = int.tryParse(
      _amountController.text.trim().replaceAll(',', ''),
    );

    if (merchant.isEmpty) {
      _toast('Please enter a merchant name', error: true);
      return;
    }
    if (amount == null || amount <= 0) {
      _toast('Please enter a valid amount', error: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final result = await TransactionRepositoryImpl().createTransaction(
        userID: uid,
        merchant: merchant,
        amount: amount,
        type: 'expense',
        category: _selectedCategory,
        source: 'scanner',
        date: _selectedDate,
      );

      if (!mounted) return;

      if (result.success) {
        // Only now is it safe to stop the watcher re-offering this slip.
        final assetId = widget.extractedData?['asset_id'] as String?;
        if (assetId != null) {
          await GalleryWatcherService().markSlipAsProcessed(assetId);
        }
        if (!mounted) return;
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

  // ── UI helpers ────────────────────────────────────────────────────────────

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.xs, bottom: AppSpacing.sm),
    child: Text(
      text,
      style: AppTextStyles.label.copyWith(color: AppColors.textSecondary),
    ),
  );

  // ── Build ─────────────────────────────────────────────────────────────────

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
                // Always ask for a check. The model's confidence score is not
                // shown: in the slip evaluation it was 0.98 on right and wrong
                // scans alike, so a "Great scan!" message could stop users from
                // catching a misread merchant or an invented date.
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.fact_check_outlined,
                        size: 20,
                        color: AppColors.primaryText,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'Check what was read from your slip before saving.',
                          style: AppTextStyles.body.copyWith(
                            color: AppColors.primaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // ── Merchant ────────────────────────────────────────────
                _fieldLabel('Merchant'),
                TextFormField(
                  controller: _merchantController,
                  textCapitalization: TextCapitalization.words,
                  style: AppTextStyles.body,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Big C Supermarket',
                    prefixIcon: Icon(
                      Icons.storefront_outlined,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // ── Amount ──────────────────────────────────────────────
                _fieldLabel('Amount'),
                TextFormField(
                  controller: _amountController,
                  // Whole baht only: money is integer ฿.
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: AppTextStyles.body,
                  decoration: InputDecoration(
                    hintText: '0',
                    // An icon rather than prefixText, which only shows once
                    // the field is focused.
                    prefixIcon: SizedBox(
                      width: 48,
                      child: Center(
                        child: Text(
                          '฿',
                          style: AppTextStyles.bodyStrong
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // ── Date ────────────────────────────────────────────────
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
                    title: DateFormat('d MMM yyyy').format(_selectedDate),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textMuted,
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                      }
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // ── Category ────────────────────────────────────────────
                _fieldLabel('Category'),
                GridView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisExtent: 60,
                  ),
                  itemCount: _categories.length,
                  itemBuilder: (context, i) {
                    final cat = _categories[i];
                    final label = cat['label'] as String;
                    return CategoryTile(
                      label: label,
                      icon: cat['icon'] as IconData,
                      color: cat['color'] as Color,
                      selected: _selectedCategory == label,
                      onTap: () => setState(() => _selectedCategory = label),
                    );
                  },
                ),
              ],
            ),
          ),

          SubpageHeader(
            title: 'Verify receipt',
            onBack: () => context.go('/scanner'),
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
