import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:smart_fin/widgets/ui/ui.dart';
import 'package:smart_fin/features/transactions/data/transaction_repository_impl.dart';
import 'package:smart_fin/features/scanner/services/gallery_watcher_service.dart';

/// One person's part of a slip shared evenly, to the nearest whole baht:
/// money is integer ฿, so ฿1,000 between three is ฿333.
int evenShare(int total, int people) {
  if (total <= 0 || people <= 0) return 0;
  return (total + people ~/ 2) ~/ people;
}

/// What the user decided about a slip that matches an expense they already have.
enum DuplicateChoice { saveAnyway, skip }

String _duplicateSourceLabel(String? source) {
  switch (source) {
    case 'subscription':
      return 'Bill marked paid';
    case 'scanner':
      return 'Scanned slip';
    case 'coach_agent':
      return 'AI Coach';
    default:
      return 'Entered manually';
  }
}

/// Warns that [matches] may already record this slip's payment — a bill marked
/// paid, or the same slip scanned earlier. It asks rather than blocks, because
/// two real payments can share an amount. Returns null when dismissed.
Future<DuplicateChoice?> showPossibleDuplicateDialog(
  BuildContext context,
  List<Map<String, dynamic>> matches,
) {
  return showDialog<DuplicateChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      // Up to three matches: scroll rather than overflow on a small phone.
      scrollable: true,
      title: const Text('Already added?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            matches.length == 1
                ? 'This slip matches an expense in your history:'
                : 'This slip matches expenses in your history:',
            style: AppTextStyles.body,
          ),
          for (final tx in matches) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              tx['merchant'] as String? ?? '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyStrong,
            ),
            Text(
              [
                tx['formatted_amount'] as String? ?? '',
                tx['formatted_date'] as String? ?? '',
                _duplicateSourceLabel(tx['source'] as String?),
              ].where((part) => part.isNotEmpty).join(' · '),
              style: AppTextStyles.caption,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, DuplicateChoice.skip),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
          ),
          child: const Text('Skip this slip'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, DuplicateChoice.saveAnyway),
          child: const Text('Save anyway'),
        ),
      ],
    ),
  );
}

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

  // Splitting: the slip was paid for a group, and only the user's share is
  // their spending. The amount field then holds the slip total.
  static const int _maxSplitPeople = 100;
  final TextEditingController _shareController = TextEditingController();
  bool _isSplit = false;
  int _splitPeople = 2;

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
    _amountController.addListener(_fillEvenShare);
  }

  int? get _enteredTotal =>
      int.tryParse(_amountController.text.trim().replaceAll(',', ''));

  /// Refills the share whenever the total or the head count changes. A share
  /// typed by hand (an uneven split) stays until one of those changes again.
  void _fillEvenShare() {
    if (!_isSplit) return;
    final share = evenShare(_enteredTotal ?? 0, _splitPeople);
    _shareController.text = share > 0 ? share.toString() : '';
  }

  void _setSplit(bool on) {
    setState(() => _isSplit = on);
    _fillEvenShare();
  }

  void _setSplitPeople(int people) {
    if (people < 2 || people > _maxSplitPeople) return;
    setState(() => _splitPeople = people);
    _fillEvenShare();
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _amountController.dispose();
    _shareController.dispose();
    super.dispose();
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  void _toast(String message, {bool error = false}) =>
      showAppToast(context, message, error: error);

  Future<void> _markSlipProcessed() async {
    final assetId = widget.extractedData?['asset_id'] as String?;
    if (assetId != null) {
      await GalleryWatcherService().markSlipAsProcessed(assetId);
    }
  }

  Future<void> _saveTransaction() async {
    if (_isLoading) return;
    final merchant = _merchantController.text.trim();
    final total = _enteredTotal;

    if (merchant.isEmpty) {
      _toast('Please enter a merchant name', error: true);
      return;
    }
    if (total == null || total <= 0) {
      _toast('Please enter a valid amount', error: true);
      return;
    }

    // What is saved as spending: the whole slip, or only the user's share.
    var amount = total;
    if (_isSplit) {
      final share = int.tryParse(_shareController.text.trim());
      if (share == null || share <= 0) {
        _toast('Please enter your share', error: true);
        return;
      }
      if (share > total) {
        _toast("Your share can't be more than the slip total", error: true);
        return;
      }
      amount = share;
    }

    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final repository = TransactionRepositoryImpl();

      // The payment may already be recorded: a bill marked paid, or this slip
      // scanned before. Checked against the slip total, which is what a split
      // slip was saved from. A failed check never holds up a save.
      final existing = await repository.findPossibleDuplicates(
        userID: uid,
        amount: total,
        date: _selectedDate,
      );
      if (!mounted) return;
      final matches = existing.data ?? const <Map<String, dynamic>>[];
      if (existing.success && matches.isNotEmpty) {
        final choice = await showPossibleDuplicateDialog(context, matches);
        if (!mounted || choice == null) return;
        if (choice == DuplicateChoice.skip) {
          // Handled, so Auto-Detect stops offering it.
          await _markSlipProcessed();
          if (!mounted) return;
          _toast('Slip skipped');
          context.go('/home');
          return;
        }
      }

      final result = await repository.createTransaction(
        userID: uid,
        merchant: merchant,
        amount: amount,
        type: 'expense',
        category: _selectedCategory,
        source: 'scanner',
        date: _selectedDate,
        splitTotal: _isSplit ? total : null,
        splitPeople: _isSplit ? _splitPeople : null,
      );

      if (!mounted) return;

      if (result.success) {
        // Only now is it safe to stop the watcher re-offering this slip.
        await _markSlipProcessed();
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

  Widget _stepButton(IconData icon, String label, VoidCallback? onPressed) =>
      IconButton(
        onPressed: onPressed,
        tooltip: label,
        icon: Icon(icon, size: 22),
        color: AppColors.primaryText,
        disabledColor: AppColors.textMuted,
      );

  /// The split switch and, once on, the head count and the user's share.
  List<Widget> _buildSplit() {
    return [
      AppCard(
        flat: true,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            ListRow(
              leading: const Icon(
                Icons.group_outlined,
                size: 20,
                color: AppColors.textSecondary,
              ),
              title: 'Split with others',
              subtitle: 'Save only your share as spending',
              trailing: Switch(value: _isSplit, onChanged: _setSplit),
              onTap: () => _setSplit(!_isSplit),
            ),
            if (_isSplit) ...[
              ListRow.divider(indent: AppSpacing.lg),
              ListRow(
                title: 'People sharing',
                subtitle: 'Including you',
                padding: const EdgeInsets.only(
                  left: AppSpacing.lg,
                  right: AppSpacing.xs,
                  top: AppSpacing.xs,
                  bottom: AppSpacing.xs,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _stepButton(
                      Icons.remove_circle_outline_rounded,
                      'Fewer people',
                      _splitPeople > 2
                          ? () => _setSplitPeople(_splitPeople - 1)
                          : null,
                    ),
                    SizedBox(
                      width: 28,
                      child: Text(
                        '$_splitPeople',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyStrong,
                      ),
                    ),
                    _stepButton(
                      Icons.add_circle_outline_rounded,
                      'More people',
                      _splitPeople < _maxSplitPeople
                          ? () => _setSplitPeople(_splitPeople + 1)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      if (_isSplit) ...[
        const SizedBox(height: AppSpacing.xl),
        _fieldLabel('Your share'),
        TextFormField(
          controller: _shareController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: AppTextStyles.body,
          decoration: InputDecoration(
            hintText: '0',
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
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            top: AppSpacing.sm,
          ),
          child: Text(
            'Split evenly to the nearest baht. Change it if you paid a '
            'different share.',
            style: AppTextStyles.caption,
          ),
        ),
      ],
    ];
  }

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
                _fieldLabel(_isSplit ? 'Slip total' : 'Amount'),
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
                const SizedBox(height: AppSpacing.md),
                ..._buildSplit(),
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
