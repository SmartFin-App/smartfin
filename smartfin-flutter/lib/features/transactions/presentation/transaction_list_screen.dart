import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_fin/widgets/ui/ui.dart';
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
  final TextEditingController _searchController = TextEditingController();

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
    _searchController.dispose();
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
      'Food',
      'Transport',
      'Shopping',
      'Bills',
      'Groceries',
      'Health',
      'Entertainment',
      'Other',
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
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
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
                Text('Filter', style: AppTextStyles.title),
                const SizedBox(height: AppSpacing.xl),

                // No type filter: SmartFin records expenses only, so "All" and
                // "Expense" would show the same list.
                _filterLabel('Month'),
                Row(
                  children: [
                    AppChip(
                      label: 'All months',
                      selected: month == null,
                      onTap: () => setSheet(() => month = null),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _monthStepper(
                        shown: shown,
                        selected: month != null,
                        canGoNext: shown.isBefore(thisMonth),
                        onSelect: () =>
                            setSheet(() => month = _monthKey(shown)),
                        onStep: (delta) => setSheet(() {
                          shown = DateTime(shown.year, shown.month + delta);
                          month = _monthKey(shown);
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),

                _filterLabel('Category'),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    AppChip(
                      label: 'Any',
                      selected: category == null,
                      onTap: () => setSheet(() => category = null),
                    ),
                    ...categories.map(
                      (c) => AppChip(
                        label: c,
                        icon: _styleFor(c).icon,
                        selected: category == c,
                        onTap: () => setSheet(() => category = c),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),

                Row(
                  children: [
                    Expanded(
                      child: AppButton.secondary(
                        label: 'Clear all',
                        expand: true,
                        onPressed: () => setSheet(() {
                          type = null;
                          category = null;
                          month = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 2,
                      child: AppButton(
                        label: 'Show results',
                        expand: true,
                        onPressed: () => Navigator.pop(ctx, true),
                      ),
                    ),
                  ],
                ),
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
    final fg = selected ? AppColors.primaryText : AppColors.textDark;
    Widget arrow(
      IconData icon,
      String label,
      bool enabled,
      VoidCallback onTap,
    ) => IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 20, semanticLabel: label),
      color: fg,
      disabledColor: AppColors.border,
      visualDensity: VisualDensity.compact,
    );

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.14)
            : AppColors.white,
        border: Border.all(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.5)
              : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          arrow(
            Icons.chevron_left_rounded,
            'Previous month',
            true,
            () => onStep(-1),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSelect,
              child: Center(
                child: Text(
                  DateFormat('MMM yyyy').format(shown),
                  style: AppTextStyles.label.copyWith(color: fg),
                ),
              ),
            ),
          ),
          arrow(
            Icons.chevron_right_rounded,
            'Next month',
            canGoNext,
            () => onStep(1),
          ),
        ],
      ),
    );
  }

  Widget _filterLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Text(
      text,
      style: AppTextStyles.label.copyWith(color: AppColors.textSecondary),
    ),
  );

  /// Returns transactions grouped by formatted_date, in order:
  /// "Today" first, "Yesterday" second, then older dates.
  Map<String, List<Map<String, dynamic>>> _groupTransactionsByDate(
    List<Map<String, dynamic>> transactions,
  ) {
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
    // Fallback
    'Other': (icon: Icons.add_circle_outline, color: Color(0xFF9E9E9E)),
  };

  ({IconData icon, Color color}) _styleFor(String? category) =>
      _categoryStyle[category] ?? _categoryStyle['Other']!;

  /// Spinner while the next page loads, or a retry if it failed.
  Widget _buildListFooter() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (_loadMoreFailed) {
      return Center(
        child: AppButton.text(
          label: "Couldn't load more. Tap to retry",
          icon: Icons.refresh_rounded,
          onPressed: () {
            setState(() => _loadMoreFailed = false);
            _loadMore();
          },
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildTransactionRow(Map<String, dynamic> tx) {
    final category = tx['category'] as String? ?? '';
    final style = _styleFor(category);
    return ListRow(
      leading: IconTile(icon: style.icon, color: style.color),
      title: tx['merchant'] as String? ?? '-',
      subtitle: category,
      trailing: Text(
        tx['formatted_amount'] as String? ?? '',
        style: AppTextStyles.amount,
      ),
      onTap: () => _openDetail(tx),
    );
  }

  /// One day's transactions: a date label, then the rows grouped in a card.
  Widget _buildDayGroup(String dateKey, List<Map<String, dynamic>> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: Text(
              dateKey,
              style: AppTextStyles.label.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) ListRow.divider(),
                  _buildTransactionRow(items[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonList() {
    return AppCard(
      flat: true,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        children: [
          for (var i = 0; i < 6; i++)
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Skeleton(width: 40, height: 40, radius: AppRadius.md),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton(width: 140, height: 14),
                        SizedBox(height: 6),
                        Skeleton(width: 80, height: 12),
                      ],
                    ),
                  ),
                  Skeleton(width: 56, height: 14),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Centred in the space under the header, with room left for the nav bar.
  Widget _fillState(Widget child) => SliverFillRemaining(
    hasScrollBody: false,
    child: Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.screen,
        right: AppSpacing.screen,
        bottom: 100,
      ),
      child: Center(child: child),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final grouped = _groupTransactionsByDate(_transactions);
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Stack(
        children: [
          // ────────────────── Body content ──────────────────
          RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _loadTransactions,
            child: CustomScrollView(
              controller: _scroll,
              physics: const ClampingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                // ── Sticky Header + Search ──
                // Title (48 + 40), a 12 gap, the 48 search field, then 8.
                SliverAppBar(
                  pinned: true,
                  automaticallyImplyLeading: false,
                  toolbarHeight: PageTitleRow.barHeight(context, 156),
                  expandedHeight: PageTitleRow.barHeight(context, 156),
                  collapsedHeight: PageTitleRow.barHeight(context, 156),
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  flexibleSpace: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                      child: Container(
                        color: AppColors.cream.withValues(alpha: 0.85),
                        padding: const EdgeInsets.only(
                          top: 48,
                          bottom: AppSpacing.sm,
                          left: AppSpacing.screen,
                          right: AppSpacing.screen,
                        ),
                        child: Column(
                          children: [
                            PageTitleRow(
                              title: 'History',
                              // The badge stops a filtered list from looking
                              // empty.
                              trailing: AppIconButton(
                                icon: Icons.tune_rounded,
                                semanticLabel: 'Filters',
                                active: _activeFilterCount > 0,
                                badge: _activeFilterCount,
                                onPressed: _showFilterSheet,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            // Fixed height: the header's size is computed
                            // from it.
                            SizedBox(
                              height: 48,
                              child: TextField(
                                controller: _searchController,
                                onChanged: (value) {
                                  // Rebuild for the clear button.
                                  setState(() {});
                                  _onSearchChanged(value);
                                },
                                textInputAction: TextInputAction.search,
                                textAlignVertical: TextAlignVertical.center,
                                style: AppTextStyles.body,
                                decoration: InputDecoration(
                                  hintText: 'Search merchants',
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    size: 20,
                                    color: AppColors.textSecondary,
                                  ),
                                  suffixIcon: _searchController.text.isEmpty
                                      ? null
                                      : IconButton(
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                            semanticLabel: 'Clear search',
                                          ),
                                          color: AppColors.textSecondary,
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() {});
                                            _onSearchChanged('');
                                          },
                                        ),
                                ),
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
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screen,
                      AppSpacing.sm,
                      AppSpacing.screen,
                      120,
                    ),
                    sliver: SliverToBoxAdapter(child: _buildSkeletonList()),
                  )
                // ── Error state ──
                else if (_error != null)
                  _fillState(
                    StatusMessage(
                      icon: Icons.cloud_off_rounded,
                      title: "Couldn't load your history",
                      message: _error,
                      action: AppButton.secondary(
                        label: 'Try again',
                        icon: Icons.refresh_rounded,
                        onPressed: _loadTransactions,
                      ),
                    ),
                  )
                // ── Empty state (no transactions at all, not just filtered) ──
                else if (_transactions.isEmpty &&
                    _searchQuery.isEmpty &&
                    _activeFilterCount == 0)
                  _fillState(
                    const StatusMessage(
                      icon: Icons.receipt_long_rounded,
                      title: 'No expenses yet',
                      message: 'Scan a slip or tap + to add your first one.',
                    ),
                  )
                // ── Filtered empty (search or filters with no matches) ──
                else if (_transactions.isEmpty)
                  _fillState(
                    StatusMessage(
                      icon: Icons.search_off_rounded,
                      title: 'Nothing matches',
                      message: _searchQuery.isNotEmpty
                          ? 'Try searching for something else.'
                          : 'Try another month or category.',
                      action: _activeFilterCount > 0
                          ? AppButton.secondary(
                              label: 'Clear filters',
                              onPressed: () {
                                setState(() {
                                  _filterType = null;
                                  _filterCategory = null;
                                  _filterMonth = null;
                                });
                                _loadTransactions();
                              },
                            )
                          : null,
                    ),
                  )
                // ── Grouped transaction list ──
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screen,
                      AppSpacing.sm,
                      AppSpacing.screen,
                      120,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, groupIndex) {
                          if (groupIndex == grouped.length) {
                            return _buildListFooter();
                          }
                          final dateKey = grouped.keys.elementAt(groupIndex);
                          return _buildDayGroup(dateKey, grouped[dateKey]!);
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
          const SmartFinBottomNav(currentIndex: 1),
        ],
      ),
    );
  }
}
