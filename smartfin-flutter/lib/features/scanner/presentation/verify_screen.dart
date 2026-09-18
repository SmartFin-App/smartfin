import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:smart_fin/constants/color_style.dart';
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
    {'label': 'Food',          'icon': Icons.restaurant_outlined,          'color': const Color(0xFFFF9F29)},
    {'label': 'Transport',     'icon': Icons.directions_car_outlined,       'color': const Color(0xFF2563EB)},
    {'label': 'Entertainment', 'icon': Icons.movie_outlined,                'color': const Color(0xFF7C3AED)},
    {'label': 'Shopping',      'icon': Icons.shopping_bag_outlined,         'color': const Color(0xFFDB2777)},
    {'label': 'Health',        'icon': Icons.favorite_outline,              'color': const Color(0xFFDC2626)},
    {'label': 'Groceries',     'icon': Icons.local_grocery_store_outlined,  'color': const Color(0xFF65A30D)},
    {'label': 'Bills',         'icon': Icons.receipt_outlined,              'color': const Color(0xFF0D9488)},
    {'label': 'Other',         'icon': Icons.add_circle_outline,            'color': const Color(0xFF9E9E9E)},
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
      if (cat != null &&
          _categories.any((c) => c['label'] as String == cat)) {
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

  Future<void> _saveTransaction() async {
    final merchant = _merchantController.text.trim();
    final amountText = _amountController.text.trim().replaceAll(',', '');
    final amount = int.tryParse(amountText) ?? (double.tryParse(amountText)?.toInt());

    if (merchant.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a merchant name')),
      );
      return;
    }
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt saved!')),
        );
        context.go('/home');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error ?? 'Failed to save transaction.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
        fontWeight: FontWeight.w500,
        fontSize: 14,
        color: const Color.fromRGBO(158, 158, 158, 0.5),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color.fromRGBO(234, 226, 214, 0.6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFFF9F29)),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 1.5,
          color: const Color(0xFF9E9E9E),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Stack(
        children: [
          // ── Scrollable content ─────────────────────────────────────────
          SingleChildScrollView(
            padding: const EdgeInsets.only(top: 104, bottom: 120),
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Always ask for a check. The model's confidence score is not
                // shown: in the slip evaluation it was 0.98 on right and wrong
                // scans alike, so a "Great scan!" message could stop users from
                // catching a misread merchant or an invented date.
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  color: const Color(0xFFFF9F29).withValues(alpha: 0.1),
                  child: Text(
                    'Please check the details below before saving.',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: const Color(0xFFFF9F29),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Merchant field ──────────────────────────────────
                      _sectionLabel('MERCHANT / STORE'),
                      TextFormField(
                        controller: _merchantController,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: const Color(0xFF333333),
                        ),
                        decoration: _inputDecoration('e.g. Big C Supermarket'),
                      ),

                      const SizedBox(height: 24),

                      // ── Amount field ────────────────────────────────────
                      _sectionLabel('AMOUNT (฿)'),
                      TextFormField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: const Color(0xFF333333),
                        ),
                        decoration: _inputDecoration('0'),
                      ),

                      const SizedBox(height: 24),

                      // ── Date picker ─────────────────────────────────────
                      _sectionLabel('DATE'),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                            builder: (ctx, child) => Theme(
                              data: Theme.of(ctx).copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: Color(0xFFFF9F29),
                                ),
                              ),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            setState(() => _selectedDate = picked);
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: const Border.fromBorderSide(BorderSide(
                                color: Color.fromRGBO(234, 226, 214, 0.6))),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined,
                                  size: 16,
                                  color: Color.fromRGBO(158, 158, 158, 0.7)),
                              const SizedBox(width: 12),
                              Text(
                                DateFormat('MMM d, yyyy').format(_selectedDate),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: const Color(0xFF333333),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── Category grid ───────────────────────────────────
                      _sectionLabel('CATEGORY'),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: _categories.length,
                        itemBuilder: (context, i) {
                          final cat = _categories[i];
                          final label = cat['label'] as String;
                          final icon = cat['icon'] as IconData;
                          final color = cat['color'] as Color;
                          final isSelected = _selectedCategory == label;

                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedCategory = label),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? color.withOpacity(0.12)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? color
                                      : const Color.fromRGBO(234, 226, 214, 0.6),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(icon,
                                      size: 22,
                                      color: isSelected
                                          ? color
                                          : const Color.fromRGBO(
                                              51, 51, 51, 0.4)),
                                  const SizedBox(height: 6),
                                  Text(
                                    label,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      fontSize: 9,
                                      color: isSelected
                                          ? color
                                          : const Color.fromRGBO(
                                              51, 51, 51, 0.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Sticky glass header ────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(
                  color: const Color.fromRGBO(255, 249, 240, 0.85),
                  padding:
                      const EdgeInsets.only(top: 48, left: 24, right: 24, bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Back
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => context.go('/scanner'),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: const Color.fromRGBO(
                                        234, 226, 214, 0.6)),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.02),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2))
                                ],
                              ),
                              child: const Icon(Icons.chevron_left,
                                  size: 22,
                                  color: Color.fromRGBO(51, 51, 51, 0.7)),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'Verify Receipt',
                            style: GoogleFonts.bricolageGrotesque(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: const Color(0xFF333333),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Fixed footer Save button ───────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 249, 240, 0.95),
                border: const Border(
                    top: BorderSide(
                        color: Color.fromRGBO(234, 226, 214, 0.4))),
              ),
              child: GestureDetector(
                onTap: _isLoading ? null : _saveTransaction,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9F29),
                    borderRadius: BorderRadius.circular(9999),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF9F29).withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          'SAVE TRANSACTION',
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
          ),
        ],
      ),
    );
  }
}
