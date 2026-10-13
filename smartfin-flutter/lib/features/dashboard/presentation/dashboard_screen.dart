import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_fin/widgets/ui/ui.dart';
import 'package:smart_fin/core/network/dio_client.dart';
import 'package:smart_fin/widgets/bottom_nav_bar.dart';
import 'package:smart_fin/widgets/page_title_row.dart';
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

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _monthlySummary;
  List<Map<String, dynamic>> _recentTransactions = [];
  bool _isLoading = true;
  bool _loadFailed = false;
  // Active bills overdue or due within 7 days, soonest first.
  List<Map<String, dynamic>> _upcomingBills = [];
  int _upcomingTotal = 0;
  String _currentMonth = '';

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
    'Other': (icon: Icons.attach_money, color: Color(0xFF9E9E9E)),
  };

  /// A resume while the earlier-slips question is open must not stack a second one.
  bool _checkingSlips = false;

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

  /// Asks a new install, once, whether to add the slips already saved this
  /// month. Not dismissible: closing it unanswered would ask again on every
  /// resume.
  Future<void> _askAboutEarlierSlips(EarlierSlipsOffer offer) async {
    final since = DateFormat(
      'd MMMM',
    ).format(offer.monthStart.toUtc().add(const Duration(hours: 7)));
    final slips = offer.count == 1 ? '1 slip' : '${offer.count} slips';
    final include = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Add earlier slips from this month?'),
          content: Text(
            'We found $slips saved since $since, before you set up Auto-Detect. '
            'Add them to this month, or only track slips from today.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              child: const Text('Start from today'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add them'),
            ),
          ],
        ),
      ),
    );
    if (include == null) return;
    await GalleryWatcherService().answerEarlierSlipsOffer(
      offer,
      include: include,
    );
  }

  Future<void> _checkForNewSlips() async {
    if (!mounted || _checkingSlips) return;
    _checkingSlips = true;
    try {
      final watcher = GalleryWatcherService();
      final offer = await watcher.pendingEarlierSlipsOffer();
      if (!mounted) return;
      if (offer != null) {
        await _askAboutEarlierSlips(offer);
        if (!mounted) return;
      }

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
              "We couldn't find your slip folder. Pick one so SmartFin can spot new slips.",
            ),
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
    } finally {
      _checkingSlips = false;
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
        DioClient.dio
            .get('/api/summary/$uid', queryParameters: {'month': _currentMonth})
            .then((res) {
              if (mounted) {
                setState(() {
                  _monthlySummary = res.data as Map<String, dynamic>;
                });
              }
            }),
        // Recent 3
        TransactionRepositoryImpl().getTransactions(userID: uid, limit: 3).then(
          (res) {
            if (res.success && mounted) {
              setState(() => _recentTransactions = res.data ?? []);
            }
          },
        ),
        // Upcoming bills — non-fatal, the rest of the dashboard stands without
        // them. Wrapped so a failure here cannot reject the whole Future.wait and
        // take the rest of the dashboard down with it.
        () async {
          try {
            final res = await SubscriptionRepositoryImpl().getSubscriptions(
              userID: uid,
              activeOnly: true,
            );
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
              _upcomingTotal =
                  (res.data?['due_soon_total'] as num?)?.toInt() ?? 0;
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

  Future<void> _openProfileForBudget() async {
    await context.push('/profile');
    if (mounted) _loadData();
  }

  Future<void> _openTransaction(Map<String, dynamic> tx) async {
    final id = tx['id'] as String?;
    if (id == null || id.isEmpty) return;
    // Detail returns true when the record was edited or deleted.
    final changed = await context.push<bool>('/transaction/$id');
    if (changed == true && mounted) _loadData();
  }

  void _openCategory(String category) {
    // Type and month travel with the category so History's totals match the
    // card: category alone would pull that category's transactions from every
    // month.
    context.push(
      Uri(
        path: '/history',
        queryParameters: {
          'type': 'expense',
          if (category.isNotEmpty) 'category': category,
          if (_currentMonth.isNotEmpty) 'month': _currentMonth,
        },
      ).toString(),
    );
  }

  ({IconData icon, Color color}) _styleFor(String? category) =>
      _categoryStyle[category?.trim()] ?? _categoryStyle['Other']!;

  // ── Budget donut + top categories ─────────────────────────────────────────
  // Replaces the old budget card, whose headline ("available to spend") was
  // income − expenses. Income is an assumed profile figure credited in full on
  // day one, so that headline was a projection dressed as a balance. Every
  // figure on this card is a recorded expense or the user's own budget limit.

  /// Placeholder shaped like the loaded card, so the layout doesn't jump.
  Widget _buildBudgetCardSkeleton() {
    return AppCard(
      flat: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Skeleton(width: 140, height: 18),
          const SizedBox(height: AppSpacing.sm),
          const Skeleton(width: 90, height: 12),
          const SizedBox(height: AppSpacing.xl),
          const Center(child: Skeleton.circle(size: 180)),
          const SizedBox(height: AppSpacing.xl),
          for (var i = 0; i < 3; i++) ...[
            const SizedBox(height: AppSpacing.lg),
            const Row(
              children: [
                Skeleton(width: 36, height: 36, radius: AppRadius.md),
                SizedBox(width: AppSpacing.md),
                Expanded(child: Skeleton(height: 14)),
              ],
            ),
          ],
        ],
      ),
    );
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
            color: _styleFor(c['category'] as String?).color,
            radius: 18,
            showTitle: false,
          ),
      if (hasBudget && spent < budget)
        PieChartSectionData(
          value: (budget - spent).toDouble(),
          color: AppColors.surfaceMuted,
          radius: 18,
          showTitle: false,
        ),
    ];
    // fl_chart draws nothing for an all-zero pie; keep the empty ring visible.
    if (sections.isEmpty) {
      sections.add(
        PieChartSectionData(
          value: 1,
          color: AppColors.surfaceMuted,
          radius: 18,
          showTitle: false,
        ),
      );
    }

    final String status;
    final Color statusColor;
    if (!hasBudget) {
      status = 'No budget set';
      statusColor = AppColors.textSecondary;
    } else if (over) {
      status = '${_baht(spent - budget)} over';
      statusColor = AppColors.danger;
    } else {
      status = '${_baht(budget - spent)} left';
      statusColor = AppColors.success;
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
                  centerSpaceRadius: 76,
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
                    style: AppTextStyles.display.copyWith(
                      fontSize: 28,
                      color: over ? AppColors.danger : AppColors.textDark,
                    ),
                  ),
                  if (hasBudget)
                    Text('of ${_baht(budget)}', style: AppTextStyles.caption),
                  const SizedBox(height: AppSpacing.sm),
                  // A tinted pill, so the verdict reads at a glance.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      status,
                      style: AppTextStyles.label.copyWith(
                        fontSize: 12,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!hasBudget) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton.text(
            label: 'Set a monthly budget',
            icon: Icons.add_rounded,
            onPressed: _openProfileForBudget,
          ),
        ],
      ],
    );
  }

  Widget _buildBudgetCard() {
    // Already sorted largest-first server-side, and [] rather than null when
    // there are no expenses — but guard the shape anyway.
    final raw = _monthlySummary?['expense_by_category'];
    final allCategories = (raw is List ? raw : const [])
        .whereType<Map>()
        .toList();
    final categories = allCategories.take(3).toList();
    final month = (_monthlySummary?['formatted_month'] as String?) ?? '';

    return AppCard(
      onTap: () => context.push('/history'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monthly budget', style: AppTextStyles.heading),
          if (month.isNotEmpty) Text(month, style: AppTextStyles.caption),
          const SizedBox(height: AppSpacing.lg),
          _buildBudgetDonut(allCategories),
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Top categories',
            style: AppTextStyles.label.copyWith(color: AppColors.textSecondary),
          ),
          if (categories.isEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No spending yet this month. Scan a slip or add an expense to see where your money goes.',
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ] else
            for (final c in categories) _buildCategoryRow(c),
        ],
      ),
    );
  }

  Widget _buildCategoryRow(Map c) {
    final name = (c['category'] as String?)?.trim();
    final label = (name == null || name.isEmpty) ? 'Other' : name;
    final amount = (c['amount'] as num?) ?? 0;
    final pct = ((c['percentage'] as num?) ?? 0).toDouble();
    final style = _styleFor(label);

    // Its own ink target, so a tap on the row opens this category rather than
    // the card's unfiltered History.
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () => _openCategory(name ?? ''),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            IconTile(icon: style.icon, color: style.color, size: 40),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyStrong,
                        ),
                      ),
                      Text(_baht(amount), style: AppTextStyles.amount),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: LinearProgressIndicator(
                            value: (pct / 100).clamp(0.0, 1.0),
                            minHeight: 6,
                            color: style.color,
                            backgroundColor: AppColors.surfaceMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      SizedBox(
                        width: 36,
                        child: Text(
                          '${pct.round()}%',
                          textAlign: TextAlign.right,
                          style: AppTextStyles.caption.copyWith(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Upcoming bills ────────────────────────────────────────────────────────

  /// Bills that are overdue or due within a week. Hidden when there are none, so
  /// it never adds an empty card for users who don't track bills. The figures and
  /// day counts come from the server in Thai time; this only picks the wording.
  Widget _buildUpcomingBillsCard() {
    final count = _upcomingBills.length;
    return AppCard(
      onTap: _openSubscriptions,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        children: [
          ListRow(
            leading: const IconTile(
              icon: Icons.event_repeat_rounded,
              color: AppColors.primary,
            ),
            title: 'Upcoming bills',
            subtitle:
                '${_baht(_upcomingTotal)} · $count bill${count == 1 ? '' : 's'}',
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted,
            ),
          ),
          ListRow.divider(indent: AppSpacing.lg),
          ..._upcomingBills.take(3).map(_buildUpcomingBillRow),
        ],
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
    final whenColor = days < 0 ? AppColors.danger : AppColors.primaryText;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              bill['name'] as String? ?? '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: whenColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              when,
              style: AppTextStyles.label.copyWith(
                fontSize: 12,
                color: whenColor,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            bill['formatted_amount'] as String? ??
                _baht((bill['amount'] as num?) ?? 0),
            style: AppTextStyles.amount,
          ),
        ],
      ),
    );
  }

  // ── Recent activity ───────────────────────────────────────────────────────

  Widget _buildRecentActivity() {
    if (_isLoading) {
      return AppCard(
        flat: true,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          children: [
            for (var i = 0; i < 3; i++)
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
                          Skeleton(width: 120, height: 14),
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

    if (_recentTransactions.isEmpty) {
      return const AppCard(
        flat: true,
        child: StatusMessage(
          icon: Icons.receipt_long_rounded,
          title: 'No expenses yet',
          message: 'Scan a slip or tap + to add your first one.',
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        children: [
          for (var i = 0; i < _recentTransactions.length; i++) ...[
            if (i > 0) ListRow.divider(),
            _buildTransactionRow(_recentTransactions[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildTransactionRow(Map<String, dynamic> tx) {
    final category = tx['category'] as String? ?? '';
    final style = _styleFor(category);
    final date = tx['formatted_date'] as String? ?? '';
    return ListRow(
      leading: IconTile(icon: style.icon, color: style.color),
      title: tx['merchant'] as String? ?? '-',
      subtitle: [category, date].where((s) => s.isNotEmpty).join(' · '),
      trailing: Text(
        tx['formatted_amount'] as String? ?? '',
        style: AppTextStyles.amount,
      ),
      onTap: () => _openTransaction(tx),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _loadData,
        child: Stack(
          children: [
            CustomScrollView(
              physics: const ClampingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                // ── Sticky Header ──────────────────────────────────────────
                // Logo row: 48 from the top, 40 tall, then 8 of breathing room.
                SliverAppBar(
                  pinned: true,
                  toolbarHeight: PageTitleRow.barHeight(context, 96),
                  expandedHeight: PageTitleRow.barHeight(context, 96),
                  collapsedHeight: PageTitleRow.barHeight(context, 96),
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
                          left: AppSpacing.screen,
                          right: AppSpacing.screen,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Brand mark rather than a greeting: the name told
                            // the user nothing they did not know, and the logo
                            // gives every screenshot an identifiable header.
                            const SmartFinLogo(),
                            // A person icon: cat imagery belongs to the AI
                            // Coach only.
                            Material(
                              color: AppColors.white,
                              shape: const CircleBorder(
                                side: BorderSide(color: AppColors.border),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => context.push('/profile'),
                                child: const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Icon(
                                    Icons.person_outline_rounded,
                                    size: 22,
                                    color: AppColors.textDark,
                                    semanticLabel: 'Profile',
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
                    left: AppSpacing.screen,
                    right: AppSpacing.screen,
                    top: AppSpacing.sm,
                    bottom: 120,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // ── Budget donut + Top Categories ────────────────────
                      // A failed load must not render as a real ฿0 month.
                      if (_loadFailed && !_isLoading)
                        AppCard(
                          flat: true,
                          child: StatusMessage(
                            icon: Icons.cloud_off_rounded,
                            title: "Couldn't load this month",
                            message: 'Check your connection, then try again.',
                            action: AppButton.secondary(
                              label: 'Try again',
                              icon: Icons.refresh_rounded,
                              onPressed: _loadData,
                            ),
                          ),
                        )
                      else if (_isLoading)
                        _buildBudgetCardSkeleton()
                      else
                        _buildBudgetCard(),

                      if (!_isLoading && _upcomingBills.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _buildUpcomingBillsCard(),
                      ],

                      const SizedBox(height: AppSpacing.xl),

                      // ── Recent Activity ──────────────────────────────────
                      SectionHeader(
                        title: 'Recent activity',
                        actionLabel: 'See all',
                        onAction: () => context.push('/history'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _buildRecentActivity(),
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
