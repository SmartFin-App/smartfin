import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/core/network/dio_client.dart';
import 'package:smart_fin/widgets/bottom_nav_bar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_fin/features/transactions/data/transaction_repository_impl.dart';
import 'package:smart_fin/features/scanner/services/gallery_watcher_service.dart';
import 'package:smart_fin/features/scanner/presentation/widgets/slip_detection_sheet.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _monthlySummary;
  Map<String, dynamic>? _previousSummary;
  List<Map<String, dynamic>> _recentTransactions = [];
  bool _isLoading = true;
  bool _loadFailed = false;
  Map<String, dynamic>? _savingsProgress;
  String _userName = 'there';
  String _currentMonth = '';

  static const Map<String, ({IconData icon, Color color})> _categoryStyle = {
    'Food':          (icon: Icons.restaurant_outlined,            color: Color(0xFFFF9F29)),
    'Transport':     (icon: Icons.directions_car_outlined,        color: Color(0xFF4A90E2)),
    'Entertainment': (icon: Icons.movie_outlined,                 color: Color(0xFF9C27B0)),
    'Shopping':      (icon: Icons.shopping_bag_outlined,          color: Color(0xFFE91E63)),
    'Health':        (icon: Icons.favorite_outline,               color: Color(0xFFEF4444)),
    'Groceries':     (icon: Icons.local_grocery_store_outlined,   color: Color(0xFF4CAF50)),
    'Bills':         (icon: Icons.receipt_outlined,               color: Color(0xFFFF9800)),
    'Salary':        (icon: Icons.account_balance_wallet_outlined, color: Color(0xFF4CAF50)),
    'Gifts':         (icon: Icons.card_giftcard_outlined,         color: Color(0xFF4A90E2)),
    'Refunds':       (icon: Icons.local_offer_outlined,           color: Color(0xFF4CAF50)),
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
      final slip = await GalleryWatcherService().checkForNewSlips();
      if (slip != null && mounted) {
        SlipDetectionSheet.show(context, slip);
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

  bool get _hasSavingsGoal => _savingsProgress?['has_goal'] == true;

  String _baht(num amount) {
    return '฿${amount.round().toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}';
  }

  /// Progress toward the savings goal. "Saved" is derived server-side by summing
  /// each month's savings since the account was created, so it always agrees with
  /// the transactions rather than being a second figure the user has to maintain.
  Widget _buildSavingsGoalCard() {
    final p = _savingsProgress!;
    final goal = (p['goal'] as num?) ?? 0;
    final saved = (p['saved'] as num?) ?? 0;
    final remaining = (p['remaining'] as num?) ?? 0;
    final pct = ((p['percentage'] as num?) ?? 0).toDouble().clamp(0, 100).toDouble();
    final name = (p['goal_name'] as String?) ?? '';
    final lastMonth = (p['last_month_savings'] as num?) ?? 0;
    final thisMonth = (p['this_month_surplus'] as num?) ?? 0;
    final reached = remaining <= 0 && goal > 0;

    return GestureDetector(
      onTap: () => context.go('/profile'),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.5)),
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
                  child: const Icon(Icons.savings_outlined,
                      size: 19, color: Color(0xFFFF9F29)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isNotEmpty ? name : 'Savings Goal',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: const Color(0xFF333333),
                        ),
                      ),
                      Text(
                        reached
                            ? 'Goal reached 🐾'
                            : '${_baht(remaining)} to go',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          color: reached
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFF9E9E9E),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${pct.round()}%',
                  style: GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: reached
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFFF9F29),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(9999),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 8,
                backgroundColor: const Color.fromRGBO(240, 235, 225, 0.8),
                valueColor: AlwaysStoppedAnimation<Color>(
                  reached ? const Color(0xFF4CAF50) : const Color(0xFFFF9F29),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_baht(saved)} of ${_baht(goal)}',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: const Color(0xFF333333),
                  ),
                ),
                // Last month is what actually moved the bar; the live month is
                // shown only when there is no completed month to report, and is
                // labelled so it never reads as progress already banked.
                if (lastMonth > 0)
                  Text(
                    '+${_baht(lastMonth)} last month',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: const Color(0xFF4CAF50),
                    ),
                  )
                else if (thisMonth > 0)
                  Text(
                    '+${_baht(thisMonth)} so far this month',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: const Color(0xFF9E9E9E),
                    ),
                  ),
              ],
            ),
            if (!reached) ...[
              const SizedBox(height: 12),
              _buildGoalProjection(p),
            ],
          ],
        ),
      ),
    );
  }

  /// One line that turns the goal into a plan. Income minus the chosen budget is
  /// what the user sets aside each month; from that the server estimates months
  /// to the goal and, with a target date, whether the budget gets there in time.
  /// Every figure is computed server-side in whole Baht — this only picks words.
  Widget _buildGoalProjection(Map p) {
    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final budgetSet = p['budget_set'] == true;
    final planned = (p['planned_monthly_saving'] as num?) ?? 0;
    final monthsToGoal = (p['months_to_goal'] as num?)?.toInt();
    final targetParsed = p['target_parsed'] == true;
    final targetPassed = p['target_passed'] == true;
    final requiredMonthly = (p['required_monthly_saving'] as num?) ?? 0;
    final onTrack = p['on_track'] == true;
    final remaining = (p['remaining'] as num?) ?? 0;
    final target = DateTime.tryParse((p['target_date'] as String?) ?? '');
    final targetLabel =
        target != null ? '${monthNames[target.month - 1]} ${target.year}' : '';

    const grey = Color(0xFF9E9E9E);
    const green = Color(0xFF4CAF50);
    const orange = Color(0xFFFF9F29);
    const red = Color(0xFFEF4444);

    final String text;
    final Color color;
    final IconData icon;

    if (!budgetSet) {
      text = 'Set a monthly budget to see how long this goal takes';
      color = grey;
      icon = Icons.info_outline;
    } else if (planned <= 0) {
      text = 'Your budget uses all your income — lower it to start saving';
      color = red;
      icon = Icons.warning_amber_rounded;
    } else if (targetParsed && targetPassed) {
      text = 'Target date has passed · ${_baht(remaining)} still to go';
      color = orange;
      icon = Icons.event_busy_outlined;
    } else if (targetParsed && !onTrack) {
      text =
          'Needs ${_baht(requiredMonthly)}/month by $targetLabel — your budget leaves ${_baht(planned)}';
      color = orange;
      icon = Icons.trending_up;
    } else if (targetParsed) {
      text = '${_baht(planned)}/month planned · on track for $targetLabel';
      color = green;
      icon = Icons.check_circle_outline;
    } else {
      final eta = monthsToGoal == null
          ? ''
          : monthsToGoal <= 1
              ? ' · about a month to go'
              : ' · about $monthsToGoal months to go';
      text = '${_baht(planned)}/month planned$eta';
      color = grey;
      icon = Icons.calendar_month_outlined;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
              height: 1.4,
              color: color,
            ),
          ),
        ),
      ],
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
    int mongoIncome = 0;

    try {
      await Future.wait([
        // Load name from prefs
        SharedPreferences.getInstance().then((prefs) {
          final name = prefs.getString('user_name') ??
              FirebaseAuth.instance.currentUser?.displayName?.split(' ').first ??
              'there';
          if (mounted) setState(() => _userName = name);
        }),
        // Monthly Summary
        DioClient.dio.get(
          '/api/summary/$uid',
          queryParameters: {'month': _currentMonth},
        ).then((res) {
          if (mounted) {
            setState(() {
              _monthlySummary = res.data as Map<String, dynamic>;
              _previousSummary = _monthlySummary?['previous_month'] as Map<String, dynamic>?;
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
        // Savings goal progress — non-fatal, the rest of the dashboard stands
        // without it.
        // Wrapped so a failure here cannot reject the whole Future.wait and take
        // the rest of the dashboard down with it.
        () async {
          try {
            final res =
                await DioClient.dio.get('/api/summary/$uid/savings-goal');
            if (mounted) {
              setState(
                  () => _savingsProgress = res.data as Map<String, dynamic>?);
            }
          } catch (e) {
            debugPrint('Savings progress unavailable: $e');
          }
        }(),
      ]);

      // Fetch user profile from MongoDB and sync SharedPreferences
      if (uid.isNotEmpty) {
        try {
          final userResponse = await DioClient.dio.get('/api/users/$uid');
          final userData = userResponse.data as Map<String, dynamic>;
          mongoIncome = ((userData['monthly_income'] ?? 0) as num).toInt();
          final mongoBudget = ((userData['budget_limit'] ?? 0) as num).toInt();

          if (mongoIncome > 0) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('income_set', true);
            await prefs.setInt('user_income_amount', mongoIncome);
            if (mongoBudget > 0) {
              await prefs.setInt('user_budget_limit', mongoBudget);
            }
            if ((userData['name'] as String?)?.isNotEmpty == true) {
              await prefs.setString('user_name', userData['name'] as String);
              if (mounted) setState(() => _userName = userData['name'] as String);
            }
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

    // Show income setup modal only if BOTH local and MongoDB income are unset
    if (mounted) {
      await _checkIncomeSetup(mongoIncome);
    }
  }

  Future<void> _checkIncomeSetup(int mongoIncome) async {
    final prefs = await SharedPreferences.getInstance();
    final isSetLocally = prefs.getBool('income_set') ?? false;

    // Only show modal if local prefs say not set AND MongoDB has no income
    if (!isSetLocally && mongoIncome == 0 && mounted) {
      final changed = await showDialog<bool>(
        context: context,
        barrierColor: Colors.black.withOpacity(0.2),
        barrierDismissible: false,
        builder: (ctx) => Stack(
          children: [
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
              child: const SizedBox.expand(),
            ),
            const _IncomeSetupDialog(),
          ],
        ),
      );
      if (changed == true && mounted) setState(() {});
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  // ── Top categories ────────────────────────────────────────────────────────
  // Replaces the old budget card, whose headline ("available to spend") was
  // income − expenses. Income is an assumed profile figure credited in full on
  // day one, so that headline was a projection dressed as a balance. Every
  // figure on this card is a recorded expense.

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

  Widget _buildTopCategoriesCard() {
    // Already sorted largest-first server-side, and [] rather than null when
    // there are no expenses — but guard the shape anyway.
    final raw = _monthlySummary?['expense_by_category'];
    final categories =
        (raw is List ? raw : const []).whereType<Map>().take(3).toList();

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
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                'No spending yet this month. Scan a slip or add an expense to see where your money goes 🐾',
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
                color: style.color.withOpacity(0.1),
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
                  color: Colors.black.withOpacity(0.02),
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
                            Text(
                              'Hi $_userName!',
                              style: GoogleFonts.bricolageGrotesque(
                                fontWeight: FontWeight.w800,
                                fontSize: 24,
                                letterSpacing: -0.5,
                                color: const Color(0xFF333333),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => context.push('/profile'),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: const Color(0xFFEAE2D6)),
                                  image: const DecorationImage(
                                    image: AssetImage(
                                        'assets/images/lucky_cat.png'),
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.medium,
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

                      // ── Top Categories ───────────────────────────────────
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

                      if (_hasSavingsGoal) ...[
                        const SizedBox(height: 24),
                        _buildSavingsGoalCard(),
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
                          final bool isIncome =
                              (tx['type'] as String?) == 'income';
                          final String category =
                              tx['category'] as String? ?? '';
                          final style = _categoryStyle[category] ??
                              (isIncome
                                  ? (icon: Icons.account_balance_wallet_outlined, color: const Color(0xFF4CAF50))
                                  : (icon: Icons.attach_money, color: const Color(0xFF9E9E9E)));
                          return _buildTransactionRow(
                            context: context,
                            icon: style.icon,
                            iconColor: style.color,
                            name: tx['merchant'] as String? ?? '-',
                            meta: category.toUpperCase(),
                            amount: tx['formatted_amount'] as String? ?? '',
                            amountColor: isIncome
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFFEF4444),
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

class _IncomeSetupDialog extends StatefulWidget {
  const _IncomeSetupDialog();

  @override
  State<_IncomeSetupDialog> createState() => _IncomeSetupDialogState();
}

class _IncomeSetupDialogState extends State<_IncomeSetupDialog> with TickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;
  late Animation<Offset> _slideAnim;
  
  late AnimationController _cursorController;
  
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _amountController = TextEditingController();
  
  bool _isButtonPressed = false;

  @override
  void initState() {
    super.initState();
    // Entrance animations
    _animController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 500)
    );
    _scaleAnim = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack)
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutQuart)
    );

    // Blinking cursor
    _cursorController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 500)
    )..repeat(reverse: true);

    _animController.forward();

    // Auto focus text field after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });

    _amountController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _cursorController.dispose();
    _focusNode.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _saveIncome() async {
    final cleanText = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid amount')));
      return;
    }
    
    final amount = double.tryParse(cleanText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid amount')));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('income_set', true);
    await prefs.setInt('user_income_amount', amount.round());
    
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  String get formattedAmount {
    String cleanText = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanText.isEmpty) return "0";
    
    double val = double.parse(cleanText);
    String intPart = val.toStringAsFixed(0);
    String result = intPart.replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            return SlideTransition(
              position: _slideAnim,
              child: ScaleTransition(
                scale: _scaleAnim,
                child: child,
              ),
            );
          },
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              // Card
              Container(
                width: MediaQuery.of(context).size.width * 0.9,
                constraints: const BoxConstraints(maxWidth: 380),
                margin: const EdgeInsets.only(top: 48), // Push down to make room for cat
                padding: const EdgeInsets.fromLTRB(32, 72, 32, 32), // 48px covers cat base + 24px spacing = 72px
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 40,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Final piece of the puzzle!",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.bricolageGrotesque(
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                        letterSpacing: -1,
                        color: const Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        "An exact number helps our AI calculate your daily budget more accurately.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter( // Inter as safe fallback for Geist
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          height: 1.5,
                          color: const Color(0xFF9E9E9E),
                        ),
                      ),
                    ),
                    
                    // Invisible TextField and Display
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 40),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "฿ ",
                                style: GoogleFonts.bricolageGrotesque(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 36,
                                  color: const Color(0xFFFF9F29),
                                ),
                              ),
                              Text(
                                formattedAmount,
                                style: GoogleFonts.bricolageGrotesque(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 36,
                                  color: const Color(0xFF333333),
                                ),
                              ),
                              const SizedBox(width: 4),
                              FadeTransition(
                                opacity: _cursorController,
                                child: Container(
                                  width: 2,
                                  height: 36,
                                  color: const Color(0xFFFF9F29),
                                ),
                              ),
                            ],
                          ),
                          // Transparent text field capturing keyboard input over the whole area
                          Positioned.fill(
                            child: TextField(
                              controller: _amountController,
                              focusNode: _focusNode,
                              keyboardType: TextInputType.number,
                              showCursor: false,
                              style: const TextStyle(color: Colors.transparent, fontSize: 1), // Invisible text
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // "Set Income" Button
                    GestureDetector(
                      onTapDown: (_) => setState(() => _isButtonPressed = true),
                      onTapUp: (_) {
                        setState(() => _isButtonPressed = false);
                        _saveIncome();
                      },
                      onTapCancel: () => setState(() => _isButtonPressed = false),
                      child: AnimatedScale(
                        scale: _isButtonPressed ? 0.98 : 1.0,
                        duration: const Duration(milliseconds: 100),
                        child: Container(
                          width: double.infinity,
                          height: 58,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9F29),
                            borderRadius: BorderRadius.circular(9999),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFF9F29).withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Text(
                            "SET INCOME",
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

                    const SizedBox(height: 16),

                    // "Maybe Later" Button
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(false),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          "MAYBE LATER",
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                            letterSpacing: 2,
                            color: const Color(0xFF9E9E9E),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Floating Cat
              Positioned(
                top: 0, // The stack is topCenter, card is margin top 48. This sits at 0, meaning it overflows 48px above the card!
                child: Image.asset(
                  'assets/images/lucky_cat.png',
                  width: 96,
                  height: 96,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
