/// Response of /auth/forgot-password and (reused shape) /auth/resend-forgot-otp.
class ForgotPasswordResponse {
  const ForgotPasswordResponse({
    required this.otpSentTo,
    required this.expiresIn,
    required this.resendCooldown,
    required this.maxResends,
    this.message = '',
    this.resendCount = 0,
  });

  final String message;
  final String otpSentTo;
  final int expiresIn;
  final int resendCooldown;
  final int maxResends;
  final int resendCount;

  factory ForgotPasswordResponse.fromJson(Map<String, dynamic> json) {
    int i(dynamic v, int f) => (v is num)
        ? v.toInt()
        : int.tryParse(v?.toString() ?? '') ?? f;
    return ForgotPasswordResponse(
      message: json['message']?.toString() ?? '',
      otpSentTo: json['otpSentTo']?.toString() ?? '',
      expiresIn: i(json['expiresIn'], 600),
      resendCooldown: i(json['resendCooldown'], 30),
      maxResends: i(json['maxResends'], 3),
      resendCount: i(json['resendCount'], 0),
    );
  }
}
