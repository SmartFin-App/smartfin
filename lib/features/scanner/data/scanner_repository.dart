import 'dart:io';
import 'package:smart_fin/core/network/dio_client.dart';

abstract class ScannerRepository {
  Future<ApiResponse<Map<String, dynamic>>> processReceipt(
      File imageFile, String userID);
}
