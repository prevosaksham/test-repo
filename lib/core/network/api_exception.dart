import 'package:dio/dio.dart';

/// A single, UI-friendly error type the whole app can rely on.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.data});

  final String message;
  final int? statusCode;
  final dynamic data;

  /// No-internet is a common, specific case worth flagging.
  bool get isNetwork => statusCode == null;

  @override
  String toString() => message;

  /// Maps a low-level [DioException] into a clean, human message.
  factory ApiException.fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException('Connection timed out. Please try again.');
      case DioExceptionType.connectionError:
        return ApiException(
          'Unable to reach the server. Check your internet connection.',
        );
      case DioExceptionType.badCertificate:
        return ApiException('Secure connection failed.');
      case DioExceptionType.cancel:
        return ApiException('Request cancelled.');
      case DioExceptionType.badResponse:
        return ApiException(
          _messageFromResponse(e.response),
          statusCode: e.response?.statusCode,
          data: e.response?.data,
        );
      case DioExceptionType.unknown:
        return ApiException(
          'Something went wrong. Please try again.',
        );
    }
  }

  /// Pull the EXACT message the server sent, whatever shape it arrives in:
  ///   {"message": "..."}                          (success wrapper errors)
  ///   {"error": "..."} / {"error": {"message": …}} (raw / 500 errors)
  ///   {"errors": [{"message": …}, …]}             (validation lists)
  /// Only falls back to a generic line when the body carries NO message.
  static String _messageFromResponse(Response? res) {
    final serverMsg = _digMessage(res?.data);
    if (serverMsg != null && serverMsg.trim().isNotEmpty) {
      return serverMsg.trim();
    }
    final code = res?.statusCode;
    if (code == 401) return 'Invalid credentials.';
    if (code == 403) return 'You are not allowed to perform this action.';
    if (code == 404) return 'Service not found.';
    if (code != null && code >= 500) {
      return 'Server error. Please try again later.';
    }
    return 'Request failed. Please try again.';
  }

  /// Recursively digs the first human-readable message out of an error body
  /// (handles String / Map / List and nested `error` / `errors` objects).
  static String? _digMessage(dynamic data) {
    if (data is String) {
      return data.trim().isNotEmpty ? data : null;
    }
    if (data is Map) {
      for (final key in ['message', 'msg', 'detail', 'error_description']) {
        final v = data[key];
        if (v is String && v.trim().isNotEmpty) return v;
      }
      for (final key in ['error', 'errors']) {
        if (data.containsKey(key)) {
          final nested = _digMessage(data[key]);
          if (nested != null) return nested;
        }
      }
    }
    if (data is List) {
      for (final item in data) {
        final nested = _digMessage(item);
        if (nested != null) return nested;
      }
    }
    return null;
  }
}
