import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/lead_preview.dart';
import '../../data/repositories/lead_repository.dart';

part 'lead_preview_event.dart';
part 'lead_preview_state.dart';

/// Loads `POST /rm/getPreview` for one lead → the resume state (allowedActions,
/// leadDetails, leadStages, applicationStages) used by the interaction flow.
class LeadPreviewBloc extends Bloc<LeadPreviewEvent, LeadPreviewState> {
  LeadPreviewBloc({required LeadRepository repository})
      : _repository = repository,
        super(const LeadPreviewState()) {
    on<LeadPreviewRequested>(_onRequested);
  }

  final LeadRepository _repository;

  Future<void> _onRequested(
    LeadPreviewRequested event,
    Emitter<LeadPreviewState> emit,
  ) async {
    emit(state.copyWith(
      status: LeadPreviewStatus.loading,
      errorMessage: null,
    ));
    try {
      final preview = await _repository.getPreview(leadId: event.leadId);
      emit(state.copyWith(
          status: LeadPreviewStatus.success, preview: preview));
    } on ApiException catch (e) {
      emit(state.copyWith(
          status: LeadPreviewStatus.failure, errorMessage: e.message));
    } catch (_) {
      emit(state.copyWith(
        status: LeadPreviewStatus.failure,
        errorMessage: 'Something went wrong. Please try again.',
      ));
    }
  }
}
