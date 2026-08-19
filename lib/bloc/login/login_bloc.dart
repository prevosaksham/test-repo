import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/login_response.dart';
import '../../data/repositories/auth_repository.dart';

part 'login_event.dart';
part 'login_state.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  LoginBloc({required AuthRepository repository})
      : _repository = repository,
        super(const LoginState()) {
    on<LoginSubmitted>(_onSubmitted);
    on<LoginReset>((_, emit) => emit(const LoginState()));
  }

  final AuthRepository _repository;

  Future<void> _onSubmitted(
    LoginSubmitted event,
    Emitter<LoginState> emit,
  ) async {
    emit(state.copyWith(status: LoginStatus.loading, errorMessage: null));
    try {
      final res = await _repository.login(
        email: event.email.trim(),
        password: event.password,
      );
      emit(state.copyWith(
        status: res.otpRequired ? LoginStatus.otpRequired : LoginStatus.success,
        response: res,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(status: LoginStatus.failure, errorMessage: e.message));
    } catch (_) {
      emit(state.copyWith(
        status: LoginStatus.failure,
        errorMessage: 'Something went wrong. Please try again.',
      ));
    }
  }
}
