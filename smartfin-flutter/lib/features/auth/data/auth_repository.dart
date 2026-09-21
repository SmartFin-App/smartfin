import 'package:smart_fin/core/network/dio_client.dart';

abstract class AuthRepository {
  Future<ApiResponse<Map<String, dynamic>>> createUser({
    required String firebaseUID,
    required String name,
    required String email,
    required String photoURL,
    required String currentStatus,
    required String financialHealth,
    required double budgetLimit,
  });

  Future<ApiResponse<Map<String, dynamic>>> getUserByFirebaseUID(
    String firebaseUID,
  );

  Future<ApiResponse<bool>> updateUser(
    String firebaseUID,
    Map<String, dynamic> data,
  );
}
