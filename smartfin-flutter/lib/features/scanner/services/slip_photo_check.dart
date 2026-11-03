import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// What the on-device check made of a photo before it is sent to Gemini.
enum SlipPhotoVerdict {
  /// Shows a money amount, so it is worth reading.
  slip,

  /// No amount anywhere: a selfie, a meal, a blank page. Not sent.
  notSlip,

  /// The check could not run (no ML Kit on this platform, an unreadable file).
  /// The photo is sent anyway, and the server's own check decides.
  unchecked,
}

/// Reads a photo's text on the device with ML Kit and decides whether it could
/// be a payment slip or receipt, so photos that clearly are not never cost a
/// Gemini Vision call.
///
/// ML Kit has no Thai model, so this runs the Latin one. It still reads the
/// digits, `฿`, "THB" and the English labels Thai banking slips print, which is
/// all the check needs. It only looks for an amount; telling a slip from a
/// price tag is left to the server.
class SlipPhotoCheck {
  static Future<SlipPhotoVerdict> check(File image) async {
    TextRecognizer? recognizer;
    try {
      recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognized = await recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );
      return looksLikeSlip(recognized.text)
          ? SlipPhotoVerdict.slip
          : SlipPhotoVerdict.notSlip;
    } catch (e) {
      // Includes MissingPluginException on macOS, or after hot reload without a
      // full `flutter run`. Blocking every scan then would be worse than
      // spending one Gemini call.
      debugPrint('Slip photo check could not run, sending the photo: $e');
      return SlipPhotoVerdict.unchecked;
    } finally {
      await recognizer?.close();
    }
  }

  /// A money figure with satang, as every Thai banking slip and most receipts
  /// print it: `1,250.00`, `45.00`. The dot guards keep dotted dates
  /// (`12.05.2026`) and version numbers (`1.2.10`) from counting.
  static final _amount = RegExp(r'(?<![\d.])\d[\d,]*\.\d{2}(?![\d.])');

  static final _currency = RegExp(
    r'฿|\b(?:THB|baht)\b',
    caseSensitive: false,
  );

  /// English words printed on Thai e-slips and receipts.
  static final _slipWords = RegExp(
    r'\b(?:prompt\s?pay|k\s?plus|scb|krungthai|krungsri|kasikorn|bangkok\s?bank'
    r'|ttb|transfer|transaction|amount|total|subtotal|receipt|tax\s?invoice'
    r'|vat|ref|fee|payment)\b',
    caseSensitive: false,
  );

  static final _anyDigit = RegExp(r'\d');
  static final _twoDigits = RegExp(r'\d{2,}');

  /// True when [text] (what ML Kit read off the photo) shows an amount.
  @visibleForTesting
  static bool looksLikeSlip(String text) {
    if (_amount.hasMatch(text)) return true;
    if (_currency.hasMatch(text) && _anyDigit.hasMatch(text)) return true;
    return _slipWords.hasMatch(text) && _twoDigits.hasMatch(text);
  }
}
