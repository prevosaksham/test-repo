import 'package:dio/dio.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/network_info.dart';
import '../../core/network/token_store.dart';
import '../local/auth_storage.dart';
import '../models/auth_session.dart';
import '../models/forgot_password_response.dart';
import '../models/login_response.dart';
import '../services/auth_api_service.dart';

/// Coordinates the auth use-cases: checks connectivity, calls the API, maps
/// errors to [ApiException], persists the session, and stashes tokens.
class AuthRepository {
  AuthRepository({AuthApiService? service, NetworkInfo? networkInfo})
      : _service = service ?? AuthApiService(),
        _network = networkInfo ?? NetworkInfo();

  final AuthApiService _service;
  final NetworkInfo _network;

  Future<void> _ensureOnline() async {
    if (!await _network.isConnected) {
      throw ApiException('No internet connection. Please check and try again.');
    }
  }

  /// Wraps a call so every error becomes a clean [ApiException].
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

  // ---- Login: step 1 (credentials -> OTP) ----
  Future<LoginResponse> login({
    required String email,
    required String password,
    String role = AppConstants.defaultRole,
  }) {
    return _guard(() async {
      final json = await _service.login(
        email: email,
        password: password,
        role: role,
      );
      final result = LoginResponse.fromJson(json);
      if (result.loginToken.isNotEmpty) {
        TokenStore.instance.loginToken = result.loginToken;
      }
      return result;
    });
  }

  // ---- Login: step 2 (verify OTP -> session) ----
  Future<AuthSession> verifyOtp({
    required String loginToken,
    required String otp,
  }) {
    return _guard(() async {
      final json = await _service.verifyOtp(loginToken: loginToken, otp: otp);
      final session = AuthSession.fromJson(json);
      // Persist + keep the bearer token for authenticated requests.
      TokenStore.instance.authToken = session.accessToken;
      TokenStore.instance.loginToken = null;
      await AuthStorage.instance.save(session);
      return session;
    });
  }

  // ---- Forgot password: send OTP ----
  Future<ForgotPasswordResponse> forgotPassword({
    required String email,
    String role = AppConstants.defaultRole,
  }) {
    return _guard(() async {
      final json = await _service.forgotPassword(email: email, role: role);
      return ForgotPasswordResponse.fromJson(json);
    });
  }

  // ---- Forgot password: resend OTP ----
  Future<ForgotPasswordResponse> resendForgotOtp({
    required String email,
    String role = AppConstants.defaultRole,
  }) {
    return _guard(() async {
      final json = await _service.resendForgotOtp(email: email, role: role);
      return ForgotPasswordResponse.fromJson(json);
    });
  }

  // ---- Forgot password: verify OTP (must run before reset) ----
  Future<String> verifyForgotOtp({
    required String email,
    required String otp,
    String role = AppConstants.defaultRole,
  }) {
    return _guard(() async {
      final json =
          await _service.verifyForgotOtp(email: email, otp: otp, role: role);
      return json['message']?.toString() ?? 'OTP verified';
    });
  }

  // ---- Reset password ----
  Future<String> resetPassword({
    required String email,
    required String newPassword,
  }) {
    return _guard(() async {
      final json =
          await _service.resetPassword(email: email, newPassword: newPassword);
      return json['message']?.toString() ?? 'Password reset successfully';
    });
  }

  // ---- Session helpers ----
  Future<void> logout() async {
    TokenStore.instance.clear();
    await AuthStorage.instance.clear();
  }
}
