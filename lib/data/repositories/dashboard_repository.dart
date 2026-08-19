import 'package:dio/dio.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/network_info.dart';
import '../models/dashboard_stats.dart';
import '../models/followup_item.dart';
import '../models/followup_page.dart';
import '../services/dashboard_api_service.dart';

/// Home data use-cases: dashboard counts + the follow-up list. Checks
/// connectivity, calls the API, maps errors to [ApiException], parses models.
class DashboardRepository {
  DashboardRepository({DashboardApiService? service, NetworkInfo? networkInfo})
      : _service = service ?? DashboardApiService(),
        _network = networkInfo ?? NetworkInfo();

  final DashboardApiService _service;
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

  /// Counts come in `data[]` as `{name, count}` rows.
  Future<DashboardStats> getDashboard() {
    return _guard(() async {
      final json = await _service.dashboard();
      final data = json['data'];
      return DashboardStats.fromItems(data is List ? data : const []);
    });
  }

  /// Follow-ups live in `data.followups[]` (current API) or `data[]` (legacy).
  /// May be empty until follow-ups exist.
  Future<List<FollowupItem>> getFollowups() {
    return _guard(() async {
      final json = await _service.followups();
      final data = json['data'];
      final list = (data is Map) ? data['followups'] : data;
      if (list is! List) return <FollowupItem>[];
      return list
          .whereType<Map>()
          .map((e) => FollowupItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    });
  }

  /// Every follow-up (both call + visit) for the "View All" screen. The backend
  /// `/followup/list` does NOT filter by `followupType` server-side, so we pull
  /// the full list once (a generous page_limit) and the screen splits by tab,
  /// searches, and paginates client-side.
  Future<List<FollowupItem>> getAllFollowups() {
    return _guard(() async {
      final json = await _service.followupsPaged(page: 1, limit: 1000);
      final page = FollowupPage.fromJson(json['data'], requestedPage: 1);
      return page.items;
    });
  }

  /// Follow-up history (`POST /followup/history`) — server-paginated with a
  /// search term + optional `date` filter (yyyy-MM-dd). Returns one page.
  Future<FollowupPage> getFollowupHistory({
    required int page,
    int limit = 10,
    String search = '',
    String date = '',
    String followupType = '', // '' = all, else 'CALL' / 'VISIT'
  }) {
    return _guard(() async {
      final json = await _service.followupHistory(
        page: page,
        limit: limit,
        search: search,
        date: date,
        followupType: followupType,
      );
      return FollowupPage.fromJson(json['data'], requestedPage: page);
    });
  }
}
