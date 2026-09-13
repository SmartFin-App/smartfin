import 'package:dio/dio.dart';
import 'package:smart_fin/core/network/dio_client.dart';
import 'package:smart_fin/features/subscriptions/data/subscription_repository.dart';

class SubscriptionRepositoryImpl implements SubscriptionRepository {
  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Map<String, dynamic> _asMap(dynamic data) =>
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

  @override
  Future<ApiResponse<Map<String, dynamic>>> getSubscriptions({
    required String userID,
    bool activeOnly = false,
  }) async {
    try {
      final response = await DioClient.dio.get(
        '/api/subscriptions/$userID',
        queryParameters: {if (activeOnly) 'active': 'true'},
      );
      return ApiResponse.success(_asMap(response.data));
    } on DioException catch (e) {
      return ApiResponse.error(DioClient.handleError(e));
    }
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> createSubscription({
    required String userID,
    required String name,
    required int amount,
    required String billingCycle,
    required DateTime nextDueDate,
    String category = 'Bills',
    String? note,
  }) async {
    try {
      final response = await DioClient.dio.post(
        '/api/subscriptions',
        data: {
          'user_id': userID,
          'name': name,
          'amount': amount,
          'billing_cycle': billingCycle,
          'next_due_date': _day(nextDueDate),
          'category': category,
          'note': ?note,
        },
      );
      return ApiResponse.success(_asMap(response.data));
    } on DioException catch (e) {
      return ApiResponse.error(DioClient.handleError(e));
    }
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> updateSubscription({
    required String subscriptionID,
    required String userID,
    String? name,
    int? amount,
    String? billingCycle,
    DateTime? nextDueDate,
    String? category,
    String? note,
    bool? active,
  }) async {
    try {
      final response = await DioClient.dio.put(
        '/api/subscriptions/$subscriptionID',
        data: {
          'user_id': userID,
          'name': ?name,
          'amount': ?amount,
          'billing_cycle': ?billingCycle,
          if (nextDueDate != null) 'next_due_date': _day(nextDueDate),
          'category': ?category,
          'note': ?note,
          'active': ?active,
        },
      );
      return ApiResponse.success(_asMap(response.data));
    } on DioException catch (e) {
      return ApiResponse.error(DioClient.handleError(e));
    }
  }

  @override
  Future<ApiResponse<bool>> deleteSubscription({
    required String subscriptionID,
    required String userID,
  }) async {
    try {
      await DioClient.dio.delete(
        '/api/subscriptions/$subscriptionID',
        queryParameters: {'user_id': userID},
      );
      return ApiResponse.success(true);
    } on DioException catch (e) {
      return ApiResponse.error(DioClient.handleError(e));
    }
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> markPaid({
    required String subscriptionID,
    required String userID,
    required String expectedDueDate,
  }) async {
    try {
      final response = await DioClient.dio.post(
        '/api/subscriptions/$subscriptionID/pay',
        data: {'user_id': userID, 'expected_due_date': expectedDueDate},
      );
      return ApiResponse.success(_asMap(response.data));
    } on DioException catch (e) {
      return ApiResponse.error(DioClient.handleError(e));
    }
  }
}
