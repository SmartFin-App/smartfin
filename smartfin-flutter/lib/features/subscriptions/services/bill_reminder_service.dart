import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// On-device reminders for tracked bills: 09:00 the day before a bill is due,
/// 09:00 on the day, and once it is overdue, 09:00 every day until it is marked
/// paid (see [remindersFor]). The server has no background jobs, so reminders are
/// scheduled here whenever the bill list is loaded — every load cancels the
/// previous bill reminders and schedules afresh, so an edit, a payment, a pause
/// or a deletion never leaves a stale reminder behind.
///
/// Every method is safe to call at any time: failures are logged, never thrown,
/// because a reminder is a convenience that must not break the screen that
/// triggered it.
class BillReminderService {
  /// Kill switch. Set to false and hot restart to silence every reminder call
  /// without touching the native setup.
  static const bool enabled = true;

  static final BillReminderService _instance = BillReminderService._();
  factory BillReminderService() => _instance;
  BillReminderService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _payloadPrefix = 'bill:';
  static const _testPayload = 'test';
  static const _reminderHour = 9;

  /// One-off overdue reminders scheduled ahead of time, on days 1 to 3 after
  /// the due date, for someone who does not open the app in between.
  static const _overdueDaysAhead = 3;


  // Above any id produced by [idFor], so a test never replaces a real reminder.
  static const _testNowId = 2147483000;
  static const _testLaterId = 2147483001;

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'bill_reminders',
      'Bill reminders',
      channelDescription: 'Reminders before a tracked bill is due',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> init() async {
    if (!enabled || _ready || kIsWeb) return;
    tzdata.initializeTimeZones();
    // Bills are due on Thai calendar days — the backend's fixed +07:00 — whatever
    // zone the device clock is set to (the emulator is often on UTC).
    tz.setLocalLocation(tz.getLocation('Asia/Bangkok'));

    // Permission is asked for on the tracker screen, not at app start.
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: darwin,
        macOS: darwin,
      ),
    );
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Asks for permission to post notifications. On Android 13+ this shows the
  /// system prompt once; when already granted it returns true without a prompt.
  Future<bool> requestPermission() async {
    if (!enabled || !_ready) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _android?.requestNotificationsPermission() ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
    } catch (e) {
      debugPrint('Bill reminders: permission request failed: $e');
    }
    return false;
  }

  Future<bool> notificationsEnabled() async {
    if (!enabled || !_ready) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _android?.areNotificationsEnabled() ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // Ask iOS rather than assuming: a denied prompt is never shown again,
        // and reminders then fail without any error.
        final status = await _plugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.checkPermissions();
        return status?.isEnabled ?? false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> openSettings() async {
    try {
      await _android?.openAppNotificationSettings();
    } catch (e) {
      debugPrint('Bill reminders: could not open settings: $e');
    }
  }

  /// A stable notification id for a bill's reminder [slot]: 0 = the day before,
  /// 1 = on the day, 2 = overdue (day 1, or the daily repeat), 3 and 4 = days 2
  /// and 3 overdue. Built from the Mongo ObjectID, not `String.hashCode`, which
  /// is not guaranteed to be the same between runs — a changed id would leave
  /// the old reminder impossible to cancel. The last 7 hex digits are mostly the
  /// ObjectID's counter, so two of one user's bills do not collide in practice.
  static int idFor(String objectIdHex, int slot) {
    final hex = objectIdHex.length >= 7
        ? objectIdHex.substring(objectIdHex.length - 7)
        : objectIdHex.padLeft(7, '0');
    // At most 0xFFFFFFF × 5 + 4, about 1.34 billion: inside a 32-bit id and
    // below the test ids.
    return (int.tryParse(hex, radix: 16) ?? 0) * _slots + slot;
  }

  static const _slots = 5;

  /// The reminders [bill] (as the API returns it) should have at [now], which
  /// must be in Asia/Bangkok.
  ///
  /// A daily repeat can't be given a later start date: both platforms fire it
  /// at the next matching 09:00, whatever date it was scheduled for. So the
  /// repeat is set only once the bill is already overdue. Before that, the
  /// overdue days are covered by one-off reminders, and the first time the app
  /// is opened after the due date, the repeat replaces them. Paying the bill
  /// reloads the list, and the resync clears every reminder for it.
  @visibleForTesting
  static List<PlannedReminder> remindersFor(
    Map<String, dynamic> bill,
    tz.TZDateTime now,
  ) {
    if (bill['active'] != true) return const [];
    final id = bill['id'] as String? ?? '';
    // due_date is the Thai calendar day as a plain string, so no conversion.
    final due = DateTime.tryParse(bill['due_date'] as String? ?? '');
    if (id.isEmpty || due == null) return const [];

    final name = bill['name'] as String? ?? 'A bill';
    final amount = bill['formatted_amount'] as String? ?? '';
    final overdueTitle = '$name is overdue';
    final overdueBody =
        '$amount was due ${DateFormat('MMM d').format(due)} — tap "Mark paid" once it\'s done';

    // Day overflow (Oct 31 + 1) rolls into the next month, as with DateTime.
    tz.TZDateTime nineOn(int daysAfterDue) => tz.TZDateTime(
      now.location,
      due.year,
      due.month,
      due.day + daysAfterDue,
      _reminderHour,
    );

    final today = DateTime(now.year, now.month, now.day);
    if (today.isAfter(due)) {
      var next = tz.TZDateTime(
        now.location,
        now.year,
        now.month,
        now.day,
        _reminderHour,
      );
      if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
      return [
        PlannedReminder(
          id: idFor(id, 2),
          when: next,
          title: overdueTitle,
          body: overdueBody,
          daily: true,
        ),
      ];
    }

    return [
          PlannedReminder(
            id: idFor(id, 0),
            when: nineOn(-1),
            title: '$name is due tomorrow',
            body: '$amount — open SmartFin to see your upcoming bills',
          ),
          PlannedReminder(
            id: idFor(id, 1),
            when: nineOn(0),
            title: '$name is due today',
            body: '$amount — tap "Mark paid" once it\'s done',
          ),
          for (var day = 1; day <= _overdueDaysAhead; day++)
            PlannedReminder(
              id: idFor(id, 1 + day),
              when: nineOn(day),
              title: overdueTitle,
              body: overdueBody,
            ),
        ]
        // zonedSchedule throws for a one-off time in the past, e.g. the
        // day-before reminder of a bill due today.
        .where((r) => r.when.isAfter(now.add(const Duration(seconds: 5))))
        .toList();
  }

  /// Replaces every scheduled bill reminder with reminders for [subs], a list of
  /// bills as the API returns them. Paused bills and times already past are skipped.
  Future<void> syncAll(List<Map<String, dynamic>> subs) async {
    if (!enabled || !_ready) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        if ((p.payload ?? '').startsWith(_payloadPrefix)) {
          await _plugin.cancel(id: p.id);
        }
      }

      final now = tz.TZDateTime.now(tz.local);
      for (final bill in subs) {
        for (final reminder in remindersFor(bill, now)) {
          await _schedule(reminder, payload: '$_payloadPrefix${bill['id']}');
        }
      }
    } catch (e) {
      debugPrint('Bill reminders: sync failed: $e');
    }
  }

  Future<void> _schedule(
    PlannedReminder reminder, {
    required String payload,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id: reminder.id,
        scheduledDate: reminder.when,
        notificationDetails: _details,
        // Inexact: no exact-alarm permission needed, and a reminder a few minutes
        // late is fine.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        // Repeats every day at the same time until cancelled.
        matchDateTimeComponents: reminder.daily
            ? DateTimeComponents.time
            : null,
        title: reminder.title,
        body: reminder.body,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Bill reminders: could not schedule ${reminder.id}: $e');
    }
  }

  Future<void> cancelFor(String subscriptionId) async {
    if (!enabled || !_ready || subscriptionId.isEmpty) return;
    try {
      for (var slot = 0; slot < _slots; slot++) {
        await _plugin.cancel(id: idFor(subscriptionId, slot));
      }
    } catch (e) {
      debugPrint('Bill reminders: cancel failed: $e');
    }
  }

  /// Clears every reminder — on logout and account deletion, so the next person
  /// signed in on this device is not reminded about someone else's bills.
  Future<void> cancelAll() async {
    if (!enabled || !_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('Bill reminders: cancelAll failed: $e');
    }
  }

  /// Shows a sample reminder immediately. Returns false if it could not be shown.
  Future<bool> showTestNow([Map<String, dynamic>? bill]) async {
    if (!enabled || !_ready) return false;
    try {
      await _plugin.show(
        id: _testNowId,
        title: bill != null ? '${bill['name']} is due soon' : 'Bill reminders are on',
        body: bill != null
            ? '${bill['formatted_amount'] ?? ''} — this is how SmartFin reminds you'
            : 'SmartFin will remind you before a bill is due',
        notificationDetails: _details,
        payload: _testPayload,
      );
      return true;
    } catch (e) {
      debugPrint('Bill reminders: test failed: $e');
      return false;
    }
  }

  /// Schedules a sample reminder [seconds] from now, through the same scheduling
  /// path real reminders use. Inexact, so it can arrive a little late.
  Future<bool> scheduleTest({int seconds = 10, Map<String, dynamic>? bill}) async {
    if (!enabled || !_ready) return false;
    try {
      await _plugin.zonedSchedule(
        id: _testLaterId,
        scheduledDate: tz.TZDateTime.now(tz.local).add(Duration(seconds: seconds)),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: bill != null ? '${bill['name']} is due tomorrow' : 'Scheduled test reminder',
        body: bill != null
            ? '${bill['formatted_amount'] ?? ''} — a scheduled test from SmartFin'
            : 'Scheduled reminders are working',
        payload: _testPayload,
      );
      return true;
    } catch (e) {
      debugPrint('Bill reminders: scheduled test failed: $e');
      return false;
    }
  }
}

/// One reminder [BillReminderService.remindersFor] wants scheduled.
@visibleForTesting
class PlannedReminder {
  final int id;
  final tz.TZDateTime when;
  final String title;
  final String body;

  /// Repeats at the same time every day until cancelled.
  final bool daily;

  const PlannedReminder({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
    this.daily = false,
  });
}
