import 'package:equatable/equatable.dart';

/// Response of POST /auth/login.
///
/// Parsing is intentionally defensive: the API shape can change, so every
/// field is read through null-safe, type-tolerant helpers and never throws.
class LoginResponse extends Equatable {
  const LoginResponse({
    required this.otpRequired,
    required this.loginToken,
    required this.otpSentTo,
    required this.expiresIn,
    required this.resendCooldown,
    required this.maxResends,
  });

  final bool otpRequired;
  final String loginToken;
  final String otpSentTo;
  final int expiresIn; // seconds
  final int resendCooldown; // seconds
  final int maxResends;

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      otpRequired: _asBool(json['otpRequired']),
      loginToken: _asString(json['loginToken']),
      otpSentTo: _asString(json['otpSentTo']),
      expiresIn: _asInt(json['expiresIn'], fallback: 600),
      resendCooldown: _asInt(json['resendCooldown'], fallback: 30),
      maxResends: _asInt(json['maxResends'], fallback: 3),
    );
  }

  @override
  List<Object?> get props =>
      [otpRequired, loginToken, otpSentTo, expiresIn, resendCooldown, maxResends];

  // ---- tolerant coercion helpers ----
  static bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v.toLowerCase() == 'true' || v == '1';
    return false;
  }

  static String _asString(dynamic v) => v == null ? '' : v.toString();

  static int _asInt(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }
}
