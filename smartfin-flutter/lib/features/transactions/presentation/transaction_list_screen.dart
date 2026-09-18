import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/widgets/bottom_nav_bar.dart';
import 'package:smart_fin/features/transactions/data/transaction_repository_impl.dart';

class TransactionListScreen extends StatefulWidget {
  /// Starting filters, set when another screen opens History for a specific
  /// slice — the dashboard's top-categories card passes type, category and
  /// month. All of them stay editable from the filter sheet.
  final String? initialType;
  final String? initialCategory;
  final String? initialMonth;

  const TransactionListScreen({
    super.key,
    this.initialType,
    this.initialCategory,
    this.initialMonth,
  });

  @override
  State<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends State<TransactionListScreen> {
  String _searchQuery = '';
  String? _filterType;
  String? _filterCategory;
  String? _filterMonth;
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Applied before the first load, so a pre-filtered open never flashes the
    // unfiltered list first.
    _filterType = _nonEmpty(widget.initialType);
    _filterCategory = _nonEmpty(widget.initialCategory);
    _filterMonth = _nonEmpty(widget.initialMonth);
    _loadTransactions();
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    // Filtering happens server-side so the month window matches the one the
    // summaries use; only the free-text search stays local.
    final result = await TransactionRepositoryImpl().getTransactions(
      userID: uid,
      type: _filterType,
      category: _filterCategory,
      month: _filterMonth,
    );

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _transactions = result.data ?? [];
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = result.error;
        _isLoading = false;
      });
    }
  }

  int get _activeFilterCount =>
      (_filterType != null ? 1 : 0) +
      (_filterCategory != null ? 1 : 0) +
      (_filterMonth != null ? 1 : 0);

  Future<void> _openDetail(Map<String, dynamic> tx) async {
    final id = tx['id'] as String?;
    if (id == null || id.isEmpty) return;
    // Detail returns true when the record was edited or deleted.
    final changed = await context.push<bool>('/transaction/$id');
    if (changed == true) await _loadTransactions();
  }

  Future<void> _showFilterSheet() async {
    String? type = _filterType;
    String? category = _filterCategory;
    String? month = _filterMonth;

    const categories = [
      'Food', 'Transport', 'Shopping', 'Bills', 'Groceries',
      'Health', 'Entertainment', 'Salary', 'Gifts', 'Refunds', 'Other',
    ];

    // Last six months, newest first.
    final now = DateTime.now();
    final months = List.generate(6, (i) {
      final d = DateTime(now.year, now.month - i, 1);
      return (
        value: '${d.year}-${d.month.toString().padLeft(2, '0')}',
        label: DateFormat('MMM yyyy').format(d),
      );
    });

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: SingleChildScrollView(
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
                Text('Filter',
                    style: GoogleFonts.bricolageGrotesque(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: const Color(0xFF333333))),
                const SizedBox(height: 20),

                // No type filter: SmartFin records expenses only, so "All" and
                // "Expense" would show the same list.
                _filterLabel('MONTH'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _filterChip('Any', month == null, () => setSheet(() => month = null)),
                  ...months.map((m) => _filterChip(
                      m.label, month == m.value, () => setSheet(() => month = m.value))),
                ]),
                const SizedBox(height: 20),

                _filterLabel('CATEGORY'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _filterChip('Any', category == null,
                      () => setSheet(() => category = null)),
                  ...categories.map((c) => _filterChip(
                      c, category == c, () => setSheet(() => category = c))),
                ]),
                const SizedBox(height: 28),

                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFEAE2D6)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9999)),
                        ),
                        onPressed: () => setSheet(() {
                          type = null;
                          category = null;
                          month = null;
                        }),
                        child: Text('Clear all',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: const Color(0xFF9E9E9E))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9F29),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9999)),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text('APPLY',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                letterSpacing: 2,
                                color: Colors.white)),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );

    if (applied == true && mounted) {
      setState(() {
        _filterType = type;
        _filterCategory = category;
        _filterMonth = month;
      });
      await _loadTransactions();
    }
  }

  Widget _filterLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 10,
                letterSpacing: 2,
                color: const Color(0xFF9E9E9E))),
      );

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color.fromRGBO(255, 159, 41, 0.08) : Colors.white,
          border: Border.all(
            color: selected ? const Color(0xFFFF9F29) : const Color(0xFFEAE2D6),
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
                color: selected ? const Color(0xFFFF9F29) : const Color(0xFF333333))),
      ),
    );
  }

  /// Returns transactions grouped by formatted_date, in order:
  /// "Today" first, "Yesterday" second, then older dates.
  Map<String, List<Map<String, dynamic>>> _groupTransactionsByDate(
      List<Map<String, dynamic>> transactions) {
    const priorityKeys = ['Today', 'Yesterday'];
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final tx in transactions) {
      final dateKey = tx['formatted_date'] as String? ?? 'Older';
      grouped.putIfAbsent(dateKey, () => []).add(tx);
    }

    // Reorder: Today → Yesterday → everything else in insertion order
    final ordered = <String, List<Map<String, dynamic>>>{};
    for (final key in priorityKeys) {
      if (grouped.containsKey(key)) {
        ordered[key] = grouped[key]!;
      }
    }
    for (final key in grouped.keys) {
      if (!priorityKeys.contains(key)) {
        ordered[key] = grouped[key]!;
      }
    }
    return ordered;
  }

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _transactions;
    final q = _searchQuery.toLowerCase();
    return _transactions
        .where((tx) =>
            (tx['merchant'] as String? ?? '').toLowerCase().contains(q))
        .toList();
  }

  static const Map<String, ({IconData icon, Color color})> _categoryStyle = {
    // Expense categories
    'Food':          (icon: Icons.restaurant_outlined,       color: Color(0xFFFF9F29)),
    'Transport':     (icon: Icons.directions_car_outlined,   color: Color(0xFF4A90E2)),
    'Entertainment': (icon: Icons.movie_outlined,             color: Color(0xFF9C27B0)),
    'Shopping':      (icon: Icons.shopping_bag_outlined,      color: Color(0xFFE91E63)),
    'Health':        (icon: Icons.favorite_outline,           color: Color(0xFFEF4444)),
    'Groceries':     (icon: Icons.local_grocery_store_outlined, color: Color(0xFF4CAF50)),
    'Bills':         (icon: Icons.receipt_outlined,           color: Color(0xFFFF9800)),
    // Income categories
    'Salary':        (icon: Icons.account_balance_wallet_outlined, color: Color(0xFFFF9F29)),
    'Gifts':         (icon: Icons.card_giftcard_outlined,     color: Color(0xFF4A90E2)),
    'Refunds':       (icon: Icons.local_offer_outlined,       color: Color(0xFF4CAF50)),
    // Fallback
    'Other':         (icon: Icons.add_circle_outline,         color: Color(0xFF9E9E9E)),
  };

  Widget _buildTransactionRow(Map<String, dynamic> tx) {
    final bool isIncome = (tx['type'] as String?) == 'income';
    final String merchant = tx['merchant'] as String? ?? '-';
    final String formattedAmount = tx['formatted_amount'] as String? ?? '';
    final String category = tx['category'] as String? ?? '';
    final String formattedTime = tx['formatted_time'] as String? ?? '';

    final style = _categoryStyle[category] ??
        (isIncome
            ? (icon: Icons.account_balance_wallet_outlined, color: const Color(0xFFFF9F29))
            : (icon: Icons.arrow_upward, color: const Color(0xFF9E9E9E)));

    return GestureDetector(
      onTap: () => _openDetail(tx),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.4)),
        ),
        child: Row(
          children: [
            // Icon container
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: style.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: style.color.withOpacity(0.2)),
              ),
              child: Icon(
                style.icon,
                size: 18,
                color: style.color,
              ),
            ),
            const SizedBox(width: 16),

            // Middle: merchant + category • time
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    merchant,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: const Color(0xFF333333),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$category${formattedTime.isNotEmpty ? ' • $formattedTime' : ''}',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w500,
                      fontSize: 10,
                      color: const Color(0xFF9E9E9E),
                    ),
                  ),
                ],
              ),
            ),

            // Right: formatted amount
            Text(
              formattedAmount,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: isIncome
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFFEF4444),
              ),
            ),
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
          // ────────────────── Body content ──────────────────
          RefreshIndicator(
            color: const Color(0xFFFF9F29),
            onRefresh: _loadTransactions,
            child: CustomScrollView(
              physics: const ClampingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                // ── Sticky Header + Search ──
                SliverAppBar(
                  pinned: true,
                  automaticallyImplyLeading: false,
                  expandedHeight: 164,
                  collapsedHeight: 164,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  flexibleSpace: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                      child: Container(
                        color: const Color.fromRGBO(255, 249, 240, 0.8),
                        padding: const EdgeInsets.only(top: 48, bottom: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () => context.go('/home'),
                                        child: Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: const Color.fromRGBO(
                                                    234, 226, 214, 0.6)),
                                            boxShadow: [
                                              BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.02),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2))
                                            ],
                                          ),
                                          child: const Icon(Icons.chevron_left,
                                              size: 22,
                                              color: Color.fromRGBO(
                                                  51, 51, 51, 0.7)),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        "History",
                                        style: GoogleFonts.bricolageGrotesque(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 18,
                                          color: const Color(0xFF333333),
                                        ),
                                      ),
                                    ],
                                  ),
                                  GestureDetector(
                                    onTap: _showFilterSheet,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: _activeFilterCount > 0
                                                ? const Color.fromRGBO(
                                                    255, 159, 41, 0.1)
                                                : Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: _activeFilterCount > 0
                                                    ? const Color(0xFFFF9F29)
                                                    : const Color.fromRGBO(
                                                        234, 226, 214, 0.6)),
                                          ),
                                          child: Icon(Icons.tune,
                                              size: 22,
                                              color: _activeFilterCount > 0
                                                  ? const Color(0xFFFF9F29)
                                                  : const Color.fromRGBO(
                                                      51, 51, 51, 0.7)),
                                        ),
                                        // Without this the list can look empty
                                        // when it is merely filtered.
                                        if (_activeFilterCount > 0)
                                          Positioned(
                                            top: -4,
                                            right: -4,
                                            child: Container(
                                              width: 18,
                                              height: 18,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFF9F29),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                    color: AppColors.cream,
                                                    width: 2),
                                              ),
                                              child: Text(
                                                '$_activeFilterCount',
                                                style: GoogleFonts.inter(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 9,
                                                    color: Colors.white),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Search bar
                            Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 8),
                              height: 48,
                              padding:
                                  const EdgeInsets.only(left: 16, right: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: const Color.fromRGBO(
                                        234, 226, 214, 0.6)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.search,
                                      size: 18,
                                      color:
                                          Color.fromRGBO(158, 158, 158, 0.5)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      onChanged: (val) =>
                                          setState(() => _searchQuery = val),
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 14,
                                        color: const Color(0xFF333333),
                                      ),
                                      decoration: InputDecoration(
                                        border: InputBorder.none,
                                        hintText: "Search...",
                                        hintStyle: GoogleFonts.inter(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                          color: const Color.fromRGBO(
                                              158, 158, 158, 0.4),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Loading state ──
                if (_isLoading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF9F29),
                      ),
                    ),
                  )

                // ── Error state ──
                else if (_error != null)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.cloud_off_outlined,
                              size: 64,
                              color: Color(0xFFD8D2C8),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                                color: const Color(0xFF9E9E9E),
                              ),
                            ),
                            const SizedBox(height: 20),
                            GestureDetector(
                              onTap: _loadTransactions,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 28, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF9F29),
                                  borderRadius: BorderRadius.circular(9999),
                                ),
                                child: Text(
                                  "TRY AGAIN",
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    letterSpacing: 1.5,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 80),
                          ],
                        ),
                      ),
                    ),
                  )

                // ── Empty state (no transactions at all, not just filtered) ──
                else if (_transactions.isEmpty && _searchQuery.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.receipt_long_outlined,
                            size: 64,
                            color: Color(0xFFD8D2C8),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "No transactions yet.",
                            style: GoogleFonts.bricolageGrotesque(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: const Color(0xFF333333),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Add your first one! 🐾",
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                              color: const Color(0xFF9E9E9E),
                            ),
                          ),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  )

                // ── Filtered empty (search with no matches) ──
                else if (_filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.search_off_outlined,
                            size: 64,
                            color: Color(0xFFD8D2C8),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "No transactions found",
                            style: GoogleFonts.bricolageGrotesque(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: const Color(0xFF333333),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Try searching for something else",
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                              color: const Color(0xFF9E9E9E),
                            ),
                          ),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  )

                // ── Grouped transaction list ──
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(
                        left: 24, right: 24, top: 8, bottom: 120),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, groupIndex) {
                          final grouped =
                              _groupTransactionsByDate(_filtered);
                          final dateKey =
                              grouped.keys.elementAt(groupIndex);
                          final items = grouped[dateKey]!;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                        horizontal: 8)
                                    .copyWith(bottom: 16, top: 8),
                                child: Text(
                                  dateKey.toUpperCase(),
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                    letterSpacing: 1.5,
                                    color: const Color(0xFF9E9E9E),
                                  ),
                                ),
                              ),
                              ...items
                                  .map((tx) => _buildTransactionRow(tx)),
                              const SizedBox(height: 8),
                            ],
                          );
                        },
                        childCount:
                            _groupTransactionsByDate(_filtered).length,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Bottom Nav Bar
          // FAB kept here: History is where a missing entry is noticed, and
          // there is nothing at the bottom of this screen for it to collide with.
          const SmartFinBottomNav(currentIndex: 1),
        ],
      ),
    );
  }
}
