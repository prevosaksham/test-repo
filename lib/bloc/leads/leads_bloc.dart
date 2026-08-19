import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/lead_item.dart';
import '../../data/repositories/lead_repository.dart';

part 'leads_event.dart';
part 'leads_state.dart';

class LeadsBloc extends Bloc<LeadsEvent, LeadsState> {
  LeadsBloc({required LeadRepository repository, this.pageLimit = 10})
      : _repository = repository,
        super(const LeadsState()) {
    on<LeadsRequested>(_onRequested);
    on<LeadsNextPageRequested>(_onNextPage);
    on<LeadsPageSelected>(_onPageSelected);
  }

  final LeadRepository _repository;
  final int pageLimit;

  // First page (also used for refresh / new search).
  Future<void> _onRequested(
    LeadsRequested event,
    Emitter<LeadsState> emit,
  ) async {
    emit(state.copyWith(
      status: LeadsStatus.loading,
      search: event.search,
      leadStatus: event.leadStatus,
      errorMessage: null,
    ));
    try {
      final page = await _repository.getLeads(
        page: 1,
        limit: pageLimit,
        search: event.search,
        leadStatus: event.leadStatus,
      );
      emit(state.copyWith(
        status: LeadsStatus.success,
        items: page.items,
        pageNumber: page.pageNumber,
        totalPages: page.totalPages,
        totalCount: page.totalCount,
        isLoadingMore: false,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(status: LeadsStatus.failure, errorMessage: e.message));
    } catch (_) {
      emit(state.copyWith(
        status: LeadsStatus.failure,
        errorMessage: 'Something went wrong. Please try again.',
      ));
    }
  }

  // Jump to a specific page (numbered pagination) — REPLACES the current list
  // instead of appending. Keeps the old items visible while the page loads.
  Future<void> _onPageSelected(
    LeadsPageSelected event,
    Emitter<LeadsState> emit,
  ) async {
    emit(state.copyWith(
      status: LeadsStatus.loading,
      search: event.search,
      leadStatus: event.leadStatus,
      errorMessage: null,
    ));
    try {
      final page = await _repository.getLeads(
        page: event.page,
        limit: pageLimit,
        search: event.search,
        leadStatus: event.leadStatus,
      );
      emit(state.copyWith(
        status: LeadsStatus.success,
        items: page.items,
        pageNumber: page.pageNumber,
        totalPages: page.totalPages,
        totalCount: page.totalCount,
        isLoadingMore: false,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(status: LeadsStatus.failure, errorMessage: e.message));
    } catch (_) {
      emit(state.copyWith(
        status: LeadsStatus.failure,
        errorMessage: 'Something went wrong. Please try again.',
      ));
    }
  }

  // Append the next page when the user scrolls to the bottom.
  Future<void> _onNextPage(
    LeadsNextPageRequested event,
    Emitter<LeadsState> emit,
  ) async {
    if (state.status != LeadsStatus.success ||
        state.isLoadingMore ||
        !state.hasMore) {
      return;
    }
    emit(state.copyWith(isLoadingMore: true));
    try {
      final page = await _repository.getLeads(
        page: state.pageNumber + 1,
        limit: pageLimit,
        search: state.search,
        leadStatus: state.leadStatus,
      );
      emit(state.copyWith(
        items: [...state.items, ...page.items],
        pageNumber: page.pageNumber,
        totalPages: page.totalPages,
        totalCount: page.totalCount,
        isLoadingMore: false,
      ));
    } catch (_) {
      // Keep what we have; just stop the bottom spinner.
      emit(state.copyWith(isLoadingMore: false));
    }
  }
}
