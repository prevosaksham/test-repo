part of 'dashboard_bloc.dart';

enum DashboardStatus { initial, loading, success, failure }

class DashboardState extends Equatable {
  const DashboardState({
    this.status = DashboardStatus.initial,
    this.stats = const DashboardStats(),
    this.calls = const [],
    this.visits = const [],
    this.errorMessage,
  });

  final DashboardStatus status;
  final DashboardStats stats;
  final List<FollowupItem> calls; // followupType == call
  final List<FollowupItem> visits; // followupType == visit
  final String? errorMessage;

  bool get isLoading => status == DashboardStatus.loading;

  DashboardState copyWith({
    DashboardStatus? status,
    DashboardStats? stats,
    List<FollowupItem>? calls,
    List<FollowupItem>? visits,
    String? errorMessage,
  }) {
    return DashboardState(
      status: status ?? this.status,
      stats: stats ?? this.stats,
      calls: calls ?? this.calls,
      visits: visits ?? this.visits,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, stats, calls, visits, errorMessage];
}
