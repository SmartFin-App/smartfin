import 'dart:io';
import 'package:dio/dio.dart';


class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException({required this.message, this.statusCode});

  @override
  String toString() => message;
}

class ApiResponse<T> {
  final T? data;
  final String? error;
  final bool success;

  ApiResponse.success(this.data)
      : success = true,
        error = null;

  ApiResponse.error(this.error)
      : success = false,
        data = null;
}

class DioClient {
  static final Dio dio = _createDio();

  /// Returns the correct base URL depending on platform and run mode.
  /// Emulator:        flutter run --dart-define=IS_EMULATOR=true
  /// Physical device: flutter run
  static String get baseUrl {
    if (Platform.isAndroid) {
      const bool isEmulator =
          bool.fromEnvironment('IS_EMULATOR', defaultValue: true);
      return isEmulator
          ? 'http://10.0.2.2:3000'          // Android emulator → host loopback
          : 'http://192.168.1.118:3000';    // Physical device → Mac's LAN IP
    }
    return 'http://localhost:3000';          // iOS simulator / macOS
  }

  static Dio _createDio() {
    final dio = Dio(BaseOptions(
      baseUrl: DioClient.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      // Must exceed the backend's own 45s coach budget: both clocks start together,
      // so an equal value aborts requests the server has just finished.
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          print("REQUEST: ${options.method} ${options.path}");
          return handler.next(options);
        },
        onResponse: (response, handler) {
          print("RESPONSE: ${response.statusCode} ${response.requestOptions.path}");
          return handler.next(response);
        },
        onError: (DioException e, handler) {
          final errorMessage = handleError(e);
          print("ERROR: $errorMessage");
          return handler.next(DioException(
            requestOptions: e.requestOptions,
            error: ApiException(
              message: errorMessage,
              statusCode: e.response?.statusCode,
            ),
            response: e.response,
            type: e.type,
          ));
        },
      ),
    );

    return dio;
  }

  static String handleError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout || 
        e.type == DioExceptionType.receiveTimeout) {
      return "Connection timed out. Please check your internet.";
    }
    
    if (e.type == DioExceptionType.connectionError) {
      return "Cannot connect to server. Make sure the backend is running.";
    }

    if (e.response != null) {
      switch (e.response?.statusCode) {
        case 400:
          // The backend reports failures under "error"; "message" is its success key.
          final data = e.response?.data;
          if (data is Map<String, dynamic> &&
              (data['error'] ?? data['message']) != null) {
            return (data['error'] ?? data['message']).toString();
          } else if (data is String) {
            return data;
          }
          return "Bad request. Please verify your input.";
        case 401:
          return "Unauthorized. Please log in again.";
        case 404:
          return "Not found.";
        case 409:
          final data = e.response?.data;
          if (data is Map<String, dynamic> && data['error'] != null) {
            return data['error'].toString();
          }
          return "That already exists.";
        case 500:
          return "Server error. Please try again later.";
        default:
          return "Something went wrong. Please try again.";
      }
    }

    return "Something went wrong. Please try again.";
  }
}
