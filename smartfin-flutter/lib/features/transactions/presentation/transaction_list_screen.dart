import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/widgets/bottom_nav_bar.dart';
import 'package:smart_fin/features/transactions/data/transaction_repository_impl.dart';

class TransactionListScreen extends StatefulWidget {
  const TransactionListScreen({super.key});

  @override
  State<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends State<TransactionListScreen> {
  String _searchQuery = '';
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final result = await TransactionRepositoryImpl().getTransactions(userID: uid);

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
      onTap: () => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Detail coming soon'))),
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
              physics: const BouncingScrollPhysics(
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
                                    onTap: () => ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(
                                            content:
                                                Text('Filter coming soon'))),
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
                                              color:
                                                  Colors.black.withOpacity(0.02),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2))
                                        ],
                                      ),
                                      child: const Icon(Icons.tune,
                                          size: 22,
                                          color:
                                              Color.fromRGBO(51, 51, 51, 0.7)),
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
                            Opacity(
                              opacity: 0.4,
                              child: Image.asset(
                                'assets/images/lucky_cat.png',
                                width: 72,
                                height: 72,
                                filterQuality: FilterQuality.medium,
                              ),
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
                          Opacity(
                            opacity: 0.5,
                            child: Image.asset(
                              'assets/images/lucky_cat.png',
                              width: 80,
                              height: 80,
                              filterQuality: FilterQuality.medium,
                            ),
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
                          Opacity(
                            opacity: 0.5,
                            child: Image.asset('assets/images/lucky_cat.png',
                                width: 80,
                                height: 80,
                                filterQuality: FilterQuality.medium),
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
          const SmartFinBottomNav(currentIndex: 1, showFab: false),
        ],
      ),
    );
  }
}
