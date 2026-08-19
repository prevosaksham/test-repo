import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'api_endpoints.dart';
import 'token_store.dart';

/// A single configured Dio instance for the whole app.
///
/// Why the no-cache handling: occasionally an updated API response wasn't
/// reflected because an intermediary (or a kept-alive connection) served a
/// stale body. We defeat that two ways:
///   1. Send no-cache request headers on every call.
///   2. Append a cache-busting timestamp to GET requests.
/// [clearCache] additionally force-closes pooled connections.
class DioClient {
  DioClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiEndpoints.baseUrl,
        // No timeouts anywhere (Duration.zero = unlimited): connect, send and
        // receive all wait indefinitely so slow server-side work (e.g. document
        // OCR) never aborts. NOTE: with no connectTimeout, an unreachable server
        // / no network will hang the request until the OS gives up.
        connectTimeout: Duration.zero,
        receiveTimeout: Duration.zero,
        sendTimeout: Duration.zero,
        responseType: ResponseType.json,
        // Treat only 2xx as success; everything else becomes a DioException
        // so error handling is centralised.
        validateStatus: (status) => status != null && status >= 200 && status < 300,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // 1) Always ask for a fresh response.
          options.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate';
          options.headers['Pragma'] = 'no-cache';
          options.headers['Expires'] = '0';

          // 2) Cache-bust GETs (POST/PUT aren't cached).
          if (options.method.toUpperCase() == 'GET') {
            options.queryParameters = {
              ...options.queryParameters,
              '_': DateTime.now().millisecondsSinceEpoch,
            };
          }

          // 3) Attach auth token when we have one.
          final token = TokenStore.instance.authToken;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          _log('→ ${options.method} ${options.uri}');
          if (options.data != null) _log('  body: ${options.data}');
          handler.next(options);
        },
        onResponse: (response, handler) {
          _log('← ${response.statusCode} ${response.requestOptions.uri}');
          handler.next(response);
        },
        onError: (error, handler) {
          _log(
            '✕ ${error.response?.statusCode} ${error.requestOptions.uri} :: ${error.message}',
          );
          handler.next(error);
        },
      ),
    );
  }

  static final DioClient instance = DioClient._internal();

  late final Dio _dio;
  Dio get dio => _dio;

  /// Drop pooled/kept-alive connections so the next request opens fresh —
  /// useful after logout or when you suspect a stale kept-alive response.
  /// Replaces the adapter instead of closing Dio, so the instance stays usable.
  void clearCache() {
    _dio.httpClientAdapter = IOHttpClientAdapter();
  }

  void _log(String msg) {
    if (kDebugMode) developer.log(msg, name: 'DIO');
  }
}
