import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/auth_session.dart';
import '../../data/models/forgot_password_response.dart';
import '../../data/repositories/auth_repository.dart';

part 'otp_event.dart';
part 'otp_state.dart';

class OtpBloc extends Bloc<OtpEvent, OtpState> {
  OtpBloc({required AuthRepository repository})
      : _repository = repository,
        super(const OtpState()) {
    on<OtpVerifyRequested>(_onVerify);
    on<OtpForgotVerifyRequested>(_onForgotVerify);
    on<OtpResendRequested>(_onResend);
  }

  final AuthRepository _repository;

  // Login-flow OTP verification.
  Future<void> _onVerify(OtpVerifyRequested e, Emitter<OtpState> emit) async {
    emit(state.copyWith(status: OtpStatus.verifying, errorMessage: null));
    try {
      final session =
          await _repository.verifyOtp(loginToken: e.loginToken, otp: e.otp);
      emit(state.copyWith(status: OtpStatus.verified, session: session));
    } on ApiException catch (ex) {
      emit(state.copyWith(
          status: OtpStatus.verifyFailure, errorMessage: ex.message));
    }
  }

  // Forgot-flow OTP verification — backend requires this before reset-password.
  Future<void> _onForgotVerify(
      OtpForgotVerifyRequested e, Emitter<OtpState> emit) async {
    emit(state.copyWith(status: OtpStatus.verifying, errorMessage: null));
    try {
      await _repository.verifyForgotOtp(email: e.email, otp: e.otp);
      emit(state.copyWith(status: OtpStatus.forgotVerified));
    } on ApiException catch (ex) {
      emit(state.copyWith(
          status: OtpStatus.verifyFailure, errorMessage: ex.message));
    }
  }

  // Forgot-flow OTP resend.
  Future<void> _onResend(OtpResendRequested e, Emitter<OtpState> emit) async {
    emit(state.copyWith(status: OtpStatus.resending, errorMessage: null));
    try {
      final res = await _repository.resendForgotOtp(email: e.email);
      emit(state.copyWith(status: OtpStatus.resent, resend: res));
    } on ApiException catch (ex) {
      emit(state.copyWith(
          status: OtpStatus.resendFailure, errorMessage: ex.message));
    }
  }
}
