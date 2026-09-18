import 'package:dio/dio.dart';
import 'package:smart_fin/core/network/dio_client.dart';
import 'package:smart_fin/features/auth/data/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  @override
  Future<ApiResponse<Map<String, dynamic>>> createUser({
    required String firebaseUID,
    required String name,
    required String email,
    required String photoURL,
    required String currentStatus,
    required String financialHealth,
    required double budgetLimit,
  }) async {
    try {
      final response = await DioClient.dio.post(
        '/api/users',
        data: {
          'firebase_uid': firebaseUID,
          'name': name,
          'email': email,
          'photo_url': photoURL,
          'current_status': currentStatus,
          'financial_health': financialHealth,
          'budget_limit': budgetLimit.toInt(),
        },
      );
      // Ensure we extract the Map<String, dynamic>
      if (response.data is Map) {
         return ApiResponse.success(Map<String, dynamic>.from(response.data));
      }
      return ApiResponse.success(response.data);
    } on DioException catch (e) {
      print('CreateUser Error Status: ${e.response?.statusCode}');
      print('CreateUser Error Data: ${e.response?.data}');
      print('CreateUser Request Data: ${e.requestOptions.data}');
      return ApiResponse.error(DioClient.handleError(e));
    }
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> getUserByFirebaseUID(String firebaseUID) async {
    try {
      final response = await DioClient.dio.get('/api/users/$firebaseUID');
      if (response.data is Map) {
         return ApiResponse.success(Map<String, dynamic>.from(response.data));
      }
      return ApiResponse.success(response.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return ApiResponse.error('User not found');
      }
      return ApiResponse.error(DioClient.handleError(e));
    }
  }

  @override
  Future<ApiResponse<bool>> updateUser(String firebaseUID, Map<String, dynamic> data) async {
    try {
      await DioClient.dio.put(
        '/api/users/$firebaseUID',
        data: data,
      );
      return ApiResponse.success(true);
    } on DioException catch (e) {
      return ApiResponse.error(DioClient.handleError(e));
    }
  }
}
