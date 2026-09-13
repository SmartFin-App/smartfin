import 'package:smart_fin/core/network/dio_client.dart';

/// Recurring bills the user tracks by hand. Every date the UI shows comes from the
/// server already in Thai time (`due_date`, `days_until_due`, `status`), so the
/// client never converts the stored `next_due_date` instant itself.
abstract class SubscriptionRepository {
  /// The whole list envelope: `subscriptions` plus `monthly_total`,
  /// `active_count`, `overdue_count`, `due_soon_count` and `due_soon_total`.
  Future<ApiResponse<Map<String, dynamic>>> getSubscriptions({
    required String userID,
    bool activeOnly = false,
  });

  Future<ApiResponse<Map<String, dynamic>>> createSubscription({
    required String userID,
    required String name,
    required int amount,
    required String billingCycle,
    required DateTime nextDueDate,
    String category = 'Bills',
    String? note,
  });

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
  });

  // userID is required: single-subscription routes are scoped to their owner.
  Future<ApiResponse<bool>> deleteSubscription({
    required String subscriptionID,
    required String userID,
  });

  /// Logs the bill as an expense for today and moves its due date on a cycle.
  /// [expectedDueDate] is the `due_date` the user saw — the server refuses
  /// (409) if the bill has already moved on, so a double tap books one expense.
  Future<ApiResponse<Map<String, dynamic>>> markPaid({
    required String subscriptionID,
    required String userID,
    required String expectedDueDate,
  });
}
