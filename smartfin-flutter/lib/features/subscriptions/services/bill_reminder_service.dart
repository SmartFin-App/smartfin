import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// On-device reminders for tracked bills: 09:00 the day before a bill is due,
/// and 09:00 on the day. The server has no background jobs, so reminders are
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

  /// A stable notification id for a bill's reminder [slot] (0 = the day before,
  /// 1 = on the day). Built from the Mongo ObjectID, not `String.hashCode`, which
  /// is not guaranteed to be the same between runs — a changed id would leave
  /// the old reminder impossible to cancel. The last 7 hex digits are mostly the
  /// ObjectID's counter, so two of one user's bills do not collide in practice.
  static int idFor(String objectIdHex, int slot) {
    final hex = objectIdHex.length >= 7
        ? objectIdHex.substring(objectIdHex.length - 7)
        : objectIdHex.padLeft(7, '0');
    return (int.tryParse(hex, radix: 16) ?? 0) * 2 + slot;
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
      for (final s in subs) {
        if (s['active'] != true) continue;
        final id = s['id'] as String? ?? '';
        // due_date is the Thai calendar day as a plain string, so no conversion.
        final due = DateTime.tryParse(s['due_date'] as String? ?? '');
        if (id.isEmpty || due == null) continue;

        final name = s['name'] as String? ?? 'A bill';
        final amount = s['formatted_amount'] as String? ?? '';
        final onTheDay = tz.TZDateTime(tz.local, due.year, due.month, due.day, _reminderHour);

        await _schedule(
          id: idFor(id, 0),
          when: onTheDay.subtract(const Duration(days: 1)),
          title: '$name is due tomorrow',
          body: '$amount — open SmartFin to see your upcoming bills 🐾',
          payload: '$_payloadPrefix$id',
          now: now,
        );
        await _schedule(
          id: idFor(id, 1),
          when: onTheDay,
          title: '$name is due today',
          body: '$amount — tap "Mark paid" once it\'s done 🐾',
          payload: '$_payloadPrefix$id',
          now: now,
        );
      }
    } catch (e) {
      debugPrint('Bill reminders: sync failed: $e');
    }
  }

  Future<void> _schedule({
    required int id,
    required tz.TZDateTime when,
    required String title,
    required String body,
    required String payload,
    required tz.TZDateTime now,
  }) async {
    // zonedSchedule throws for a time in the past, e.g. the day-before reminder
    // of a bill due today, or today's 09:00 reminder after 09:00.
    if (!when.isAfter(now.add(const Duration(seconds: 5)))) return;
    try {
      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: when,
        notificationDetails: _details,
        // Inexact: no exact-alarm permission needed, and a reminder a few minutes
        // late is fine.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Bill reminders: could not schedule $id: $e');
    }
  }

  Future<void> cancelFor(String subscriptionId) async {
    if (!enabled || !_ready || subscriptionId.isEmpty) return;
    try {
      await _plugin.cancel(id: idFor(subscriptionId, 0));
      await _plugin.cancel(id: idFor(subscriptionId, 1));
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
            ? '${bill['formatted_amount'] ?? ''} — this is how SmartFin reminds you 🐾'
            : 'SmartFin will remind you before a bill is due 🐾',
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
            ? '${bill['formatted_amount'] ?? ''} — a scheduled test from SmartFin 🐾'
            : 'Scheduled reminders are working 🐾',
        payload: _testPayload,
      );
      return true;
    } catch (e) {
      debugPrint('Bill reminders: scheduled test failed: $e');
      return false;
    }
  }
}
