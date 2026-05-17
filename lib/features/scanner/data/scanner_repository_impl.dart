import 'dart:io';
import 'package:dio/dio.dart';
import 'package:smart_fin/core/network/dio_client.dart';
import 'package:smart_fin/features/scanner/data/scanner_repository.dart';

class ScannerRepositoryImpl implements ScannerRepository {
  @override
  Future<ApiResponse<Map<String, dynamic>>> processReceipt(
      File imageFile, String userID) async {
    try {
      final formData = FormData.fromMap({
        'user_id': userID,
        'image': await MultipartFile.fromFile(
          imageFile.path,
          filename: imageFile.path.split('/').last,
        ),
      });

      final response = await DioClient.dio.post(
        '/api/scanner/process',
        data: formData,
      );

      return ApiResponse.success(response.data);
    } on DioException catch (e) {
      print('ProcessReceipt Error Status: ${e.response?.statusCode}');
      print('ProcessReceipt Error Data: ${e.response?.data}');
      print('ProcessReceipt Request Path: ${e.requestOptions.path}');
      return ApiResponse.error(DioClient.handleError(e));
    }
  }
}
