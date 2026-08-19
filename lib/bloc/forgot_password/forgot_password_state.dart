part of 'forgot_password_bloc.dart';

enum ForgotStatus { initial, loading, success, failure }

class ForgotPasswordState extends Equatable {
  const ForgotPasswordState({
    this.status = ForgotStatus.initial,
    this.response,
    this.errorMessage,
  });

  final ForgotStatus status;
  final ForgotPasswordResponse? response;
  final String? errorMessage;

  bool get isLoading => status == ForgotStatus.loading;

  ForgotPasswordState copyWith({
    ForgotStatus? status,
    ForgotPasswordResponse? response,
    String? errorMessage,
  }) {
    return ForgotPasswordState(
      status: status ?? this.status,
      response: response ?? this.response,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, response, errorMessage];
}
