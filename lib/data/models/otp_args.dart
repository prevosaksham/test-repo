/// Which flow opened the OTP screen — controls what "Verify" does next.
enum OtpFlow { login, forgotPassword }

/// Everything the OTP screen needs, regardless of which flow launched it.
class OtpArgs {
  const OtpArgs({
    required this.sentTo,
    required this.flow,
    this.email = '',
    this.loginToken = '',
    this.expiresIn = 600,
    this.resendCooldown = 30,
    this.maxResends = 3,
  });

  /// Masked email/phone shown to the user (e.g. "ka***@gmail.com").
  final String sentTo;

  /// Real email — needed to resend (forgot) and to reset the password.
  final String email;

  final OtpFlow flow;

  /// Short-lived token from /auth/login, used to verify the login OTP.
  final String loginToken;

  final int expiresIn; // seconds the OTP stays valid
  final int resendCooldown; // seconds before "Resend" is allowed
  final int maxResends;
}
