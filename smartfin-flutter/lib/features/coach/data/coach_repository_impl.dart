import 'package:dio/dio.dart';
import 'package:smart_fin/core/network/dio_client.dart';

class CoachRepositoryImpl {
  /// Loads the stored conversation. The screen is disposed whenever the user
  /// switches tabs, so the transcript has to come back from the server rather
  /// than from widget state.
  Future<ApiResponse<List<Map<String, dynamic>>>> getHistory({
    required String userID,
    int limit = 50,
  }) async {
    try {
      final response = await DioClient.dio.get(
        '/api/coach/history/$userID',
        queryParameters: {'limit': limit},
      );
      final raw = (response.data as Map<String, dynamic>)['messages'] as List?;
      final list = (raw ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return ApiResponse.success(list);
    } on DioException catch (e) {
      return ApiResponse.error(DioClient.handleError(e));
    }
  }

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
