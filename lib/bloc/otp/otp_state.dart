part of 'otp_bloc.dart';

enum OtpStatus {
  initial,
  verifying,
  verified,
  forgotVerified,
  verifyFailure,
  resending,
  resent,
  resendFailure,
}

class OtpState extends Equatable {
  const OtpState({
    this.status = OtpStatus.initial,
    this.session,
    this.resend,
    this.errorMessage,
  });

  final OtpStatus status;
  final AuthSession? session;
  final ForgotPasswordResponse? resend;
  final String? errorMessage;

  bool get isVerifying => status == OtpStatus.verifying;
  bool get isResending => status == OtpStatus.resending;

  OtpState copyWith({
    OtpStatus? status,
    AuthSession? session,
    ForgotPasswordResponse? resend,
    String? errorMessage,
  }) {
    return OtpState(
      status: status ?? this.status,
      session: session ?? this.session,
      resend: resend ?? this.resend,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, session, resend, errorMessage];
}
