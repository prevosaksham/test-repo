import 'package:dio/dio.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/network_info.dart';
import '../models/lead_trend.dart';
import '../services/report_api_service.dart';

/// Reports use-case: connectivity check, API call, error mapping, parsing.
class ReportRepository {
  ReportRepository({ReportApiService? service, NetworkInfo? networkInfo})
      : _service = service ?? ReportApiService(),
        _network = networkInfo ?? NetworkInfo();

  final ReportApiService _service;
  final NetworkInfo _network;

  Future<void> _ensureOnline() async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    await _ensureOnline();
    try {
      return await run();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  Future<LeadTrend> getMonthlyLeadTrend({required String year}) {
    return _guard(() async {
      final json = await _service.monthlyLeadTrend(year: year);
      return LeadTrend.fromJson(json);
    });
  }
}
