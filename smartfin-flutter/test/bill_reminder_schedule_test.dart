import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:smart_fin/features/subscriptions/services/bill_reminder_service.dart';

void main() {
  late tz.Location bangkok;
  setUpAll(() {
    tzdata.initializeTimeZones();
    bangkok = tz.getLocation('Asia/Bangkok');
  });

  tz.TZDateTime at(int month, int day, [int hour = 12]) =>
      tz.TZDateTime(bangkok, 2026, month, day, hour);

  Map<String, dynamic> bill(String dueDate, {bool active = true}) => {
    'id': '6720f1a2b3c4d5e6f7a8b9c0',
    'name': 'Netflix',
    'formatted_amount': '฿419',
    'due_date': dueDate,
    'active': active,
  };

  String describe(PlannedReminder r) =>
      '${r.when.month}/${r.when.day} ${r.when.hour}:00 ${r.title}${r.daily ? ' (daily)' : ''}';

  test('a bill due ahead gets the usual two, then three overdue days', () {
    final plan = BillReminderService.remindersFor(
      bill('2026-11-10'),
      at(11, 3),
    );
    expect(plan.map(describe), [
      '11/9 9:00 Netflix is due tomorrow',
      '11/10 9:00 Netflix is due today',
      '11/11 9:00 Netflix is overdue',
      '11/12 9:00 Netflix is overdue',
      '11/13 9:00 Netflix is overdue',
    ]);
    expect(
      plan.last.body,
      '฿419 was due Nov 10 — tap "Mark paid" once it\'s done',
    );
    expect(plan.map((r) => r.id).toSet(), hasLength(5));
  });

  test('times already past are left out', () {
    // Due today, after 09:00: only the overdue days remain.
    final plan = BillReminderService.remindersFor(
      bill('2026-11-03'),
      at(11, 3, 10),
    );
    expect(plan.map(describe), [
      '11/4 9:00 Netflix is overdue',
      '11/5 9:00 Netflix is overdue',
      '11/6 9:00 Netflix is overdue',
    ]);
  });

  test('overdue days roll over the end of the month', () {
    final plan = BillReminderService.remindersFor(
      bill('2026-10-31'),
      at(10, 20),
    );
    expect(plan.skip(2).map(describe), [
      '11/1 9:00 Netflix is overdue',
      '11/2 9:00 Netflix is overdue',
      '11/3 9:00 Netflix is overdue',
    ]);
  });

  test('an overdue bill gets one daily reminder from the next 09:00', () {
    final before9 = BillReminderService.remindersFor(
      bill('2026-10-28'),
      at(11, 3, 8),
    );
    expect(before9.map(describe), ['11/3 9:00 Netflix is overdue (daily)']);

    final after9 = BillReminderService.remindersFor(
      bill('2026-10-28'),
      at(11, 3, 10),
    );
    expect(after9.map(describe), ['11/4 9:00 Netflix is overdue (daily)']);
    expect(after9.single.body, contains('was due Oct 28'));
  });

  test('the daily reminder reuses the first overdue slot', () {
    final ahead = BillReminderService.remindersFor(
      bill('2026-11-10'),
      at(11, 3),
    );
    final overdue = BillReminderService.remindersFor(
      bill('2026-11-10'),
      at(11, 20),
    );
    expect(overdue.single.id, ahead[2].id);
  });

  test('paused or malformed bills get nothing', () {
    expect(
      BillReminderService.remindersFor(
        bill('2026-11-10', active: false),
        at(11, 3),
      ),
      isEmpty,
    );
    expect(BillReminderService.remindersFor(bill('soon'), at(11, 3)), isEmpty);
  });

  test('ids of neighbouring bills never collide', () {
    final a = List.generate(
      5,
      (s) => BillReminderService.idFor('000000000000000000000001', s),
    );
    final b = List.generate(
      5,
      (s) => BillReminderService.idFor('000000000000000000000002', s),
    );
    expect({...a, ...b}, hasLength(10));
    expect(
      BillReminderService.idFor('ffffffffffffffffffffffff', 4),
      lessThan(2147483000),
    );
  });
}
