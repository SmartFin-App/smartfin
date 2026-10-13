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
    int? splitTotal,
    int? splitPeople,
  });

  /// Expenses that may already record a payment: the same amount within a day
  /// of [date], or of today (as the server sees it) when none is given. Used to
  /// warn before saving, never to block.
  Future<ApiResponse<List<Map<String, dynamic>>>> findPossibleDuplicates({
    required String userID,
    required int amount,
    DateTime? date,
  });

  Future<ApiResponse<List<Map<String, dynamic>>>> getTransactions({
    required String userID,
    String? type,
    String? category,
    String? month,
    String? search,
    int limit = 50,
    int skip = 0,
  });

  Future<ApiResponse<Map<String, dynamic>>> getTransactionById({
    required String transactionID,
    required String userID,
  });

  Future<ApiResponse<bool>> updateTransaction({
    required String transactionID,
    required String userID,
    String? merchant,
    int? amount,
    String? type,
    String? category,
    DateTime? date,
  });

  Future<ApiResponse<Map<String, dynamic>>> getTransactionSummary({
    required String userID,
    String? month,
  });

  /// [userID] is required: the API scopes single-transaction routes to their
  /// owner, so a delete without it is rejected.
  Future<ApiResponse<bool>> deleteTransaction({
    required String transactionID,
    required String userID,
  });
}
