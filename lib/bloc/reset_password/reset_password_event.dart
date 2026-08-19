part of 'reset_password_bloc.dart';

abstract class ResetPasswordEvent extends Equatable {
  const ResetPasswordEvent();
  @override
  List<Object?> get props => [];
}

class ResetPasswordSubmitted extends ResetPasswordEvent {
  const ResetPasswordSubmitted({
    required this.email,
    required this.newPassword,
  });
  final String email;
  final String newPassword;
  @override
  List<Object?> get props => [email, newPassword];
}
