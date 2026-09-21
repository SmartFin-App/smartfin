import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:smart_fin/core/network/dio_client.dart';

/// A write the coach made while answering: an expense it recorded or a budget
/// it set. [label] is preformatted by the backend ("Added ฿120 · 7-Eleven").
class CoachAction {
  final String action;
  final String label;

  /// The new transaction's id, for `add_transaction` only.
  final String? id;

  const CoachAction({required this.action, required this.label, this.id});

  /// Reads `actions_taken` from a reply or `actions` from a stored message.
  /// Records without a label are skipped rather than shown blank.
  static List<CoachAction> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map && e['label'] is String && (e['label'] as String).isNotEmpty)
          CoachAction(
            action: e['action'] as String? ?? '',
            label: e['label'] as String,
            id: e['id'] as String?,
          ),
    ];
  }
}

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

  Future<ApiResponse<({String text, List<CoachAction> actions})>> askCoach({
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
      final data = response.data as Map<String, dynamic>;
      return ApiResponse.success((
        text: data['response'] as String,
        actions: CoachAction.listFrom(data['actions_taken']),
      ));
    } on DioException catch (e) {
      debugPrint('CoachError: ${e.response?.data}');
      return ApiResponse.error(DioClient.handleError(e));
    }
  }
}
