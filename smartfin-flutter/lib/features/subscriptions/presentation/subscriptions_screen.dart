import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:smart_fin/widgets/ui/ui.dart';
import 'package:smart_fin/features/subscriptions/data/subscription_repository_impl.dart';
import 'package:smart_fin/features/subscriptions/services/bill_reminder_service.dart';
import 'package:smart_fin/features/transactions/data/transaction_repository_impl.dart';

/// Subscriptions & bills the user tracks by hand: what is overdue, what is due
/// this week, and what they cost per month. "Mark paid" logs the bill as an
/// expense and moves its due date on a cycle.
///
/// Reached with `context.push`, and pops `true` when anything changed so the
/// caller (Profile or the dashboard card) can refresh.
class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  static const List<String> _categories = [
    'Bills',
    'Entertainment',
    'Health',
    'Transport',
    'Shopping',
    'Food',
    'Groceries',
    'Other',
  ];
  static const List<String> _cycles = ['weekly', 'monthly', 'yearly'];

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

  List<Map<String, dynamic>> _subs = [];
  Map<String, dynamic> _envelope = {};
  bool _isLoading = true;
  bool _isBusy = false;
  String? _error;

  /// Set when anything is added, changed, paid or removed.
  bool _changed = false;

  /// Bills with a "Mark paid" request in flight, so a second tap does nothing.
  final Set<String> _paying = {};

  /// Notification permission is asked for once per visit, and only once there
  /// is an active bill to be reminded about.
  bool _askedPermission = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      // Keep the current list on screen during a refresh.
      _isLoading = _subs.isEmpty;
      _error = null;
    });

    if (_uid.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'You need to be signed in to see your bills.';
      });
      return;
    }

    final res = await SubscriptionRepositoryImpl().getSubscriptions(
      userID: _uid,
    );
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (res.success) {
        _envelope = res.data ?? {};
        _subs = ((_envelope['subscriptions'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _error = res.error ?? 'Could not load your bills.';
      }
    });

    if (res.success) {
      // Every load reschedules reminders, so edits, payments, pauses and
      // deletions never leave a stale one behind.
      BillReminderService().syncAll(_subs);
      if (!_askedPermission && _subs.any((s) => s['active'] == true)) {
        _askedPermission = true;
        BillReminderService().requestPermission();
      }
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    showAppToast(context, message, error: error);
  }

  String _baht(num amount) =>
      '฿${amount.round().toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")}';

  /// A server "YYYY-MM-DD" as a plain calendar date — no time-zone conversion.
  DateTime? _day(String? raw) => raw == null ? null : DateTime.tryParse(raw);

  String _cycleLabel(String? cycle) => switch (cycle) {
    'weekly' => 'Weekly',
    'yearly' => 'Yearly',
    _ => 'Monthly',
  };
  ({String text, Color fg}) _badge(Map<String, dynamic> s) {
    if (s['active'] != true) {
      return (text: 'Paused', fg: AppColors.textSecondary);
    }
    final days = (s['days_until_due'] as num?)?.toInt() ?? 0;
    if (days < 0) {
      final n = -days;
      return (text: '$n day${n == 1 ? '' : 's'} overdue', fg: AppColors.danger);
    }
    if (days == 0) return (text: 'Due today', fg: AppColors.primaryText);
    if (days == 1) return (text: 'Due tomorrow', fg: AppColors.primaryText);
    if (days <= 7) {
      return (text: 'Due in $days days', fg: AppColors.primaryText);
    }
    return (
      text: 'Due ${s['formatted_due_date'] ?? ''}',
      fg: AppColors.textSecondary,
    );
  }

  ({IconData icon, Color color}) _styleFor(String? category) =>
      _categoryStyle[category] ?? _categoryStyle['Other']!;

  Widget _sheetLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Text(
      text,
      style: AppTextStyles.label.copyWith(color: AppColors.textSecondary),
    ),
  );

  // ── Add / edit ──────────────────────────────────────────────────────────────

  Future<void> _openEditor({Map<String, dynamic>? sub}) async {
    if (_isBusy) return;
    final isEdit = sub != null;

    final nameController = TextEditingController(
      text: sub?['name'] as String? ?? '',
    );
    final amountController = TextEditingController(
      text: sub == null
          ? ''
          : ((sub['amount'] as num?) ?? 0).round().toString(),
    );
    final noteController = TextEditingController(
      text: sub?['note'] as String? ?? '',
    );
    String cycle = sub?['billing_cycle'] as String? ?? 'monthly';
    String category = sub?['category'] as String? ?? 'Bills';
    if (!_categories.contains(category)) category = 'Other';
    final today = DateUtils.dateOnly(DateTime.now());
    final originalDue = _day(sub?['due_date'] as String?);
    DateTime due = originalDue ?? today;
    bool active = sub?['active'] as bool? ?? true;
    bool closing = false;

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void close(String result) {
            // A second tap while the sheet animates out would pop this screen.
            if (closing) return;
            closing = true;
            Navigator.pop(ctx, result);
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
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
                      Text(
                        isEdit ? 'Edit bill' : 'Add a bill',
                        style: AppTextStyles.title,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      TextField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        maxLength: 60,
                        style: AppTextStyles.body,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          hintText: 'e.g. Netflix, phone bill',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: AppTextStyles.body,
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          prefixText: '฿ ',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _sheetLabel('Repeats'),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: _cycles
                            .map(
                              (c) => AppChip(
                                label: _cycleLabel(c),
                                selected: c == cycle,
                                onTap: () => setSheet(() => cycle = c),
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
                          title: 'Next due',
                          trailing: Text(
                            DateFormat('d MMM yyyy').format(due),
                            style: AppTextStyles.label.copyWith(
                              color: AppColors.primaryText,
                            ),
                          ),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: due,
                              // Past dates are allowed for a bill that is
                              // already overdue; future ones for everything
                              // else.
                              firstDate: today.subtract(
                                const Duration(days: 365),
                              ),
                              lastDate: DateTime(today.year + 5, 12, 31),
                            );
                            if (picked != null) setSheet(() => due = picked);
                          },
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _sheetLabel('Category'),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: _categories
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
                      TextField(
                        controller: noteController,
                        maxLength: 200,
                        style: AppTextStyles.body,
                        decoration: const InputDecoration(
                          labelText: 'Note (optional)',
                          counterText: '',
                        ),
                      ),
                      if (isEdit) ...[
                        const SizedBox(height: AppSpacing.md),
                        AppCard(
                          flat: true,
                          padding: EdgeInsets.zero,
                          child: ListRow(
                            title: 'Active',
                            subtitle:
                                'Paused bills are not counted or reminded',
                            trailing: Switch(
                              value: active,
                              onChanged: (v) => setSheet(() => active = v),
                            ),
                            onTap: () => setSheet(() => active = !active),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xl),
                      AppButton(
                        label: isEdit ? 'Save changes' : 'Add bill',
                        expand: true,
                        onPressed: () {
                          final amount =
                              int.tryParse(amountController.text.trim()) ?? 0;
                          if (nameController.text.trim().isEmpty) {
                            _toast('Give the bill a name', error: true);
                            return;
                          }
                          if (amount <= 0) {
                            _toast(
                              'Amount must be greater than 0',
                              error: true,
                            );
                            return;
                          }
                          close('save');
                        },
                      ),
                      if (isEdit) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Center(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.danger,
                            ),
                            onPressed: () => close('delete'),
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
                            label: const Text('Delete bill'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'delete') {
      await _delete(sub!);
      return;
    }

    setState(() => _isBusy = true);
    final repo = SubscriptionRepositoryImpl();
    final name = nameController.text.trim();
    final amount = int.tryParse(amountController.text.trim()) ?? 0;
    final note = noteController.text.trim();
    final res = isEdit
        ? await repo.updateSubscription(
            subscriptionID: sub['id'] as String? ?? '',
            userID: _uid,
            name: name,
            amount: amount,
            billingCycle: cycle,
            // Only send the date when it was changed: the server re-anchors the
            // billing day to whatever date it receives, so resending a date that
            // was clamped to a short month (31st -> 28th) would move the bill.
            nextDueDate: due == originalDue ? null : due,
            category: category,
            note: note,
            active: active,
          )
        : await repo.createSubscription(
            userID: _uid,
            name: name,
            amount: amount,
            billingCycle: cycle,
            nextDueDate: due,
            category: category,
            note: note,
          );
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (res.success) {
      _changed = true;
      _toast(isEdit ? 'Bill updated' : '$name added');
      await _load();
    } else {
      _toast(res.error ?? 'Could not save this bill', error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> sub) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${sub['name'] ?? 'bill'}?'),
        content: const Text(
          'It stops being tracked. Payments you already logged stay in your history.',
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
    final id = sub['id'] as String? ?? '';
    final res = await SubscriptionRepositoryImpl().deleteSubscription(
      subscriptionID: id,
      userID: _uid,
    );
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (res.success) {
      _changed = true;
      _toast('Bill deleted');
      await BillReminderService().cancelFor(id);
      await _load();
    } else {
      _toast(res.error ?? 'Could not delete this bill', error: true);
    }
  }

  // ── Mark paid ───────────────────────────────────────────────────────────────

  Future<void> _markPaid(Map<String, dynamic> sub) async {
    final id = sub['id'] as String? ?? '';
    if (id.isEmpty || _paying.contains(id) || _isBusy) return;

    // The payment may already be in the history, usually because its slip
    // was scanned. Then only the due date needs to move. A failed check is
    // treated as no match, so paying still works offline from this lookup.
    setState(() => _paying.add(id));
    var matches = const <Map<String, dynamic>>[];
    try {
      final amount = (sub['amount'] as num?)?.round() ?? 0;
      if (amount > 0) {
        final existing = await TransactionRepositoryImpl()
            .findPossibleDuplicates(userID: _uid, amount: amount);
        if (existing.success) matches = existing.data ?? matches;
      }
    } finally {
      if (mounted) setState(() => _paying.remove(id));
    }
    if (!mounted) return;

    final next = _day(sub['next_due_after_payment'] as String?);
    final nextLabel = next != null
        ? DateFormat('d MMM yyyy').format(next)
        : null;
    final choice = await showDialog<PayChoice>(
      context: context,
      builder: (ctx) => MarkPaidDialog(
        name: sub['name'] as String? ?? 'this bill',
        formattedAmount: sub['formatted_amount'] as String? ?? '',
        category: sub['category'] as String? ?? '',
        nextDueLabel: nextLabel,
        matches: matches,
      ),
    );
    if (choice == null || !mounted || _paying.contains(id)) return;

    setState(() => _paying.add(id));
    try {
      final res = await SubscriptionRepositoryImpl().markPaid(
        subscriptionID: id,
        userID: _uid,
        expectedDueDate: sub['due_date'] as String? ?? '',
        skipExpense: choice == PayChoice.dateOnly,
      );
      if (!mounted) return;
      if (res.success) {
        _changed = true;
        _toast('${res.data?['message'] ?? 'Marked as paid'}');
      } else {
        _toast(res.error ?? 'Could not mark this bill as paid', error: true);
      }
    } finally {
      if (mounted) setState(() => _paying.remove(id));
    }
    // Reload either way: after a 409 the row must show where the bill really is.
    if (mounted) await _load();
  }

  // ── Reminders ───────────────────────────────────────────────────────────────

  /// Explains the reminders and lets the user fire a test one — reminders are
  /// otherwise at 09:00, which nobody wants to wait for to check they work.
  Future<void> _showReminderSheet() async {
    final service = BillReminderService();
    final enabled = await service.notificationsEnabled();
    if (!mounted) return;
    Map<String, dynamic>? sample;
    for (final s in _subs) {
      if (s['active'] == true) {
        sample = s;
        break;
      }
    }

    Future<void> run(
      BuildContext sheetContext,
      Future<bool> Function() send,
      String ok,
    ) async {
      Navigator.pop(sheetContext);
      final granted = await service.requestPermission();
      if (!granted) {
        _toast(
          'Notifications are off for SmartFin. Turn them on in Settings.',
          error: true,
        );
        return;
      }
      _toast(
        await send() ? ok : 'Could not send a test reminder',
        error: false,
      );
    }

    const chevron = Icon(
      Icons.chevron_right_rounded,
      color: AppColors.textMuted,
    );

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bill reminders', style: AppTextStyles.title),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'SmartFin reminds you at 9:00 the day before a bill is due, and again on the day.',
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ListRow(
                leading: const IconTile(
                  icon: Icons.notifications_active_outlined,
                  color: AppColors.primary,
                ),
                title: 'Send a test reminder now',
                trailing: chevron,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
                onTap: () => run(
                  ctx,
                  () => service.showTestNow(sample),
                  'Test reminder sent',
                ),
              ),
              ListRow(
                leading: const IconTile(
                  icon: Icons.timer_outlined,
                  color: AppColors.primary,
                ),
                title: 'Remind me in 10 seconds',
                subtitle: 'Go to the home screen to see it arrive',
                trailing: chevron,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
                onTap: () => run(
                  ctx,
                  () => service.scheduleTest(seconds: 10, bill: sample),
                  'Scheduled — it may take a few seconds longer',
                ),
              ),
              if (!enabled)
                ListRow(
                  leading: const IconTile(
                    icon: Icons.settings_outlined,
                    color: AppColors.primary,
                  ),
                  title: 'Turn on notifications',
                  subtitle: 'Notifications are currently off for SmartFin',
                  trailing: chevron,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.md,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    service.openSettings();
                  },
                ),
            ],
          ),
        ),
      ),
    );
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
            RefreshIndicator(
              color: AppColors.primary,
              edgeOffset: SubpageHeader.contentTop,
              onRefresh: _load,
              child: ListView(
                physics: const ClampingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screen,
                  SubpageHeader.contentTop,
                  AppSpacing.screen,
                  48,
                ),
                children: _buildBody(),
              ),
            ),
            SubpageHeader(
              title: 'Subscriptions & bills',
              onBack: () => context.pop(_changed),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIconButton(
                    icon: Icons.notifications_none_rounded,
                    semanticLabel: 'Reminders',
                    onPressed: _showReminderSheet,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppIconButton(
                    icon: Icons.add_rounded,
                    semanticLabel: 'Add a bill',
                    filled: true,
                    onPressed: () => _openEditor(),
                  ),
                ],
              ),
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

  List<Widget> _buildBody() {
    if (_isLoading) {
      return const [
        SizedBox(height: 160),
        Center(child: CircularProgressIndicator()),
      ];
    }
    if (_error != null) {
      return [
        const SizedBox(height: 60),
        StatusMessage(
          icon: Icons.cloud_off_rounded,
          title: "Couldn't load your bills",
          message: _error,
          action: AppButton.secondary(
            label: 'Try again',
            icon: Icons.refresh_rounded,
            onPressed: _load,
          ),
        ),
      ];
    }
    if (_subs.isEmpty) {
      return [
        const SizedBox(height: 60),
        StatusMessage(
          icon: Icons.event_repeat_rounded,
          title: 'No bills tracked yet',
          message:
              "Add Netflix, your phone plan or rent and SmartFin will remind you before they're due.",
          action: AppButton(
            label: 'Add a bill',
            icon: Icons.add_rounded,
            onPressed: () => _openEditor(),
          ),
        ),
      ];
    }

    final overdue = _subs.where((s) => s['status'] == 'overdue').toList();
    final soon = _subs
        .where((s) => s['status'] == 'due_today' || s['status'] == 'due_soon')
        .toList();
    final later = _subs.where((s) => s['status'] == 'upcoming').toList();
    final paused = _subs.where((s) => s['status'] == 'paused').toList();

    return [
      const SizedBox(height: AppSpacing.sm),
      _buildSummaryCard(),
      if (overdue.isNotEmpty)
        _section('Overdue', overdue, color: AppColors.danger),
      if (soon.isNotEmpty) _section('Due in the next 7 days', soon),
      if (later.isNotEmpty) _section('Later', later),
      if (paused.isNotEmpty) _section('Paused', paused),
    ];
  }

  Widget _section(
    String title,
    List<Map<String, dynamic>> items, {
    Color color = AppColors.textSecondary,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: Text(
              title,
              style: AppTextStyles.label.copyWith(color: color),
            ),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) ListRow.divider(),
                  _buildRow(items[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final total = (_envelope['monthly_total'] as num?) ?? 0;
    final active = (_envelope['active_count'] as num?)?.toInt() ?? 0;
    final overdue = (_envelope['overdue_count'] as num?)?.toInt() ?? 0;
    final soon = (_envelope['due_soon_count'] as num?)?.toInt() ?? 0;
    final parts = [
      '$active active',
      if (overdue > 0) '$overdue overdue',
      if (soon > 0) '$soon due this week',
    ];

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Monthly total', style: AppTextStyles.caption),
                const SizedBox(height: AppSpacing.xs),
                Text(_baht(total), style: AppTextStyles.display),
                const SizedBox(height: AppSpacing.xs),
                Text(parts.join(' · '), style: AppTextStyles.caption),
              ],
            ),
          ),
          const IconTile(
            icon: Icons.event_repeat_rounded,
            color: AppColors.primary,
            size: 52,
          ),
        ],
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> s) {
    final id = s['id'] as String? ?? '';
    final active = s['active'] == true;
    final category = s['category'] as String? ?? 'Other';
    final style = _styleFor(category);
    final badge = _badge(s);
    final paying = _paying.contains(id);

    return Opacity(
      opacity: active ? 1 : 0.6,
      child: InkWell(
        onTap: () => _openEditor(sub: s),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              IconTile(icon: style.icon, color: style.color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s['name'] as String? ?? '-',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyStrong,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_cycleLabel(s['billing_cycle'] as String?)} · ${badge.text}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(color: badge.fg),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    s['formatted_amount'] as String? ??
                        _baht((s['amount'] as num?) ?? 0),
                    style: AppTextStyles.amount,
                  ),
                  if (active) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _markPaidButton(s, paying),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _markPaidButton(Map<String, dynamic> s, bool paying) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.14),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: paying ? null : () => _markPaid(s),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (paying)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: AppColors.primaryText,
                ),
              const SizedBox(width: 4),
              Text(
                'Mark paid',
                style: AppTextStyles.label.copyWith(
                  fontSize: 12,
                  color: AppColors.primaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How a bill is marked paid: logging the expense, or only moving its due date
/// because the payment is already in the history.
enum PayChoice { logExpense, dateOnly }

/// Confirms "Mark paid". With no [matches] it is the plain confirmation. With
/// some, the payment looks already recorded, so it offers to move the due date
/// without logging it a second time.
class MarkPaidDialog extends StatelessWidget {
  final String name;
  final String formattedAmount;
  final String category;
  final String? nextDueLabel;
  final List<Map<String, dynamic>> matches;

  const MarkPaidDialog({
    super.key,
    required this.name,
    required this.formattedAmount,
    required this.category,
    required this.nextDueLabel,
    this.matches = const [],
  });

  @override
  Widget build(BuildContext context) {
    final cancel = TextButton(
      onPressed: () => Navigator.pop(context),
      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
      child: const Text('Cancel'),
    );

    if (matches.isEmpty) {
      return AlertDialog(
        title: Text('Mark $name as paid?'),
        content: Text(
          'Logs a $formattedAmount $category expense for today'
          '${nextDueLabel != null ? ' and moves the next due date to $nextDueLabel' : ''}.',
        ),
        actions: [
          cancel,
          TextButton(
            onPressed: () => Navigator.pop(context, PayChoice.logExpense),
            child: const Text('Mark paid'),
          ),
        ],
      );
    }

    return AlertDialog(
      // Up to three matches and three stacked actions: scroll on a small phone.
      scrollable: true,
      title: const Text('Already in your history?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'An expense of $formattedAmount is already recorded:',
            style: AppTextStyles.body,
          ),
          for (final tx in matches) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              tx['merchant'] as String? ?? '-',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyStrong,
            ),
            Text(
              [
                tx['formatted_amount'] as String? ?? '',
                tx['formatted_date'] as String? ?? '',
              ].where((part) => part.isNotEmpty).join(' · '),
              style: AppTextStyles.caption,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            'If that is this payment, just move the due date'
            '${nextDueLabel != null ? ' to $nextDueLabel' : ''}. '
            'Logging it too would count it twice.',
            style: AppTextStyles.body,
          ),
        ],
      ),
      actions: [
        cancel,
        TextButton(
          onPressed: () => Navigator.pop(context, PayChoice.logExpense),
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
          child: const Text('Log it too'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, PayChoice.dateOnly),
          child: const Text('Move date only'),
        ),
      ],
    );
  }
}
