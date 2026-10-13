import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:smart_fin/widgets/ui/ui.dart';
import 'package:smart_fin/features/transactions/data/transaction_repository_impl.dart';

/// Full record for a single transaction, with edit and delete.
///
/// Both writes are scoped by the owner's Firebase UID — the API refuses a
/// single-transaction write that does not carry one, so the id alone is never
/// enough to change someone else's record.
class TransactionDetailScreen extends StatefulWidget {
  final String transactionID;

  const TransactionDetailScreen({super.key, required this.transactionID});

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  static const List<String> _expenseCategories = [
    'Food',
    'Transport',
    'Shopping',
    'Bills',
    'Groceries',
    'Health',
    'Entertainment',
    'Other',
  ];

  static const Map<String, ({IconData icon, Color color})> _categoryStyle = {
    'Food': (icon: Icons.restaurant_outlined, color: Color(0xFFFF9F29)),
    'Transport': (
      icon: Icons.directions_car_outlined,
      color: Color(0xFF2563EB),
    ),
    'Entertainment': (icon: Icons.movie_outlined, color: Color(0xFF7C3AED)),
    'Shopping': (icon: Icons.shopping_bag_outlined, color: Color(0xFFDB2777)),
    'Health': (icon: Icons.favorite_outline, color: Color(0xFFDC2626)),
    'Groceries': (
      icon: Icons.local_grocery_store_outlined,
      color: Color(0xFF65A30D),
    ),
    'Bills': (icon: Icons.receipt_outlined, color: Color(0xFF0D9488)),
    'Other': (icon: Icons.add_circle_outline, color: Color(0xFF9E9E9E)),
  };

  Map<String, dynamic>? _tx;
  bool _isLoading = true;
  bool _isBusy = false;
  String? _error;

