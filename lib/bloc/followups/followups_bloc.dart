import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_exception.dart';
import '../../data/models/followup_item.dart';
import '../../data/repositories/dashboard_repository.dart';

part 'followups_event.dart';
part 'followups_state.dart';

/// Drives the "View All" follow-ups screen.
///
/// The backend `/followup/list` returns ALL follow-ups (it ignores any
/// `followupType` filter), so we fetch the full list once and do the tab split
/// (call / visit), search (Lead ID / name), and pagination client-side. A tab
/// switch, page change, or search is therefore instant; only the first load and
/// pull-to-refresh hit the network.
class FollowupsBloc extends Bloc<FollowupsEvent, FollowupsState> {
  FollowupsBloc({required DashboardRepository repository, this.pageSize = 10})
      : _repository = repository,
        super(const FollowupsState()) {
    on<FollowupsTabChanged>(_onTabChanged);
    on<FollowupsPageRequested>(_onPageRequested);
    on<FollowupsSearchChanged>(_onSearchChanged);
    on<FollowupsRefreshed>(_onRefreshed);
  }

  final DashboardRepository _repository;
  final int pageSize;

  // Full unfiltered list cached from the last network fetch.
  List<FollowupItem> _all = const [];
  bool _loaded = false;

  Future<void> _onTabChanged(
    FollowupsTabChanged event,
    Emitter<FollowupsState> emit,
  ) async {
    if (!_loaded) {
      await _fetch(emit, kind: event.kind, search: state.search);
    } else {
      _emitView(emit, kind: event.kind, page: 1, search: state.search);
    }
  }

  void _onPageRequested(
    FollowupsPageRequested event,
    Emitter<FollowupsState> emit,
  ) {
    _emitView(emit, kind: state.kind, page: event.page, search: state.search);
  }

  void _onSearchChanged(
    FollowupsSearchChanged event,
    Emitter<FollowupsState> emit,
  ) {
    // Searching always resets to page 1, so a match that lived on a later page
    // surfaces immediately.
    _emitView(emit, kind: state.kind, page: 1, search: event.search);
  }

  Future<void> _onRefreshed(
    FollowupsRefreshed event,
    Emitter<FollowupsState> emit,
  ) =>
      _fetch(emit, kind: state.kind, search: state.search);

  Future<void> _fetch(
    Emitter<FollowupsState> emit, {
    required FollowupKind kind,
    required String search,
  }) async {
    emit(state.copyWith(
      status: FollowupsStatus.loading,
      kind: kind,
      search: search,
      errorMessage: null,
    ));
    try {
      _all = await _repository.getAllFollowups();
      _loaded = true;
      _emitView(emit, kind: kind, page: 1, search: search);
    } on ApiException catch (e) {
      emit(state.copyWith(
        status: FollowupsStatus.failure,
        errorMessage: e.message,
      ));
    } catch (_) {
      emit(state.copyWith(
        status: FollowupsStatus.failure,
        errorMessage: 'Something went wrong. Please try again.',
      ));
    }
  }

  /// Filters the cached list by tab + search, then slices the requested page.
  void _emitView(
    Emitter<FollowupsState> emit, {
    required FollowupKind kind,
    required int page,
    required String search,
  }) {
    final q = search.trim().toLowerCase();
    final filtered = _all.where((f) {
      if (f.kind != kind) return false;
      if (q.isEmpty) return true;
      return f.leadNo.toLowerCase().contains(q) ||
          f.leadName.toLowerCase().contains(q);
    }).toList();

    final total = filtered.length;
    final totalPages = total == 0 ? 1 : (total / pageSize).ceil();
    final current = page.clamp(1, totalPages);
    final start = (current - 1) * pageSize;
    final end = math.min(start + pageSize, total);
    final items = start < total
        ? filtered.sublist(start, end)
        : const <FollowupItem>[];

    emit(state.copyWith(
      status: FollowupsStatus.success,
      kind: kind,
      search: search,
      items: items,
      pageNumber: current,
      totalPages: totalPages,
      totalCount: total,
      errorMessage: null,
    ));
  }
}
