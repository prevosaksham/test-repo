import 'package:dio/dio.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/network_info.dart';

/// One parsed policy section (localized heading + body).
typedef PolicySectionData = ({String heading, String body});

/// Fetches the localized legal content (Privacy Policy) from the backend.
class PolicyRepository {
  PolicyRepository({Dio? dio, NetworkInfo? networkInfo})
      : _dio = dio ?? DioClient.instance.dio,
        _network = networkInfo ?? NetworkInfo();

  final Dio _dio;
  final NetworkInfo _network;

  /// `POST /privacy-policy { language }` (en/hi/mr) → title + sections.
  Future<({String title, List<PolicySectionData> sections})> getPrivacyPolicy(
      String language) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      final res = await _dio.post(ApiEndpoints.privacyPolicy,
          data: {'language': language});
      final body = res.data;
      final data = body is Map && body['data'] is Map
          ? Map<String, dynamic>.from(body['data'] as Map)
          : <String, dynamic>{};
      final title = (data['title'] ?? '').toString();
      final raw = data['sections'] is List ? data['sections'] as List : const [];
      final sections = raw
          .whereType<Map>()
          .map<PolicySectionData>((e) => (
                heading: (e['title'] ?? '').toString(),
                body: (e['content'] ?? '').toString(),
              ))
          .toList();
      return (title: title, sections: sections);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  /// `POST /privacy-policy/terms { language }` (en/hi/mr) → title + sections.
  Future<({String title, List<PolicySectionData> sections})> getTerms(
      String language) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      final res = await _dio.post(ApiEndpoints.privacyPolicyTerms,
          data: {'language': language});
      final body = res.data;
      final data = body is Map && body['data'] is Map
          ? Map<String, dynamic>.from(body['data'] as Map)
          : <String, dynamic>{};
      final title = (data['title'] ?? '').toString();
      final raw = data['sections'] is List ? data['sections'] as List : const [];
      final sections = raw
          .whereType<Map>()
          .map<PolicySectionData>((e) => (
                heading: (e['title'] ?? '').toString(),
                body: (e['content'] ?? '').toString(),
              ))
          .toList();
      return (title: title, sections: sections);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }
}
