import 'package:dio/dio.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_response.dart';
import '../../core/network/dio_client.dart';

/// Thin wrapper around the raw auth HTTP calls. Returns the decoded body;
/// errors surface as [DioException] and are translated higher up.
class AuthApiService {
  AuthApiService({Dio? dio}) : _dio = dio ?? DioClient.instance.dio;

  final Dio _dio;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required String role,
  }) =>
      _post(ApiEndpoints.login, {
        'email': email,
        'password': password,
        'role': role,
      });

  Future<Map<String, dynamic>> verifyOtp({
    required String loginToken,
    required String otp,
  }) =>
      _post(ApiEndpoints.verifyOtp, {
        'loginToken': loginToken,
        'otp': otp,
      });

  Future<Map<String, dynamic>> forgotPassword({
    required String email,
    required String role,
  }) =>
      _post(ApiEndpoints.forgotPassword, {
        'email': email,
        'role': role,
      });

  Future<Map<String, dynamic>> resendForgotOtp({
    required String email,
    required String role,
  }) =>
      _post(ApiEndpoints.resendForgotOtp, {
        'email': email,
        'role': role,
      });

  Future<Map<String, dynamic>> verifyForgotOtp({
    required String email,
    required String otp,
    required String role,
  }) =>
      _post(ApiEndpoints.verifyForgotOtp, {
        'email': email,
        'otp': otp,
        'role': role,
      });

  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String newPassword,
  }) =>
      _post(ApiEndpoints.resetPassword, {
        'email': email,
        'newPassword': newPassword,
      });

  // ---- shared POST + safe map decoding ----
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final res = await _dio.post(path, data: body);
    return unwrapResponse(res);
  }
}
