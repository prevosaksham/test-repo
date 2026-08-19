import 'package:dio/dio.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_response.dart';
import '../../core/network/dio_client.dart';

/// Wrapper around the Reports calls (monthly lead trend + yearly summary).
class ReportApiService {
  ReportApiService({Dio? dio}) : _dio = dio ?? DioClient.instance.dio;

  final Dio _dio;

  Future<Map<String, dynamic>> monthlyLeadTrend({required String year}) async {
    final res = await _dio.post(
      ApiEndpoints.getMonthlyLeadTrend,
      data: {'year': year},
    );
    return unwrapResponse(res);
  }
}
