import 'package:flutter_test/flutter_test.dart';
import 'package:smart_fin/features/scanner/services/gallery_watcher_service.dart';

/// Folder-name matching for Auto-Detect. Real phones name these folders after
/// whichever app saved the slip, and the spellings vary by device and locale.
void main() {
  group('normalizeAlbumName', () {
    test('drops spacing and punctuation so one spelling matches them all', () {
      expect(GalleryWatcherService.normalizeAlbumName('K PLUS'), 'kplus');
      expect(GalleryWatcherService.normalizeAlbumName('KPLUS'), 'kplus');
      expect(GalleryWatcherService.normalizeAlbumName('k-plus'), 'kplus');
      expect(GalleryWatcherService.normalizeAlbumName('K_Plus'), 'kplus');
    });

    test('keeps Thai characters', () {
      expect(GalleryWatcherService.normalizeAlbumName('สลิป โอนเงิน'), 'สลิปโอนเงิน');
    });
  });

  group('looksLikeSlipAlbum', () {
    test('matches bank folders however they are spelled', () {
      for (final name in [
        'KPLUS',
        'K PLUS',
        'SCB EASY',
        'SCBEASY',
        'Krungthai NEXT',
        'Bualuang mBanking',
        'PromptPay',
        'TrueMoney',
        'KMA',
      ]) {
        expect(GalleryWatcherService.looksLikeSlipAlbum(name), isTrue,
            reason: '"$name" is a banking folder and should be watched');
      }
    });

    test('matches our own album and slip keywords, including Thai', () {
      expect(GalleryWatcherService.looksLikeSlipAlbum('SmartFin Receipts'), isTrue);
      expect(GalleryWatcherService.looksLikeSlipAlbum('smartfin_receipts'), isTrue);
      expect(GalleryWatcherService.looksLikeSlipAlbum('My Receipts'), isTrue);
      expect(GalleryWatcherService.looksLikeSlipAlbum('สลิป'), isTrue);
    });

    test('leaves ordinary albums alone', () {
      // Screenshots is excluded on purpose: watching it automatically offered
      // every screenshot to the scanner. The picker can still select it.
      for (final name in ['Camera', 'Screenshots', 'Download', 'WhatsApp Images', '']) {
        expect(GalleryWatcherService.looksLikeSlipAlbum(name), isFalse,
            reason: '"$name" is not slip-specific');
      }
    });
  });
}
