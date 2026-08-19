import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/auth_repository.dart';

part 'reset_password_event.dart';
part 'reset_password_state.dart';

class ResetPasswordBloc extends Bloc<ResetPasswordEvent, ResetPasswordState> {
  ResetPasswordBloc({required AuthRepository repository})
      : _repository = repository,
        super(const ResetPasswordState()) {
    on<ResetPasswordSubmitted>(_onSubmitted);
  }

  final AuthRepository _repository;

  Future<void> _onSubmitted(
    ResetPasswordSubmitted e,
    Emitter<ResetPasswordState> emit,
  ) async {
    emit(state.copyWith(status: ResetStatus.loading, errorMessage: null));
    try {
      final message = await _repository.resetPassword(
        email: e.email,
        newPassword: e.newPassword,
      );
      emit(state.copyWith(status: ResetStatus.success, message: message));
    } on ApiException catch (ex) {
      emit(state.copyWith(
          status: ResetStatus.failure, errorMessage: ex.message));
    }
  }
}
