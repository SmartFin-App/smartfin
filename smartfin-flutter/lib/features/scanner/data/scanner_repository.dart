import 'dart:io';
import 'package:smart_fin/core/network/dio_client.dart';

abstract class ScannerRepository {
  /// The error [processReceipt] returns when the server read the photo and
  /// found no slip or receipt in it, so the caller can say so plainly.
  static const String notASlipError = 'not_a_slip';

  Future<ApiResponse<Map<String, dynamic>>> processReceipt(
      File imageFile, String userID);
}
