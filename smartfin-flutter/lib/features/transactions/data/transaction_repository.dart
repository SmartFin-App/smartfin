import 'package:smart_fin/core/network/dio_client.dart';

abstract class TransactionRepository {
  Future<ApiResponse<Map<String, dynamic>>> createTransaction({
    required String userID,
    required String merchant,
    required int amount,
    required String type,
    required String category,
    required String source,
    required DateTime date,
  });

  Future<ApiResponse<List<Map<String, dynamic>>>> getTransactions({
    required String userID,
    String? type,
    String? category,
    int limit = 50,
    int skip = 0,
  });

  Future<ApiResponse<Map<String, dynamic>>> getTransactionSummary({
    required String userID,
    String? month,
  });

  Future<ApiResponse<bool>> deleteTransaction(String transactionID);
}
