import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/lead_trend.dart';
import '../../data/repositories/report_repository.dart';

part 'reports_event.dart';
part 'reports_state.dart';

class ReportsBloc extends Bloc<ReportsEvent, ReportsState> {
  ReportsBloc({required ReportRepository repository})
      : _repository = repository,
        super(const ReportsState()) {
    on<ReportsRequested>(_onRequested);
  }

  final ReportRepository _repository;

  Future<void> _onRequested(
    ReportsRequested event,
    Emitter<ReportsState> emit,
  ) async {
    emit(state.copyWith(
      status: ReportsStatus.loading,
      year: event.year,
      errorMessage: null,
    ));
    try {
      final trend =
          await _repository.getMonthlyLeadTrend(year: event.year.toString());
      emit(state.copyWith(status: ReportsStatus.success, trend: trend));
    } on ApiException catch (e) {
      emit(state.copyWith(
          status: ReportsStatus.failure, errorMessage: e.message));
    } catch (_) {
      emit(state.copyWith(
        status: ReportsStatus.failure,
        errorMessage: 'Something went wrong. Please try again.',
      ));
    }
  }
}
