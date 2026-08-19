import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/forgot_password_response.dart';
import '../../data/repositories/auth_repository.dart';

part 'forgot_password_event.dart';
part 'forgot_password_state.dart';

class ForgotPasswordBloc
    extends Bloc<ForgotPasswordEvent, ForgotPasswordState> {
  ForgotPasswordBloc({required AuthRepository repository})
      : _repository = repository,
        super(const ForgotPasswordState()) {
    on<ForgotPasswordSubmitted>(_onSubmitted);
  }

  final AuthRepository _repository;

  Future<void> _onSubmitted(
    ForgotPasswordSubmitted e,
    Emitter<ForgotPasswordState> emit,
  ) async {
    emit(state.copyWith(status: ForgotStatus.loading, errorMessage: null));
    try {
      final res = await _repository.forgotPassword(email: e.email.trim());
      emit(state.copyWith(status: ForgotStatus.success, response: res));
    } on ApiException catch (ex) {
      emit(state.copyWith(
          status: ForgotStatus.failure, errorMessage: ex.message));
    }
  }
}
