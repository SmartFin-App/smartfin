import 'package:dio/dio.dart';
import 'package:smart_fin/core/network/dio_client.dart';

class CoachRepositoryImpl {
  Future<ApiResponse<String>> askCoach({
    required String userID,
    required String message,
    required List<Map<String, String>> history,
  }) async {
    try {
      final response = await DioClient.dio.post('/api/coach/ask', data: {
        'user_id': userID,
        'message': message,
        'history': history,
      });
      return ApiResponse.success(response.data['response'] as String);
    } on DioException catch (e) {
      print('CoachError: ${e.response?.data}');
      return ApiResponse.error(DioClient.handleError(e));
    }
  }
}
