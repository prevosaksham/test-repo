import 'package:dio/dio.dart';
import 'api_exception.dart';

/// Standard backend response envelope:
///
///   { "success": true, "statusCode": 201, "message": "Call created successfully", "data": ... }
///
/// [unwrapResponse] validates a 2xx Dio response against this envelope and
/// returns the full decoded body map. When the body explicitly reports
/// `success: false`, it throws an [ApiException] carrying the server's exact
/// `message` and `statusCode` — so the UI shows the real backend message and
/// callers can branch on the status code.
///
/// Endpoints that don't (yet) send the envelope pass through unchanged: a 2xx
/// HTTP status already means success here (the Dio client's `validateStatus`
/// turns non-2xx into a `DioException`).
Map<String, dynamic> unwrapResponse(Response res) {
  final body = _asMap(res.data);
  if (body.containsKey('success')) {
    final ok = body['success'] == true || body['success'] == 1;
    if (!ok) {
      final msg = (body['message'] ?? body['msg'] ?? '').toString().trim();
      throw ApiException(
        msg.isNotEmpty ? msg : 'Request failed. Please try again.',
        statusCode: _asInt(body['statusCode']) ?? res.statusCode,
        data: body,
      );
    }
  }
  return body;
}

/// The server's human message for a successful response, or [fallback] when the
/// body carries none. Use this to show "proper response" toasts on success.
String responseMessage(Map<String, dynamic> body, {String fallback = ''}) {
  final m = (body['message'] ?? body['msg'] ?? '').toString().trim();
  return m.isNotEmpty ? m : fallback;
}

/// The envelope's `statusCode` (e.g. 200 / 201), or null when absent.
int? responseStatusCode(Map<String, dynamic> body) => _asInt(body['statusCode']);

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return <String, dynamic>{};
}

int? _asInt(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}');
