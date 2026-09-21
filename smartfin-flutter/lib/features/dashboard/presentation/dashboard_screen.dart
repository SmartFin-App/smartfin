import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/core/network/dio_client.dart';
import 'package:smart_fin/widgets/bottom_nav_bar.dart';
import 'package:smart_fin/widgets/smartfin_logo.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_fin/features/transactions/data/transaction_repository_impl.dart';
import 'package:smart_fin/features/subscriptions/data/subscription_repository_impl.dart';
import 'package:smart_fin/features/subscriptions/services/bill_reminder_service.dart';
import 'package:smart_fin/features/scanner/services/gallery_watcher_service.dart';
import 'package:smart_fin/features/scanner/presentation/widgets/slip_detection_sheet.dart';
import 'package:smart_fin/features/scanner/presentation/widgets/slip_folders_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _monthlySummary;
  List<Map<String, dynamic>> _recentTransactions = [];
  bool _isLoading = true;
  bool _loadFailed = false;
  // Active bills overdue or due within 7 days, soonest first.
  List<Map<String, dynamic>> _upcomingBills = [];
  int _upcomingTotal = 0;
  String _currentMonth = '';

  static const Map<String, ({IconData icon, Color color})> _categoryStyle = {
    'Food':          (icon: Icons.restaurant_outlined,            color: Color(0xFFFF9F29)),
    'Transport':     (icon: Icons.directions_car_outlined,        color: Color(0xFF2563EB)),
    'Entertainment': (icon: Icons.movie_outlined,                 color: Color(0xFF7C3AED)),
    'Shopping':      (icon: Icons.shopping_bag_outlined,          color: Color(0xFFDB2777)),
    'Health':        (icon: Icons.favorite_outline,               color: Color(0xFFDC2626)),
    'Groceries':     (icon: Icons.local_grocery_store_outlined,   color: Color(0xFF65A30D)),
    'Bills':         (icon: Icons.receipt_outlined,               color: Color(0xFF0D9488)),
    'Other':         (icon: Icons.attach_money,                   color: Color(0xFF9E9E9E)),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    // Check for any newly saved slips in the background shortly after startup
    Future.delayed(const Duration(seconds: 2), _checkForNewSlips);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When returning from banking apps (PromptPay payment slip saved to gallery)
    if (state == AppLifecycleState.resumed) {
      _checkForNewSlips();
    }
  }

  Future<void> _checkForNewSlips() async {
    if (!mounted) return;
    try {
      final watcher = GalleryWatcherService();
      final result = await watcher.checkForNewSlipsDetailed();
      if (!mounted) return;

      if (result.slip != null) {
        SlipDetectionSheet.show(context, result.slip!);
        return;
      }

      // Auto-Detect finds nothing when the slips live in a folder we do not
      // recognise — a bank we never listed, a renamed album, or screenshots.
      // Offer the picker once rather than letting the feature look broken; a
      // check that runs on every resume must not nag.
      if (result.status == SlipCheckStatus.noAlbum &&
          await watcher.shouldOfferFolderPicker()) {
        await watcher.markFolderPickerOffered();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                "We couldn't find your slip folder. Pick one so SmartFin can spot new slips."),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Pick',
              onPressed: () => SlipFoldersSheet.show(context),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error auto-checking slips: $e');
    }
  }

  /// Waits briefly for Firebase to restore a persisted session before giving up,
  /// rather than firing requests with an empty uid.
  Future<String> _resolveUid() async {
    final current = FirebaseAuth.instance.currentUser?.uid;
    if (current != null && current.isNotEmpty) return current;
    try {
      final user = await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(const Duration(seconds: 5));
      return user?.uid ?? '';
    } catch (_) {
      return '';
    }
  }

  String _baht(num amount) {
    return '฿${amount.round().toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}';
  }

  Future<void> _openSubscriptions() async {
    final changed = await context.push<bool>('/subscriptions');
    if (changed == true && mounted) _loadData();
  }

  /// Bills that are overdue or due within a week. Hidden when there are none, so
  /// it never adds an empty card for users who don't track bills. The figures and
  /// day counts come from the server in Thai time; this only picks the wording.
  Widget _buildUpcomingBillsCard() {
    final count = _upcomingBills.length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openSubscriptions,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.4)),
          boxShadow: const [
            BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.02), blurRadius: 10, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color.fromRGBO(255, 159, 41, 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.event_repeat_outlined, size: 18, color: Color(0xFFFF9F29)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'UPCOMING BILLS',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 2,
                          color: const Color(0xFF9E9E9E),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_baht(_upcomingTotal)} · $count bill${count == 1 ? '' : 's'}',
                        style: GoogleFonts.bricolageGrotesque(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: AppColors.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20, color: Color.fromRGBO(158, 158, 158, 0.6)),
              ],
            ),
            const SizedBox(height: 12),
            ..._upcomingBills.take(3).map(_buildUpcomingBillRow),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingBillRow(Map<String, dynamic> bill) {
    final days = (bill['days_until_due'] as num?)?.toInt() ?? 0;
    final String when;
    if (days < 0) {
      when = '${-days} day${days == -1 ? '' : 's'} overdue';
    } else if (days == 0) {
      when = 'Due today';
    } else if (days == 1) {
      when = 'Due tomorrow';
    } else {
      when = 'Due in $days days';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              bill['name'] as String? ?? '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textDark),
            ),
          ),
          Text(
            when,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: days < 0 ? const Color(0xFFEF4444) : const Color(0xFFFF9F29),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            bill['formatted_amount'] as String? ?? _baht((bill['amount'] as num?) ?? 0),
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textDark),
          ),
        ],
      ),
    );
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    // Firebase restores a persisted session asynchronously, so on a cold start
    // currentUser can still be null here. Requesting with an empty uid 404s and
    // used to render a fabricated all-zero month indistinguishable from a real one.
    final uid = await _resolveUid();
    if (uid.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
      }
      return;
    }
    final now = DateTime.now();
    _currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    try {
      await Future.wait([
        // Monthly Summary
        DioClient.dio.get(
          '/api/summary/$uid',
          queryParameters: {'month': _currentMonth},
        ).then((res) {
          if (mounted) {
            setState(() {
              _monthlySummary = res.data as Map<String, dynamic>;
            });
          }
        }),
        // Recent 3
        TransactionRepositoryImpl()
            .getTransactions(userID: uid, limit: 3)
            .then((res) {
          if (res.success && mounted) {
            setState(() => _recentTransactions = res.data ?? []);
          }
        }),
        // Upcoming bills — non-fatal, the rest of the dashboard stands without
        // them. Wrapped so a failure here cannot reject the whole Future.wait and
        // take the rest of the dashboard down with it.
        () async {
          try {
            final res = await SubscriptionRepositoryImpl()
                .getSubscriptions(userID: uid, activeOnly: true);
            if (!res.success || !mounted) return;
            final all = ((res.data?['subscriptions'] as List?) ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
            // The dashboard is where most sessions start, so reminders are kept
            // current from here too, not only from the tracker screen.
            BillReminderService().syncAll(all);
            setState(() {
              _upcomingBills = all
                  .where((s) => ((s['days_until_due'] as num?) ?? 999) <= 7)
                  .toList();
              _upcomingTotal = (res.data?['due_soon_total'] as num?)?.toInt() ?? 0;
            });
          } catch (e) {
            debugPrint('Upcoming bills unavailable: $e');
          }
        }(),
      ]);

      // Fetch user profile from MongoDB and sync SharedPreferences
      if (uid.isNotEmpty) {
        try {
          final userResponse = await DioClient.dio.get('/api/users/$uid');
          final userData = userResponse.data as Map<String, dynamic>;
          final mongoBudget = ((userData['budget_limit'] ?? 0) as num).toInt();

          // This sync used to run only for users with an income set, so everyone
          // else kept a stale cached budget and name.
          final prefs = await SharedPreferences.getInstance();
          if (mongoBudget > 0) {
            await prefs.setInt('user_budget_limit', mongoBudget);
          }
          if ((userData['name'] as String?)?.isNotEmpty == true) {
            // Still cached: the coach greeting and Account settings read it.
            // Only the dashboard header stopped showing the name.
            await prefs.setString('user_name', userData['name'] as String);
          }
        } catch (_) {
          // Non-fatal — fall back to local prefs
        }
      }
    } catch (e) {
      debugPrint('Error loading dashboard data: $e');
      if (mounted && _monthlySummary == null) {
        setState(() => _loadFailed = true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  // ── Budget donut + top categories ─────────────────────────────────────────
  // Replaces the old budget card, whose headline ("available to spend") was
  // income − expenses. Income is an assumed profile figure credited in full on
  // day one, so that headline was a projection dressed as a balance. Every
  // figure on this card is a recorded expense or the user's own budget limit.

  static const Color _ringTrack = Color.fromRGBO(240, 235, 225, 0.8);
  static const Color _overBudget = Color(0xFFEF4444);

  /// Placeholder shaped like the loaded card, so the layout doesn't jump.
  Widget _buildTopCategoriesSkeleton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _shimmerBox(width: 110, height: 10),
          const SizedBox(height: 20),
          Center(child: _shimmerBox(width: 180, height: 180, radius: 90)),
          const SizedBox(height: 28),
          _shimmerBox(width: 110, height: 10),
          for (var i = 0; i < 3; i++) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                _shimmerBox(width: 36, height: 36, radius: 12),
                const SizedBox(width: 12),
                Expanded(child: _shimmerBox(height: 14)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openProfileForBudget() async {
    await context.push('/profile');
    if (mounted) _loadData();
  }

  /// Donut of this month's spending, one segment per category, filling up to
  /// the budget limit. The unspent part of the budget is the grey track; once
  /// spending passes the limit the ring is simply full and the centre says by
  /// how much. With no budget set it is a plain category breakdown.
  Widget _buildBudgetDonut(List<Map> allCategories) {
    final spent = ((_monthlySummary?['total_expenses'] as num?) ?? 0).toInt();
    final budget = ((_monthlySummary?['budget_limit'] as num?) ?? 0).toInt();
    final hasBudget = budget > 0;
    final over = hasBudget && spent > budget;

    final sections = <PieChartSectionData>[
      for (final c in allCategories)
        if (((c['amount'] as num?) ?? 0) > 0)
          PieChartSectionData(
            value: ((c['amount'] as num?) ?? 0).toDouble(),
            color: (_categoryStyle[(c['category'] as String?)?.trim()] ??
                    _categoryStyle['Other']!)
                .color,
            radius: 22,
            showTitle: false,
          ),
      if (hasBudget && spent < budget)
        PieChartSectionData(
          value: (budget - spent).toDouble(),
          color: _ringTrack,
          radius: 22,
          showTitle: false,
        ),
    ];
    // fl_chart draws nothing for an all-zero pie; keep the empty ring visible.
    if (sections.isEmpty) {
      sections.add(PieChartSectionData(
          value: 1, color: _ringTrack, radius: 22, showTitle: false));
    }

    final String status;
    final Color statusColor;
    if (!hasBudget) {
      status = 'No budget set';
      statusColor = const Color(0xFF9E9E9E);
    } else if (over) {
      status = '${_baht(spent - budget)} over';
      statusColor = _overBudget;
    } else {
      status = '${_baht(budget - spent)} left';
      statusColor = const Color(0xFF4CAF50);
    }

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 72,
                  sectionsSpace: sections.length > 1 ? 2 : 0,
                  startDegreeOffset: -90,
                  borderData: FlBorderData(show: false),
                  pieTouchData: PieTouchData(enabled: false),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _baht(spent),
                    style: GoogleFonts.bricolageGrotesque(
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                      color: over ? _overBudget : AppColors.textDark,
                    ),
                  ),
                  if (hasBudget)
                    Text(
                      'of ${_baht(budget)}',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: const Color(0xFF9E9E9E),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    status,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!hasBudget) ...[
          const SizedBox(height: 8),
          GestureDetector(
            // Opaque so this tap doesn't fall through to the card's History tap.
            behavior: HitTestBehavior.opaque,
            onTap: _openProfileForBudget,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Set a monthly budget →',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: const Color(0xFFFF9F29),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTopCategoriesCard() {
    // Already sorted largest-first server-side, and [] rather than null when
    // there are no expenses — but guard the shape anyway.
    final raw = _monthlySummary?['expense_by_category'];
    final allCategories =
        (raw is List ? raw : const []).whereType<Map>().toList();
    final categories = allCategories.take(3).toList();

    return GestureDetector(
      onTap: () => context.push('/history'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MONTHLY BUDGET',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 10,
                letterSpacing: 2,
                color: const Color(0xFF9E9E9E),
              ),
            ),
            const SizedBox(height: 16),
            _buildBudgetDonut(allCategories),
            const SizedBox(height: 24),
            Text(
              'TOP CATEGORIES',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 10,
                letterSpacing: 2,
                color: const Color(0xFF9E9E9E),
              ),
            ),
            if (categories.isEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'No spending yet this month. Scan a slip or add an expense to see where your money goes',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  height: 1.5,
                  color: const Color.fromRGBO(51, 51, 51, 0.8),
                ),
              ),
            ] else
              for (final c in categories) ...[
                const SizedBox(height: 20),
                GestureDetector(
                  // Opaque so a tap anywhere across the row, gaps included,
                  // opens this category instead of falling through to the
                  // card-level tap that opens unfiltered History.
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final category = (c['category'] as String?)?.trim() ?? '';
                    // Type and month travel with the category so History's
                    // totals match the card: category alone would pull that
                    // category's transactions from every month.
                    context.push(Uri(path: '/history', queryParameters: {
                      'type': 'expense',
                      if (category.isNotEmpty) 'category': category,
                      if (_currentMonth.isNotEmpty) 'month': _currentMonth,
                    }).toString());
                  },
                  child: _buildCategoryRow(c),
                ),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryRow(Map c) {
    final name = (c['category'] as String?)?.trim();
    final label = (name == null || name.isEmpty) ? 'Other' : name;
    final amount = (c['amount'] as num?) ?? 0;
    final pct = ((c['percentage'] as num?) ?? 0).toDouble();
    final style = _categoryStyle[label] ?? _categoryStyle['Other']!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: style.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(style.icon, size: 18, color: style.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: const Color(0xFF333333),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _baht(amount),
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: const Color(0xFF333333),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9999),
                child: Container(
                  height: 6,
                  color: const Color.fromRGBO(240, 235, 225, 0.8),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (pct / 100).clamp(0.0, 1.0),
                    child: Container(color: style.color),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${pct.round()}% of spending',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: const Color(0xFF9E9E9E),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Shimmer placeholder ───────────────────────────────────────────────────
  Widget _shimmerBox({double width = double.infinity, double height = 16, double radius = 8}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEAE2D6),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _buildTransactionRow({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String name,
    required String meta,
    required String amount,
    required Color amountColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: const Color(0xFF333333),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                    letterSpacing: -0.25,
                    color: const Color(0xFF9E9E9E),
                  ),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: amountColor,
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final formattedMonth = (_monthlySummary?['formatted_month'] as String?) ?? 'Loading...';

    return Scaffold(
      backgroundColor: AppColors.cream,
      body: RefreshIndicator(
        color: const Color(0xFFFF9F29),
        onRefresh: _loadData,
        child: Stack(
          children: [
            CustomScrollView(
              physics: const ClampingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                // ── Sticky Header ──────────────────────────────────────────
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 80,
                  collapsedHeight: 80,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  flexibleSpace: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 6.0, sigmaY: 6.0),
                      child: Container(
                        color: const Color.fromRGBO(255, 249, 240, 0.8),
                        padding:
                            const EdgeInsets.only(top: 48, left: 24, right: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Brand mark rather than a greeting: the name told
                            // the user nothing they did not know, and the logo
                            // gives every screenshot an identifiable header.
                            const SmartFinLogo(),
                            GestureDetector(
                              onTap: () => context.push('/profile'),
                              child: Container(
                                width: 36,
                                height: 36,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  border:
                                      Border.all(color: const Color(0xFFEAE2D6)),
                                ),
                                // A person icon: cat imagery belongs to the AI
                                // Coach only.
                                child: const Icon(
                                  Icons.person_outline,
                                  size: 20,
                                  color: Color(0xFF333333),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Content ────────────────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.only(
                      left: 24, right: 24, top: 16, bottom: 120),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([

                      // ── Month Header ──────────────────────────────────────────
                      Center(
                        child: Text(
                          formattedMonth.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                            letterSpacing: 2,
                            color: const Color(0xFF9E9E9E),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Budget donut + Top Categories ────────────────────
                      // A failed load must not render as a real ฿0 month.
                      _loadFailed && !_isLoading
                          ? Container(
                              height: 180,
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAE2D6),
                                borderRadius: BorderRadius.circular(40),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.cloud_off_rounded,
                                      color: Color(0xFF9E9E9E), size: 28),
                                  const SizedBox(height: 12),
                                  Text(
                                    "Couldn't load this month",
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Pull down to try again",
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: const Color(0xFF9E9E9E),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : _isLoading
                              ? _buildTopCategoriesSkeleton()
                              : _buildTopCategoriesCard(),

                      if (!_isLoading && _upcomingBills.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _buildUpcomingBillsCard(),
                      ],

                      const SizedBox(height: 48),

                      // ── Recent Activity ──────────────────────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "RECENT ACTIVITY",
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                              letterSpacing: 2,
                              color: const Color(0xFF9E9E9E),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => context.push('/history'),
                            child: Text(
                              "VIEW ALL",
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                fontSize: 10,
                                letterSpacing: 1,
                                color: const Color(0xFFFF9F29),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      if (_isLoading)
                        ...List.generate(
                          3,
                          (_) => Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              children: [
                                _shimmerBox(
                                    width: 48, height: 48, radius: 24),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _shimmerBox(width: 120, height: 12),
                                      const SizedBox(height: 6),
                                      _shimmerBox(width: 80, height: 10),
                                    ],
                                  ),
                                ),
                                _shimmerBox(width: 60, height: 12),
                              ],
                            ),
                          ),
                        )
                      else if (_recentTransactions.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No transactions yet. Add your first one!',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                                color: const Color(0xFF9E9E9E),
                              ),
                            ),
                          ),
                        )
                      else
                        ..._recentTransactions.map((tx) {
                          final String category =
                              tx['category'] as String? ?? '';
                          final style = _categoryStyle[category] ??
                              (icon: Icons.attach_money, color: const Color(0xFF9E9E9E));
                          return _buildTransactionRow(
                            context: context,
                            icon: style.icon,
                            iconColor: style.color,
                            name: tx['merchant'] as String? ?? '-',
                            meta: category.toUpperCase(),
                            amount: tx['formatted_amount'] as String? ?? '',
                            amountColor: const Color(0xFFEF4444),
                          );
                        }),
                    ]),
                  ),
                ),
              ],
            ),

            // Floating Bottom Nav
            const SmartFinBottomNav(currentIndex: 0),
          ],
        ),
      ),
    );
  }
}
