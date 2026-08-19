import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/dashboard_stats.dart';
import '../../data/models/followup_item.dart';
import '../../data/repositories/dashboard_repository.dart';

part 'dashboard_event.dart';
part 'dashboard_state.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  DashboardBloc({required DashboardRepository repository})
      : _repository = repository,
        super(const DashboardState()) {
    on<DashboardLoadRequested>(_onLoad);
  }

  final DashboardRepository _repository;

  Future<void> _onLoad(
    DashboardLoadRequested event,
    Emitter<DashboardState> emit,
  ) async {
    emit(state.copyWith(status: DashboardStatus.loading, errorMessage: null));
    try {
      // Both Home calls run together; split follow-ups by type for the tabs.
      final results = await Future.wait([
        _repository.getDashboard(),
        _repository.getFollowups(),
      ]);
      final stats = results[0] as DashboardStats;
      final followups = results[1] as List<FollowupItem>;
      emit(state.copyWith(
        status: DashboardStatus.success,
        stats: stats,
        calls: followups.where((f) => f.isCall).toList(),
        visits: followups.where((f) => f.isVisit).toList(),
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(
          status: DashboardStatus.failure, errorMessage: e.message));
    } catch (_) {
      emit(state.copyWith(
        status: DashboardStatus.failure,
        errorMessage: 'Something went wrong. Please try again.',
      ));
    }
  }
}
