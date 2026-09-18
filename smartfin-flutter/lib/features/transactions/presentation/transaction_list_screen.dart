import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/core/network/dio_client.dart';
import 'package:smart_fin/widgets/page_title_row.dart';
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

  // Paging: the API returns 50 at a time, newest first. Without this the list
  // silently stopped at the 50 most recent transactions.
  static const int _pageSize = 50;
  final ScrollController _scroll = ScrollController();
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  // Bumped on every fresh load, so a page that arrives after the filters
  // changed is dropped instead of being appended to the new list.
  int _generation = 0;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    // Applied before the first load, so a pre-filtered open never flashes the
    // unfiltered list first.
    _filterType = _nonEmpty(widget.initialType);
    _filterCategory = _nonEmpty(widget.initialCategory);
    _filterMonth = _nonEmpty(widget.initialMonth);
    _scroll.addListener(_onScroll);
    _loadTransactions();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 600) _loadMore();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || value.trim() == _searchQuery) return;
      _searchQuery = value.trim();
      _loadTransactions();
    });
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  // Filtering and search both happen server-side: the month window then
  // matches the one the summaries use, and search covers every transaction,
  // not only the pages loaded so far.
  Future<ApiResponse<List<Map<String, dynamic>>>> _fetchPage(int skip) {
    return TransactionRepositoryImpl().getTransactions(
      userID: FirebaseAuth.instance.currentUser?.uid ?? '',
      type: _filterType,
      category: _filterCategory,
      month: _filterMonth,
      search: _searchQuery,
      limit: _pageSize,
      skip: skip,
    );
  }

  Future<void> _loadTransactions() async {
    final gen = ++_generation;
    setState(() {
      _isLoading = true;
      _error = null;
      _loadingMore = false;
      _loadMoreFailed = false;
    });

    final result = await _fetchPage(0);
    if (!mounted || gen != _generation) return;

    setState(() {
      if (result.success) {
        _transactions = result.data ?? [];
        _hasMore = _transactions.length == _pageSize;
      } else {
        _error = result.error;
      }
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _isLoading || _loadMoreFailed) return;
    final gen = _generation;
    setState(() => _loadingMore = true);

    final result = await _fetchPage(_transactions.length);
    if (!mounted || gen != _generation) return;

    setState(() {
      if (result.success) {
        final page = result.data ?? [];
        _transactions = [..._transactions, ...page];
        _hasMore = page.length == _pageSize;
      } else {
        _loadMoreFailed = true;
      }
      _loadingMore = false;
    });
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

    // Expense categories only: SmartFin records no income.
    const categories = [
      'Food', 'Transport', 'Shopping', 'Bills', 'Groceries',
      'Health', 'Entertainment', 'Other',
    ];

    // The month stepper shows the selected month, or this month when "All
    // months" is selected. It goes back without limit; the old six fixed chips
    // left anything older reachable only by scrolling.
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    DateTime shown = _parseMonth(month) ?? thisMonth;

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
                Row(children: [
                  _filterChip('All months', month == null,
                      () => setSheet(() => month = null)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _monthStepper(
                      shown: shown,
                      selected: month != null,
                      canGoNext: shown.isBefore(thisMonth),
                      onSelect: () => setSheet(() => month = _monthKey(shown)),
                      onStep: (delta) => setSheet(() {
                        shown = DateTime(shown.year, shown.month + delta);
                        month = _monthKey(shown);
                      }),
                    ),
                  ),
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

  static String _monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  static DateTime? _parseMonth(String? key) {
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(key ?? '');
    if (m == null) return null;
    return DateTime(int.parse(m[1]!), int.parse(m[2]!));
  }

  /// `‹ Sep 2026 ›`. Stepping selects the month it lands on; tapping the label
  /// selects the month shown. No stepping past the current month.
  Widget _monthStepper({
    required DateTime shown,
    required bool selected,
    required bool canGoNext,
    required VoidCallback onSelect,
    required void Function(int delta) onStep,
  }) {
    const accent = Color(0xFFFF9F29);
    Widget arrow(IconData icon, bool enabled, VoidCallback onTap) =>
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Icon(icon,
                size: 20,
                color: enabled
                    ? (selected ? accent : const Color(0xFF333333))
                    : const Color(0xFFD8D2C8)),
          ),
        );

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: selected ? const Color.fromRGBO(255, 159, 41, 0.08) : Colors.white,
        border: Border.all(
          color: selected ? accent : const Color(0xFFEAE2D6),
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Row(children: [
        arrow(Icons.chevron_left, true, () => onStep(-1)),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSelect,
            child: Center(
              child: Text(
                DateFormat('MMM yyyy').format(shown),
                style: GoogleFonts.inter(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13,
                    color: selected ? accent : const Color(0xFF333333)),
              ),
            ),
          ),
        ),
        arrow(Icons.chevron_right, canGoNext, () => onStep(1)),
      ]),
    );
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

  static const Map<String, ({IconData icon, Color color})> _categoryStyle = {
    // Expense categories
    'Food':          (icon: Icons.restaurant_outlined,       color: Color(0xFFFF9F29)),
    'Transport':     (icon: Icons.directions_car_outlined,   color: Color(0xFF2563EB)),
    'Entertainment': (icon: Icons.movie_outlined,             color: Color(0xFF7C3AED)),
    'Shopping':      (icon: Icons.shopping_bag_outlined,      color: Color(0xFFDB2777)),
    'Health':        (icon: Icons.favorite_outline,           color: Color(0xFFDC2626)),
    'Groceries':     (icon: Icons.local_grocery_store_outlined, color: Color(0xFF65A30D)),
    'Bills':         (icon: Icons.receipt_outlined,           color: Color(0xFF0D9488)),
    // Income categories
    'Salary':        (icon: Icons.account_balance_wallet_outlined, color: Color(0xFFFF9F29)),
    'Gifts':         (icon: Icons.card_giftcard_outlined,     color: Color(0xFF4A90E2)),
    'Refunds':       (icon: Icons.local_offer_outlined,       color: Color(0xFF4CAF50)),
    // Fallback
    'Other':         (icon: Icons.add_circle_outline,         color: Color(0xFF9E9E9E)),
  };

  /// Spinner while the next page loads, or a retry if it failed.
  Widget _buildListFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: Color(0xFFFF9F29)),
          ),
        ),
      );
    }
    if (_loadMoreFailed) {
      return Center(
        child: TextButton(
          onPressed: () {
            setState(() => _loadMoreFailed = false);
            _loadMore();
          },
          child: Text("Couldn't load more. Tap to retry",
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: const Color(0xFFFF9F29))),
        ),
      );
    }
    return const SizedBox.shrink();
  }

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
    final grouped = _groupTransactionsByDate(_transactions);
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Stack(
        children: [
          // ────────────────── Body content ──────────────────
          RefreshIndicator(
            color: const Color(0xFFFF9F29),
            onRefresh: _loadTransactions,
            child: CustomScrollView(
              controller: _scroll,
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
                              child: PageTitleRow(
                                title: 'History',
                                trailing: GestureDetector(
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
                                      onChanged: _onSearchChanged,
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
                else if (_transactions.isEmpty &&
                    _searchQuery.isEmpty &&
                    _activeFilterCount == 0)
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
                            "Add your first one!",
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

                // ── Filtered empty (search or filters with no matches) ──
                else if (_transactions.isEmpty)
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
                            _searchQuery.isNotEmpty
                                ? "Try searching for something else"
                                : "Try another month or category",
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
                          if (groupIndex == grouped.length) {
                            return _buildListFooter();
                          }
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
                        // +1 for the load-more footer.
                        childCount: grouped.length + 1,
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
