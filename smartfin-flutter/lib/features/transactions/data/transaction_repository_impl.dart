import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:smart_fin/core/network/dio_client.dart';
import 'package:smart_fin/features/transactions/data/transaction_repository.dart';

class TransactionRepositoryImpl implements TransactionRepository {
  @override
  Future<ApiResponse<Map<String, dynamic>>> createTransaction({
    required String userID,
    required String merchant,
    required int amount,
    required String type,
    required String category,
    required String source,
    required DateTime date,
  }) async {
    try {
      final response = await DioClient.dio.post(
        '/api/transactions',
        data: {
          'user_id': userID,
          'merchant': merchant,
          'amount': amount,
          'type': type,
          'category': category,
          'source': source,
          'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        },
      );
      if (response.data is Map) {
        return ApiResponse.success(Map<String, dynamic>.from(response.data));
      }
      return ApiResponse.success(response.data);
    } on DioException catch (e) {
      debugPrint('CreateTransaction Error Status: ${e.response?.statusCode}');
      debugPrint('CreateTransaction Error Data: ${e.response?.data}');
      debugPrint('CreateTransaction Request Data: ${e.requestOptions.data}');
      return ApiResponse.error(DioClient.handleError(e));
    }
  }

  @override
  Future<ApiResponse<List<Map<String, dynamic>>>> getTransactions({
    required String userID,
    String? type,
    String? category,
    String? month,
    String? search,
    int limit = 50,
    int skip = 0,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'limit': limit,
        'skip': skip,
        'type': ?type,
        'category': ?category,
        'month': ?month,
        if (search != null && search.isNotEmpty) 'search': search,
      };
      final response = await DioClient.dio.get(
        '/api/transactions/$userID',
        queryParameters: queryParams,
      );
      final list = List<Map<String, dynamic>>.from(
        (response.data as List).map((e) => Map<String, dynamic>.from(e)),
      );
      return ApiResponse.success(list);
    } on DioException catch (e) {
      return ApiResponse.error(DioClient.handleError(e));
    }
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> getTransactionSummary({
    required String userID,
    String? month,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'month': ?month,
      };
      final response = await DioClient.dio.get(
        '/api/transactions/summary/$userID',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );
      if (response.data is Map) {
        return ApiResponse.success(Map<String, dynamic>.from(response.data));
      }
      return ApiResponse.success(response.data);
    } on DioException catch (e) {
      return ApiResponse.error(DioClient.handleError(e));
    }
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> getTransactionById({
    required String transactionID,
    required String userID,
  }) async {
    try {
      final response = await DioClient.dio.get(
        '/api/transactions/detail/$transactionID',
        queryParameters: {'user_id': userID},
      );
      return ApiResponse.success(Map<String, dynamic>.from(response.data));
    } on DioException catch (e) {
      return ApiResponse.error(DioClient.handleError(e));
    }
  }

  @override
  Future<ApiResponse<bool>> updateTransaction({
    required String transactionID,
    required String userID,
    String? merchant,
    int? amount,
    String? type,
    String? category,
    DateTime? date,
  }) async {
    try {
      await DioClient.dio.put(
        '/api/transactions/$transactionID',
        // user_id in the body identifies the owner; the API refuses the write
        // without it rather than trusting the id alone.
        data: {
          'user_id': userID,
          'merchant': ?merchant,
          'amount': ?amount,
          'type': ?type,
          'category': ?category,
          if (date != null)
            'date':
                '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        },
      );
      return ApiResponse.success(true);
    } on DioException catch (e) {
      return ApiResponse.error(DioClient.handleError(e));
    }
  }

  @override
  Future<ApiResponse<bool>> deleteTransaction({
    required String transactionID,
    required String userID,
  }) async {
    try {
      await DioClient.dio.delete(
        '/api/transactions/$transactionID',
        queryParameters: {'user_id': userID},
      );
      return ApiResponse.success(true);
    } on DioException catch (e) {
      return ApiResponse.error(DioClient.handleError(e));
    }
  }
}
