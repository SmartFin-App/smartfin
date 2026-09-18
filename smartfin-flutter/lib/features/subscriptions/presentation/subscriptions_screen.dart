import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:smart_fin/constants/color_style.dart';
import 'package:smart_fin/features/subscriptions/data/subscription_repository_impl.dart';
import 'package:smart_fin/features/subscriptions/services/bill_reminder_service.dart';

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
    'Bills', 'Entertainment', 'Health', 'Transport', 'Shopping', 'Food', 'Groceries', 'Other',
  ];
  static const List<String> _cycles = ['weekly', 'monthly', 'yearly'];

  static const Map<String, ({IconData icon, Color color})> _categoryStyle = {
    'Food':          (icon: Icons.restaurant_outlined,          color: Color(0xFFFF9F29)),
    'Transport':     (icon: Icons.directions_car_outlined,      color: Color(0xFF2563EB)),
    'Entertainment': (icon: Icons.movie_outlined,               color: Color(0xFF7C3AED)),
    'Shopping':      (icon: Icons.shopping_bag_outlined,        color: Color(0xFFDB2777)),
    'Health':        (icon: Icons.favorite_outline,             color: Color(0xFFDC2626)),
    'Groceries':     (icon: Icons.local_grocery_store_outlined, color: Color(0xFF65A30D)),
    'Bills':         (icon: Icons.receipt_outlined,             color: Color(0xFF0D9488)),
    'Other':         (icon: Icons.add_circle_outline,           color: Color(0xFF9E9E9E)),
  };

  static const _orange = Color(0xFFFF9F29);
  static const _red = Color(0xFFEF4444);
  static const _muted = Color(0xFF9E9E9E);

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

    final res = await SubscriptionRepositoryImpl().getSubscriptions(userID: _uid);
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
      backgroundColor: error ? _red : const Color(0xFF4CAF50),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
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

  ({String text, Color fg, Color bg}) _badge(Map<String, dynamic> s) {
    if (s['active'] != true) {
      return (text: 'Paused', fg: _muted, bg: const Color.fromRGBO(240, 235, 225, 0.6));
    }
    final days = (s['days_until_due'] as num?)?.toInt() ?? 0;
    const soonBg = Color.fromRGBO(255, 159, 41, 0.12);
    if (days < 0) {
      final n = -days;
      return (
        text: '$n day${n == 1 ? '' : 's'} overdue',
        fg: _red,
        bg: const Color.fromRGBO(239, 68, 68, 0.1),
      );
    }
    if (days == 0) return (text: 'Due today', fg: _orange, bg: soonBg);
    if (days == 1) return (text: 'Due tomorrow', fg: _orange, bg: soonBg);
    if (days <= 7) return (text: 'Due in $days days', fg: _orange, bg: soonBg);
    return (
      text: 'Due ${s['formatted_due_date'] ?? ''}',
      fg: _muted,
      bg: const Color.fromRGBO(240, 235, 225, 0.6),
    );
  }

  // ── Add / edit ──────────────────────────────────────────────────────────────

  Future<void> _openEditor({Map<String, dynamic>? sub}) async {
    if (_isBusy) return;
    final isEdit = sub != null;

    final nameController = TextEditingController(text: sub?['name'] as String? ?? '');
    final amountController = TextEditingController(
        text: sub == null ? '' : ((sub['amount'] as num?) ?? 0).round().toString());
    final noteController = TextEditingController(text: sub?['note'] as String? ?? '');
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
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void close(String result) {
            // A second tap while the sheet animates out would pop this screen.
            if (closing) return;
            closing = true;
            Navigator.pop(ctx, result);
          }

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
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
                      isEdit ? 'Edit bill' : 'Add a bill',
                      style: GoogleFonts.bricolageGrotesque(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 60,
                      decoration: _fieldDecoration('Name (e.g. Netflix, phone bill)')
                          .copyWith(counterText: ''),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _fieldDecoration('Amount in ฿'),
                    ),
                    const SizedBox(height: 16),
                    _label('REPEATS'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _cycles
                          .map((c) => _chip(_cycleLabel(c), c == cycle,
                              () => setSheet(() => cycle = c)))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: due,
                          // Past dates are allowed for a bill that is already
                          // overdue; future ones for everything else.
                          firstDate: today.subtract(const Duration(days: 365)),
                          lastDate: DateTime(today.year + 5, 12, 31),
                        );
                        if (picked != null) setSheet(() => due = picked);
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
                            const Icon(Icons.calendar_today_outlined, size: 17, color: _muted),
                            const SizedBox(width: 12),
                            Text('Next due',
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600, fontSize: 13, color: _muted)),
                            const Spacer(),
                            Text(
                              DateFormat('d MMM yyyy').format(due),
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700, fontSize: 13, color: _orange),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _label('CATEGORY'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _categories
                          .map((c) => _chip(c, c == category,
                              () => setSheet(() => category = c)))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: noteController,
                      maxLength: 200,
                      decoration: _fieldDecoration('Note (optional)').copyWith(counterText: ''),
                    ),
                    if (isEdit) ...[
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: active,
                        activeThumbColor: _orange,
                        onChanged: (v) => setSheet(() => active = v),
                        title: Text('Active',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.textDark)),
                        subtitle: Text('Paused bills are not counted or reminded',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w500, fontSize: 11, color: _muted)),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _orange,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9999)),
                        ),
                        onPressed: () {
                          final amount = int.tryParse(amountController.text.trim()) ?? 0;
                          if (nameController.text.trim().isEmpty) {
                            _toast('Give the bill a name', error: true);
                            return;
                          }
                          if (amount <= 0) {
                            _toast('Amount must be greater than 0', error: true);
                            return;
                          }
                          close('save');
                        },
                        child: Text(
                          isEdit ? 'SAVE CHANGES' : 'ADD BILL',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            letterSpacing: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    if (isEdit) ...[
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton.icon(
                          onPressed: () => close('delete'),
                          icon: const Icon(Icons.delete_outline, size: 18, color: _red),
                          label: Text('Delete bill',
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700, fontSize: 13, color: _red)),
                        ),
                      ),
                    ],
                  ],
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete ${sub['name'] ?? 'bill'}?',
            style: GoogleFonts.bricolageGrotesque(
                fontWeight: FontWeight.w800, fontSize: 19, color: _red)),
        content: Text(
          'It stops being tracked. Payments you already logged stay in your history.',
          style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14, color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: _muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: _red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isBusy = true);
    final id = sub['id'] as String? ?? '';
    final res = await SubscriptionRepositoryImpl()
        .deleteSubscription(subscriptionID: id, userID: _uid);
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

    final next = _day(sub['next_due_after_payment'] as String?);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Mark ${sub['name'] ?? 'this bill'} as paid?',
            style: GoogleFonts.bricolageGrotesque(
                fontWeight: FontWeight.w800, fontSize: 19, color: AppColors.textDark)),
        content: Text(
          'Logs a ${sub['formatted_amount'] ?? ''} ${sub['category'] ?? ''} expense for today'
          '${next != null ? ' and moves the next due date to ${DateFormat('d MMM yyyy').format(next)}' : ''}.',
          style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 14, color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: _muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Mark paid',
                style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: _orange)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _paying.contains(id)) return;

    setState(() => _paying.add(id));
    try {
      final res = await SubscriptionRepositoryImpl().markPaid(
        subscriptionID: id,
        userID: _uid,
        expectedDueDate: sub['due_date'] as String? ?? '',
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

  // ── UI ──────────────────────────────────────────────────────────────────────

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

    Future<void> run(BuildContext sheetContext, Future<bool> Function() send, String ok) async {
      Navigator.pop(sheetContext);
      final granted = await service.requestPermission();
      if (!granted) {
        _toast('Notifications are off for SmartFin. Turn them on in Settings.', error: true);
        return;
      }
      _toast(await send() ? ok : 'Could not send a test reminder', error: false);
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
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
            Text('Bill reminders',
                style: GoogleFonts.bricolageGrotesque(
                    fontWeight: FontWeight.w800, fontSize: 20, color: AppColors.textDark)),
            const SizedBox(height: 6),
            Text(
              'SmartFin reminds you at 9:00 the day before a bill is due, and again on the day.',
              style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13, color: _muted),
            ),
            const SizedBox(height: 16),
            _reminderOption(
              icon: Icons.notifications_active_outlined,
              title: 'Send a test reminder now',
              onTap: () => run(ctx, () => service.showTestNow(sample), 'Test reminder sent'),
            ),
            _reminderOption(
              icon: Icons.timer_outlined,
              title: 'Remind me in 10 seconds',
              subtitle: 'Go to the home screen to see it arrive',
              onTap: () => run(ctx, () => service.scheduleTest(seconds: 10, bill: sample),
                  'Scheduled — it may take a few seconds longer'),
            ),
            if (!enabled)
              _reminderOption(
                icon: Icons.settings_outlined,
                title: 'Turn on notifications',
                subtitle: 'Notifications are currently off for SmartFin',
                onTap: () {
                  Navigator.pop(ctx);
                  service.openSettings();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _reminderOption({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 159, 41, 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: _orange),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textDark)),
                  if (subtitle != null)
                    Text(subtitle,
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w500, fontSize: 11, color: _muted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color.fromRGBO(158, 158, 158, 0.5)),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: _muted),
        filled: true,
        fillColor: const Color.fromRGBO(240, 235, 225, 0.35),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );

  Widget _label(String text, {Color color = _muted}) => Text(
        text,
        style: GoogleFonts.inter(
          fontWeight: FontWeight.w800,
          fontSize: 10,
          letterSpacing: 2,
          color: color,
        ),
      );

  Widget _chip(String text, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color.fromRGBO(255, 159, 41, 0.08) : Colors.white,
          border: Border.all(
            color: selected ? _orange : const Color(0xFFEAE2D6),
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 13,
            color: selected ? _orange : AppColors.textDark,
          ),
        ),
      ),
    );
  }

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
              color: _orange,
              edgeOffset: 110,
              onRefresh: _load,
              child: ListView(
                physics: const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: const EdgeInsets.fromLTRB(24, 120, 24, 48),
                children: _buildBody(),
              ),
            ),
            _buildHeader(),
            if (_isBusy)
              Positioned.fill(
                child: Container(
                  color: const Color.fromRGBO(255, 249, 240, 0.6),
                  child: const Center(child: CircularProgressIndicator(color: _orange)),
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
        Center(child: CircularProgressIndicator(color: _orange)),
      ];
    }
    if (_error != null) return [_buildMessage(Icons.cloud_off_outlined, _error!, retry: true)];
    if (_subs.isEmpty) return [_buildEmpty()];

    final overdue = _subs.where((s) => s['status'] == 'overdue').toList();
    final soon = _subs.where((s) => s['status'] == 'due_today' || s['status'] == 'due_soon').toList();
    final later = _subs.where((s) => s['status'] == 'upcoming').toList();
    final paused = _subs.where((s) => s['status'] == 'paused').toList();

    return [
      _buildSummaryCard(),
      if (overdue.isNotEmpty) ..._section('OVERDUE', overdue, color: _red),
      if (soon.isNotEmpty) ..._section('DUE SOON · NEXT 7 DAYS', soon),
      if (later.isNotEmpty) ..._section('LATER', later),
      if (paused.isNotEmpty) ..._section('PAUSED', paused),
    ];
  }

  List<Widget> _section(String title, List<Map<String, dynamic>> items, {Color color = _muted}) {
    return [
      const SizedBox(height: 28),
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: _label(title, color: color),
      ),
      ...items.map(_buildRow),
    ];
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

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.5)),
        boxShadow: const [
          BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.02), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('MONTHLY TOTAL'),
          const SizedBox(height: 8),
          Text(
            _baht(total),
            style: GoogleFonts.bricolageGrotesque(
              fontWeight: FontWeight.w800,
              fontSize: 34,
              letterSpacing: -1,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            parts.join(' · '),
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> s) {
    final id = s['id'] as String? ?? '';
    final active = s['active'] == true;
    final category = s['category'] as String? ?? 'Other';
    final style = _categoryStyle[category] ?? _categoryStyle['Other']!;
    final badge = _badge(s);
    final paying = _paying.contains(id);

    return Opacity(
      opacity: active ? 1 : 0.6,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openEditor(sub: s),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color.fromRGBO(234, 226, 214, 0.5)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: style.color.withValues(alpha: 0.2)),
                ),
                child: Icon(style.icon, color: style.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s['name'] as String? ?? '-',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textDark),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_cycleLabel(s['billing_cycle'] as String?)} · $category',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 11, color: _muted),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badge.bg,
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Text(
                        badge.text,
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700, fontSize: 10.5, color: badge.fg),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    s['formatted_amount'] as String? ?? _baht((s['amount'] as num?) ?? 0),
                    style: GoogleFonts.bricolageGrotesque(
                        fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.textDark),
                  ),
                  if (active) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: paying ? null : () => _markPaid(s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(255, 159, 41, 0.06),
                          border: Border.all(color: _orange, width: 1.5),
                          borderRadius: BorderRadius.circular(9999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (paying)
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2, color: _orange),
                              )
                            else
                              const Icon(Icons.check_rounded, size: 14, color: _orange),
                            const SizedBox(width: 4),
                            Text('Mark paid',
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w800, fontSize: 11, color: _orange)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 159, 41, 0.1),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.event_repeat_outlined, size: 34, color: _orange),
          ),
          const SizedBox(height: 20),
          Text(
            'No bills tracked yet',
            style: GoogleFonts.bricolageGrotesque(
                fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.textDark),
          ),
          const SizedBox(height: 8),
          Text(
            'Add Netflix, your phone plan or rent and SmartFin will remind you before they\'re due',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontWeight: FontWeight.w500, fontSize: 13, color: _muted),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
              ),
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
              label: Text('ADD A BILL',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 2,
                      color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(IconData icon, String message, {bool retry = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 100),
      child: Column(
        children: [
          Icon(icon, size: 32, color: _muted),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textDark),
          ),
          if (retry) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _load,
              child: Text('Try again',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: _orange)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _headerButton({required IconData icon, required VoidCallback onTap, bool filled = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: filled ? _orange : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: filled ? null : Border.all(color: const Color.fromRGBO(234, 226, 214, 0.6)),
        ),
        child: Icon(icon,
            size: 22, color: filled ? Colors.white : const Color.fromRGBO(51, 51, 51, 0.7)),
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
            padding: const EdgeInsets.only(left: 24, right: 24, top: 48, bottom: 20),
            child: Row(
              children: [
                _headerButton(icon: Icons.chevron_left, onTap: () => context.pop(_changed)),
                Expanded(
                  child: Text(
                    'Subscriptions & Bills',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.bricolageGrotesque(
                        fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.textDark),
                  ),
                ),
                _headerButton(icon: Icons.notifications_none_rounded, onTap: _showReminderSheet),
                const SizedBox(width: 8),
                _headerButton(icon: Icons.add_rounded, onTap: () => _openEditor(), filled: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
