import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fin/features/scanner/services/gallery_watcher_service.dart';

/// The one-time earlier-slips question reaches back to the start of the month
/// Auto-Detect first ran in, by the Thai calendar, and no further.
void main() {
  group('thaiMonthStart', () {
    test('an install on 9 October looks back to 1 October, Thai time', () {
      final install = DateTime.utc(2026, 10, 9, 3, 30); // 10:30 in Thailand
      expect(
        GalleryWatcherService.thaiMonthStart(install),
        DateTime.utc(2026, 9, 30, 17), // 1 Oct 00:00 +07:00
      );
    });

    test(
      'late evening UTC on the last day already counts as the next Thai month',
      () {
        final install = DateTime.utc(
          2026,
          9,
          30,
          18,
        ); // 1 Oct 01:00 in Thailand
        expect(
          GalleryWatcherService.thaiMonthStart(install),
          DateTime.utc(2026, 9, 30, 17),
        );
      },
    );

    test('just before Thai midnight still belongs to the old month', () {
      final install = DateTime.utc(2026, 9, 30, 16, 59); // 30 Sep 23:59 Thai
      expect(
        GalleryWatcherService.thaiMonthStart(install),
        DateTime.utc(2026, 8, 31, 17),
      );
    });
  });
}
