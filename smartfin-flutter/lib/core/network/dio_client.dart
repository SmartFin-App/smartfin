import 'package:flutter/foundation.dart';
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

  /// The backend's address, set at build time with API_BASE_URL:
  ///
  ///   Deployed backend: `flutter build apk --dart-define=API_BASE_URL=https://api.example.com`
  ///   Physical device:  `flutter run --dart-define=API_BASE_URL=http://MAC_LAN_IP:3000`
  ///
  /// Without it the app assumes a local backend on port 3000, which only an
  /// emulator or simulator can reach. A real phone always needs the define:
  /// 'localhost' there means the phone itself, and a LAN IP baked in here went
  /// stale whenever the Mac's address changed.
  static String get baseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) {
      // Paths start with '/', so a trailing slash here would double it.
      return override.endsWith('/')
          ? override.substring(0, override.length - 1)
          : override;
    }
    return Platform.isAndroid
        ? 'http://10.0.2.2:3000' // Android emulator → the Mac's loopback
        : 'http://localhost:3000'; // iOS simulator / macOS
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
          debugPrint("REQUEST: ${options.method} ${options.path}");
          return handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint("RESPONSE: ${response.statusCode} ${response.requestOptions.path}");
          return handler.next(response);
        },
        onError: (DioException e, handler) {
          final errorMessage = handleError(e);
          debugPrint("ERROR: $errorMessage");
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