  /// Set when anything is changed or removed, so the list can refresh on return.
  bool _changed = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    if (_uid.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'You need to be signed in to view this transaction.';
      });
      return;
    }

    final res = await TransactionRepositoryImpl().getTransactionById(
      transactionID: widget.transactionID,
      userID: _uid,
    );
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (res.success) {
        _tx = res.data;
      } else {
        _error = res.error ?? 'Could not load this transaction.';
      }
    });
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    showAppToast(context, message, error: error);
  }

  ({IconData icon, Color color}) _styleFor(String? category) =>
      _categoryStyle[category] ?? _categoryStyle['Other']!;

  String _baht(num amount) =>
      '฿${amount.round().toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}';

  DateTime? get _date {
    final raw = _tx?['date'] as String?;
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  // ── Edit ────────────────────────────────────────────────────────────────────

  Future<void> _edit() async {
    final tx = _tx;
    if (tx == null || _isBusy) return;

    final merchantController = TextEditingController(
      text: tx['merchant'] as String? ?? '',
    );
    final amountController = TextEditingController(
      text: ((tx['amount'] as num?) ?? 0).round().toString(),
    );
    String category = tx['category'] as String? ?? 'Other';
    DateTime date = _date ?? DateTime.now();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          const categories = _expenseCategories;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Edit expense', style: AppTextStyles.title),
                    const SizedBox(height: AppSpacing.xl),
                    TextField(
                      controller: merchantController,
                      textCapitalization: TextCapitalization.words,
                      style: AppTextStyles.body,
                      decoration: const InputDecoration(labelText: 'Merchant'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: AppTextStyles.body,
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        prefixText: '฿ ',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Category',
                      style: AppTextStyles.label.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: categories
                          .map(
                            (c) => AppChip(
                              label: c,
                              icon: _styleFor(c).icon,
                              selected: c == category,
                              onTap: () => setSheet(() => category = c),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppCard(
                      flat: true,
                      padding: EdgeInsets.zero,
                      child: ListRow(
                        leading: const Icon(
                          Icons.calendar_today_rounded,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                        title: 'Date',
                        trailing: Text(
                          DateFormat('d MMM yyyy').format(date),
                          style: AppTextStyles.label.copyWith(
                            color: AppColors.primaryText,
                          ),
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setSheet(() => date = picked);
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppButton(
                      label: 'Save changes',
                      expand: true,
                      onPressed: () {
                        final amount =
                            int.tryParse(amountController.text.trim()) ?? 0;
                        if (merchantController.text.trim().isEmpty) {
                          _toast('Merchant cannot be empty', error: true);
                          return;
                        }
                        if (amount <= 0) {
                          _toast('Amount must be greater than 0', error: true);
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (saved != true || !mounted) return;

    setState(() => _isBusy = true);
    final res = await TransactionRepositoryImpl().updateTransaction(
      transactionID: widget.transactionID,
      userID: _uid,
      merchant: merchantController.text.trim(),
      amount: int.tryParse(amountController.text.trim()),
      category: category,
      date: date,
    );
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (res.success) {
      _changed = true;
      _toast('Expense updated');
      await _load();
    } else {
      _toast(res.error ?? 'Could not save changes', error: true);
    }
  }

  // ── Delete ──────────────────────────────────────────────────────────────────

  Future<void> _delete() async {
    if (_isBusy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this expense?'),
        content: const Text(
          "It's removed from your history and that month's totals are recalculated.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isBusy = true);
    final res = await TransactionRepositoryImpl().deleteTransaction(
      transactionID: widget.transactionID,
      userID: _uid,
    );
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (res.success) {
      _toast('Expense deleted');
      context.pop(true);
    } else {
      _toast(res.error ?? 'Could not delete', error: true);
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.pop(_changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.cream,
        body: Stack(
          children: [
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              _buildError()
            else
              _buildContent(),
            SubpageHeader(
              title: 'Expense',
              onBack: () => context.pop(_changed),
            ),
            if (_isBusy)
              Positioned.fill(
                child: ColoredBox(
                  color: AppColors.cream.withValues(alpha: 0.6),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: StatusMessage(
        icon: Icons.receipt_long_rounded,
        title: "Couldn't open this expense",
        message: _error,
        action: AppButton.secondary(
          label: 'Try again',
          icon: Icons.refresh_rounded,
          onPressed: _load,
        ),
      ),
    );
  }

  Widget _buildContent() {
    final tx = _tx!;
    final category = tx['category'] as String? ?? 'Other';
    final style = _styleFor(category);
    final amount = (tx['amount'] as num?) ?? 0;
    final source = tx['source'] as String? ?? 'manual';
    // Present only when the slip was shared; amount is then the user's share.
    final splitTotal = (tx['split_total'] as num?) ?? 0;
    final splitPeople = (tx['split_people'] as num?)?.toInt() ?? 0;

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screen,
        SubpageHeader.contentTop,
        AppSpacing.screen,
        60,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Headline amount
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: IconTile(icon: style.icon, color: style.color, size: 64),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '−${_baht(amount)}',
            textAlign: TextAlign.center,
            style: AppTextStyles.display.copyWith(fontSize: 40),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            tx['merchant'] as String? ?? '-',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxl),

          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                // No Type row: SmartFin records expenses only, so it
                // could only ever say "Expense".
                _row('Category', category),
                const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
                _row(
                  'Date',
                  _date != null
                      ? DateFormat('EEEE, d MMMM yyyy').format(_date!)
                      : (tx['formatted_date'] as String? ?? '—'),
                ),
                const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
                _row('Added by', _sourceLabel(source)),
                if (splitTotal > 0 && splitPeople > 1) ...[
                  const Divider(
                    indent: AppSpacing.lg,
                    endIndent: AppSpacing.lg,
                  ),
                  _row(
                    'Split',
                    'Your share of ${_baht(splitTotal)} · $splitPeople people',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Edit',
                  icon: Icons.edit_outlined,
                  expand: true,
                  onPressed: _edit,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: BorderSide(
                      color: AppColors.danger.withValues(alpha: 0.35),
                    ),
                  ),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  label: const Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'scanner':
        return 'Scanned slip';
      case 'coach_agent':
        return 'AI Coach';
      case 'subscription':
        return 'Subscription';
      default:
        return 'Entered manually';
    }
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      child: Row(
        children: [
          Text(label, style: AppTextStyles.caption.copyWith(fontSize: 14)),
          const SizedBox(width: AppSpacing.lg),
          // Expanded, not Spacer + Flexible: those split the spare width in
          // half, so short values sat mid-row instead of at the right edge.
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTextStyles.bodyStrong,
            ),
          ),
        ],
      ),
    );
  }
}
