part of 'login_bloc.dart';

enum LoginStatus { initial, loading, otpRequired, success, failure }

class LoginState extends Equatable {
  const LoginState({
    this.status = LoginStatus.initial,
    this.response,
    this.errorMessage,
  });

  final LoginStatus status;
  final LoginResponse? response;
  final String? errorMessage;

  bool get isLoading => status == LoginStatus.loading;

  LoginState copyWith({
    LoginStatus? status,
    LoginResponse? response,
    String? errorMessage,
  }) {
    return LoginState(
      status: status ?? this.status,
      response: response ?? this.response,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, response, errorMessage];
}
