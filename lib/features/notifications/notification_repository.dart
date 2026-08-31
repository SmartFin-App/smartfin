import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class NotificationRepository {
  final String baseUrl = dotenv.env['API_URL'] ?? 'http://localhost:3000/api';

  Future<void> sendNotificationToBackend(String userId, String rawText) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/notifications'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'raw_text': rawText,
        }),
      );

      if (response.statusCode == 200) {
        print('Successfully parsed and saved transaction from notification.');
      } else {
        print('Failed to send notification to backend: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error sending notification to backend: $e');
    }
  }
}
