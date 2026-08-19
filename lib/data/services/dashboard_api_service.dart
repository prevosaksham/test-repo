import 'package:dio/dio.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_response.dart';
import '../../core/network/dio_client.dart';

/// Thin wrapper around the Home GET calls (dashboard counts + follow-up list).
/// Returns the decoded body; errors surface as [DioException].
class DashboardApiService {
  DashboardApiService({Dio? dio}) : _dio = dio ?? DioClient.instance.dio;

  final Dio _dio;

  Future<Map<String, dynamic>> dashboard() => _get(ApiEndpoints.rmDashboard);

  /// Whole follow-up list (Home split). Uses the paginated POST with a generous
  /// limit so all rows come back.
  Future<Map<String, dynamic>> followups() =>
      followupsPaged(page: 1, limit: 10);

  /// Follow-up list — now a POST with a pagination/search body (same shape as
  /// `/rm/list`): `{page_limit, page_number, search}`.
  Future<Map<String, dynamic>> followupsPaged({
    required int page,
    required int limit,
    String search = '',
  }) async {
    final res = await _dio.post(
      ApiEndpoints.followupList,
      data: {
        'page_limit': limit.toString(),
        'page_number': page.toString(),
        'search': search.trim(),
      },
    );
    return unwrapResponse(res);
  }

  /// Follow-up history — POST `{page_limit, page_number, search, date}`.
  /// [date] is `yyyy-MM-dd` (empty = no date filter).
  Future<Map<String, dynamic>> followupHistory({
    required int page,
    required int limit,
    String search = '',
    String date = '',
    String followupType = '', // '' = all, else 'CALL' / 'VISIT'
  }) async {
    final res = await _dio.post(
      ApiEndpoints.followupHistory,
      data: {
        'page_limit': limit,
        'page_number': page,
        'search': search.trim(),
        'date': date.trim(),
        if (followupType.trim().isNotEmpty) 'followupType': followupType.trim(),
      },
    );
    return unwrapResponse(res);
  }

  // ---- shared GET + safe map decoding ----
  Future<Map<String, dynamic>> _get(String path) async {
    final res = await _dio.get(path);
    return unwrapResponse(res);
  }
}
