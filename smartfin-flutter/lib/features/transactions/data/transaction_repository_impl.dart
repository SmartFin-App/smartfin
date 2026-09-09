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
      print('CreateTransaction Error Status: ${e.response?.statusCode}');
      print('CreateTransaction Error Data: ${e.response?.data}');
      print('CreateTransaction Request Data: ${e.requestOptions.data}');
      return ApiResponse.error(DioClient.handleError(e));
    }
  }

  @override
  Future<ApiResponse<List<Map<String, dynamic>>>> getTransactions({
    required String userID,
    String? type,
    String? category,
    int limit = 50,
    int skip = 0,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'limit': limit,
        'skip': skip,
        if (type != null) 'type': type,
        if (category != null) 'category': category,
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
        if (month != null) 'month': month,
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
  Future<ApiResponse<bool>> deleteTransaction(String transactionID) async {
    try {
      await DioClient.dio.delete('/api/transactions/$transactionID');
      return ApiResponse.success(true);
    } on DioException catch (e) {
      return ApiResponse.error(DioClient.handleError(e));
    }
  }
}
