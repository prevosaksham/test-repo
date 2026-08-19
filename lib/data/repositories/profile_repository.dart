import 'package:dio/dio.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/dio_client.dart';
import '../../core/network/network_info.dart';
import '../../dashboard/more/profile_data.dart';

/// My Profile use-case: `POST /rm/get-profile` (empty body, Bearer attached by
/// the Dio interceptor) → [ProfileData].
class ProfileRepository {
  ProfileRepository({Dio? dio, NetworkInfo? networkInfo})
      : _dio = dio ?? DioClient.instance.dio,
        _network = networkInfo ?? NetworkInfo();

  final Dio _dio;
  final NetworkInfo _network;

  Future<ProfileData> getProfile() => _get(ApiEndpoints.rmGetProfile);

  /// Editable profile fields for the Edit Profile form (GET /rm/edit-profile).
  Future<ProfileData> getEditProfile() => _get(ApiEndpoints.rmEditProfile);

  /// Save the edited profile (`PUT /rm/edit-profile`). Returns the parsed
  /// server response (caller checks `success`/`status` + `message`).
  Future<dynamic> updateProfile({
    required String fullName,
    required String mobile,
    required String dateOfBirth,
  }) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      final res = await _dio.put(
        ApiEndpoints.rmEditProfile,
        data: {
          'fullName': fullName,
          'mobile': mobile,
          'dateOfBirth': dateOfBirth,
        },
      );
      return res.data;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }

  Future<ProfileData> _get(String path) async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
    try {
      final res = await _dio.get(path);
      final body = res.data;
      return ProfileData.fromJson(
        body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Something went wrong. Please try again.');
    }
  }
}
