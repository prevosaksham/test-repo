part of 'reset_password_bloc.dart';

enum ResetStatus { initial, loading, success, failure }

class ResetPasswordState extends Equatable {
  const ResetPasswordState({
    this.status = ResetStatus.initial,
    this.message,
    this.errorMessage,
  });

  final ResetStatus status;
  final String? message;
  final String? errorMessage;

  bool get isLoading => status == ResetStatus.loading;

  ResetPasswordState copyWith({
    ResetStatus? status,
    String? message,
    String? errorMessage,
  }) {
    return ResetPasswordState(
      status: status ?? this.status,
      message: message,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, message, errorMessage];
}
