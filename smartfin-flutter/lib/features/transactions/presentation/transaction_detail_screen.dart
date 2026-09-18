import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:smart_fin/constants/color_style.dart';
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
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  static const List<String> _expenseCategories = [
    'Food', 'Transport', 'Shopping', 'Bills', 'Groceries', 'Health', 'Entertainment', 'Other',
  ];
  static const List<String> _incomeCategories = ['Salary', 'Gifts', 'Refunds', 'Other'];

  static const Map<String, ({IconData icon, Color color})> _categoryStyle = {
    'Food':          (icon: Icons.restaurant_outlined,          color: Color(0xFFFF9F29)),
    'Transport':     (icon: Icons.directions_car_outlined,      color: Color(0xFF2563EB)),
    'Entertainment': (icon: Icons.movie_outlined,               color: Color(0xFF7C3AED)),
    'Shopping':      (icon: Icons.shopping_bag_outlined,        color: Color(0xFFDB2777)),
    'Health':        (icon: Icons.favorite_outline,             color: Color(0xFFDC2626)),
    'Groceries':     (icon: Icons.local_grocery_store_outlined, color: Color(0xFF65A30D)),
    'Bills':         (icon: Icons.receipt_outlined,             color: Color(0xFF0D9488)),
    'Salary':        (icon: Icons.account_balance_wallet_outlined, color: Color(0xFFFF9F29)),
    'Gifts':         (icon: Icons.card_giftcard_outlined,       color: Color(0xFF4A90E2)),
    'Refunds':       (icon: Icons.local_offer_outlined,         color: Color(0xFF4CAF50)),
    'Other':         (icon: Icons.add_circle_outline,           color: Color(0xFF9E9E9E)),
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      backgroundColor: error ? const Color(0xFFEF4444) : const Color(0xFF4CAF50),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

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

    final isIncome = (tx['type'] as String?) == 'income';
    final merchantController =
        TextEditingController(text: tx['merchant'] as String? ?? '');
    final amountController =
        TextEditingController(text: ((tx['amount'] as num?) ?? 0).round().toString());
    String category = tx['category'] as String? ?? 'Other';
    DateTime date = _date ?? DateTime.now();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final categories = isIncome ? _incomeCategories : _expenseCategories;
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAE2D6),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Edit transaction',
                    style: GoogleFonts.bricolageGrotesque(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: const Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: merchantController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _fieldDecoration('Merchant'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: _fieldDecoration('Amount in ฿'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'CATEGORY',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                      letterSpacing: 2,
                      color: const Color(0xFF9E9E9E),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: categories.map((c) {
                      final selected = c == category;
                      return GestureDetector(
                        onTap: () => setSheet(() => category = c),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color.fromRGBO(255, 159, 41, 0.08)
                                : Colors.white,
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFFFF9F29)
                                  : const Color(0xFFEAE2D6),
                              width: selected ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: Text(
                            c,
                            style: GoogleFonts.inter(
                              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 13,
                              color: selected
                                  ? const Color(0xFFFF9F29)
                                  : const Color(0xFF333333),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setSheet(() => date = picked);
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(240, 235, 225, 0.35),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined,
                              size: 17, color: Color(0xFF9E9E9E)),
                          const SizedBox(width: 12),
                          Text('Date',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: const Color(0xFF9E9E9E))),
                          const Spacer(),
                          Text(
                            DateFormat('d MMM yyyy').format(date),
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: const Color(0xFFFF9F29)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9F29),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9999)),
                      ),
                      onPressed: () {
                        final amount = int.tryParse(amountController.text.trim()) ?? 0;
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
                      child: Text(
                        'SAVE CHANGES',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
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
      _toast('Transaction updated');
      await _load();
    } else {
      _toast(res.error ?? 'Could not save changes', error: true);
    }
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600, fontSize: 13, color: const Color(0xFF9E9E9E)),
        filled: true,
        fillColor: const Color.fromRGBO(240, 235, 225, 0.35),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );

  // ── Delete ──────────────────────────────────────────────────────────────────

  Future<void> _delete() async {
    if (_isBusy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete transaction?',
            style: GoogleFonts.bricolageGrotesque(
                fontWeight: FontWeight.w800,
                fontSize: 19,
                color: const Color(0xFFEF4444))),
        content: Text(
          'This removes it from your history and recalculates that month\'s totals.',
          style: GoogleFonts.inter(
              fontWeight: FontWeight.w500, fontSize: 14, color: const Color(0xFF9E9E9E)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, color: const Color(0xFF9E9E9E))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, color: const Color(0xFFEF4444))),
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
      _toast('Transaction deleted');
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
              const Center(child: CircularProgressIndicator(color: Color(0xFFFF9F29)))
            else if (_error != null)
              _buildError()
            else
              _buildContent(),
            _buildHeader(),
            if (_isBusy)
              Positioned.fill(
                child: Container(
                  color: const Color.fromRGBO(255, 249, 240, 0.6),
                  child: const Center(
                      child: CircularProgressIndicator(color: Color(0xFFFF9F29))),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 32, color: Color(0xFF9E9E9E)),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textDark),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: _load,
              child: Text('Try again',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, color: const Color(0xFFFF9F29))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final tx = _tx!;
    final isIncome = (tx['type'] as String?) == 'income';
    final category = tx['category'] as String? ?? 'Other';
    final style = _categoryStyle[category] ?? _categoryStyle['Other']!;
    final amount = (tx['amount'] as num?) ?? 0;
    final source = tx['source'] as String? ?? 'manual';

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.only(top: 130, bottom: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Headline amount
            Center(
              child: Column(
                children: [
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: style.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: style.color.withOpacity(0.25)),
                    ),
                    child: Icon(style.icon, color: style.color, size: 28),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${isIncome ? '+' : '−'} ${_baht(amount)}',
                    style: GoogleFonts.bricolageGrotesque(
                      fontWeight: FontWeight.w800,
                      fontSize: 38,
                      letterSpacing: -1,
                      color: isIncome ? const Color(0xFF4CAF50) : AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tx['merchant'] as String? ?? '-',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: const Color(0xFF9E9E9E)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.5)),
              ),
              child: Column(
                children: [
                  // No Type row: SmartFin records expenses only, so it
                  // could only ever say "Expense".
                  _row('Category', category),
                  _divider(),
                  _row(
                    'Date',
                    _date != null
                        ? DateFormat('EEEE, d MMMM yyyy').format(_date!)
                        : (tx['formatted_date'] as String? ?? '—'),
                  ),
                  _divider(),
                  _row('Added by', _sourceLabel(source)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9F29),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9999)),
                      ),
                      onPressed: _edit,
                      icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.white),
                      label: Text('Edit',
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: Colors.white)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 52,
                  width: 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color.fromRGBO(239, 68, 68, 0.35)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9999)),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: _delete,
                    child: const Icon(Icons.delete_outline,
                        size: 20, color: Color(0xFFEF4444)),
                  ),
                ),
              ],
            ),
          ],
        ),
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

  Widget _divider() => Divider(
      height: 1, thickness: 1, color: const Color.fromRGBO(234, 226, 214, 0.4));

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      child: Row(
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: const Color(0xFF9E9E9E))),
          const SizedBox(width: 16),
          // Expanded, not Spacer + Flexible: those split the spare width in
          // half, so short values sat mid-row instead of at the right edge.
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Positioned(
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
                  onTap: () => context.pop(_changed),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: const Color.fromRGBO(234, 226, 214, 0.6)),
                    ),
                    child: const Icon(Icons.chevron_left,
                        size: 22, color: Color.fromRGBO(51, 51, 51, 0.7)),
                  ),
                ),
                Text('Transaction',
                    style: GoogleFonts.bricolageGrotesque(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: const Color(0xFF333333))),
                const SizedBox(width: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
