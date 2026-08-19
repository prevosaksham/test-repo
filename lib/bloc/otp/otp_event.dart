part of 'otp_bloc.dart';

abstract class OtpEvent extends Equatable {
  const OtpEvent();
  @override
  List<Object?> get props => [];
}

/// Verify the login OTP (login flow).
class OtpVerifyRequested extends OtpEvent {
  const OtpVerifyRequested({required this.loginToken, required this.otp});
  final String loginToken;
  final String otp;
  @override
  List<Object?> get props => [loginToken, otp];
}

/// Verify the forgot-password OTP (forgot flow) — required before reset.
class OtpForgotVerifyRequested extends OtpEvent {
  const OtpForgotVerifyRequested({required this.email, required this.otp});
  final String email;
  final String otp;
  @override
  List<Object?> get props => [email, otp];
}

/// Resend the forgot-password OTP (forgot flow).
class OtpResendRequested extends OtpEvent {
  const OtpResendRequested({required this.email});
  final String email;
  @override
  List<Object?> get props => [email];
}
